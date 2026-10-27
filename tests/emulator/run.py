#!/usr/bin/env python3
"""End-to-end OS tests on a dedicated emulator; no real phone or production Mac pairing."""
import argparse
from datetime import datetime, timezone
import json
import os
import re
from pathlib import Path
import shutil
import socket
import socketserver
import subprocess
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--serial', default='emulator-5554')
parser.add_argument('--skip-build', action='store_true')
parser.add_argument('--suite', action='append', help='Run a selected instrumented suite')
parser.add_argument('--native-alerts', action='store_true', help='Request authorization for the isolated Mac test app and test native delivery')
args = parser.parse_args()
adb = shutil.which('adb') or str(Path(os.environ['ANDROID_HOME']) / 'platform-tools/adb')

def device(*parts, **kwargs):
    kwargs.setdefault("timeout", 180)
    return subprocess.run([adb, '-s', args.serial, *parts], check=True, capture_output=True, **kwargs)

def wait_for(label, predicate, seconds=30):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(.1)
    raise RuntimeError('Timed out: ' + label)

# Never clear data or modify permissions on a physical device.
if not args.serial.startswith('emulator-') or device('shell', 'getprop', 'ro.kernel.qemu').stdout.strip() != b'1':
    raise RuntimeError('Use a dedicated Android Emulator')
api = int(device('shell', 'getprop', 'ro.build.version.sdk').stdout.strip())
if api < 37:
    raise RuntimeError('These tests require an API 37+ emulator')
with socket.socket() as probe:
    if probe.connect_ex(('127.0.0.1', 47831)) == 0:
        raise RuntimeError('Quit the Mac companion before running the test host')

if not args.skip_build:
    subprocess.run([str(ROOT/'android/gradlew'), '-p', str(ROOT/'android'), ':app:assembleDebug',
                    ':app:assembleDebugAndroidTest', ':notification-fixture:assembleDebug'], check=True)
    subprocess.run([str(ROOT/'tests/emulator/build-mac-host.sh')], check=True)

for apk in ['android/app/build/outputs/apk/debug/app-debug.apk',
            'android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk',
            'android/notification-fixture/build/outputs/apk/debug/notification-fixture-debug.apk']:
    device('install', '-r', '-t', str(ROOT/apk))
device('shell', 'pm', 'clear', 'dev.phonecheck')
device('shell', 'wm', 'dismiss-keyguard')
device('shell', 'cmd', 'notification', 'disallow_listener', 'dev.phonecheck/dev.phonecheck.NotificationBridge')
device('shell', 'pm', 'revoke', 'dev.phonecheck', 'android.permission.ACCESS_LOCAL_NETWORK')
device('shell', 'pm', 'grant', 'dev.phonecheck.fixture', 'android.permission.POST_NOTIFICATIONS')
device('shell', 'settings', 'put', 'global', 'window_animation_scale', '0')
device('shell', 'settings', 'put', 'global', 'transition_animation_scale', '0')
device('shell', 'settings', 'put', 'global', 'animator_duration_scale', '0')

with tempfile.TemporaryDirectory(prefix='phonecheck-e2e-') as temp:
    directory = Path(temp)
    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            request = json.loads(self.rfile.readline(32768))
            if request['action'] in ['dismiss', 'perform', 'reply', 'open', 'native', 'authorize']:
                pending = directory/'command.next'
                pending.write_text(json.dumps(request))
                pending.replace(directory/'command.json')
            self.wfile.write((directory/'state.json').read_bytes() + b'\n')
    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True
    server = Server(('127.0.0.1', 47832), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    environment = dict(os.environ, PHONECHECK_E2E_DIR=temp)
    log = open(directory/'host.log', 'wb')
    host = subprocess.Popen([str(ROOT/'macos/build/PhoneCheckE2E.app/Contents/MacOS/PhoneCheckE2E')],
                            env=environment, stdout=log, stderr=log)
    try:
        wait_for('Mac pairing window', lambda: (directory/'pairing').exists() or host.poll() is not None)
        if host.poll() is not None:
            raise RuntimeError('Mac test host exited: ' + (directory/'host.log').read_text())
        # Transfer a short-lived test credential privately, never via process arguments or logs.
        device('shell', 'run-as', 'dev.phonecheck', 'mkdir', '-p', 'files')
        device('shell', 'run-as', 'dev.phonecheck', 'sh', '-c', '"cat > files/e2e-pairing"',
               input=(directory/'pairing').read_bytes())
        reports = ROOT/'android/app/build/reports/emulator'
        reports.mkdir(parents=True, exist_ok=True)
        completed = []
        suites = args.suite or ['PermissionUiTest', 'NotificationFlowTest', 'RichNotificationTest']
        if args.native_alerts: suites.append('NativeAlertSmokeTest')
        if suites[0] != 'PermissionUiTest':
            device('shell', 'cmd', 'notification', 'allow_listener', 'dev.phonecheck/dev.phonecheck.NotificationBridge')
            device('shell', 'pm', 'grant', 'dev.phonecheck', 'android.permission.ACCESS_LOCAL_NETWORK')
        skipped = {}
        for test in suites:
            if test in ['RichNotificationTest', 'NativeAlertSmokeTest']:
                device('shell', 'pm', 'grant', 'dev.phonecheck', 'android.permission.POST_NOTIFICATIONS')
            if test == 'NotificationFlowTest':
                device('shell', 'pm', 'grant', 'dev.phonecheck', 'android.permission.ACCESS_LOCAL_NETWORK')
            result = device('shell', 'am', 'instrument', '-w', '-r', '-e', 'class',
                            'dev.phonecheck.' + test, 'dev.phonecheck.test/androidx.test.runner.AndroidJUnitRunner')
            output = result.stdout.decode()
            print(output, flush=True)
            (reports/(test + '.txt')).write_text(output)
            if test == 'PermissionUiTest':
                assert not json.loads((directory/'state.json').read_text())['connected']
                artifacts = ROOT/'android/app/build/reports/emulator'
                artifacts.mkdir(parents=True, exist_ok=True)
                for image in ['pairing-screen.png', 'notification-access-screen.png', 'local-network-screen.png']:
                    data = device('exec-out', 'run-as', 'dev.phonecheck', 'cat', 'files/' + image).stdout
                    (artifacts/image).write_bytes(data)
            if 'FAILURES!!!' in output or 'INSTRUMENTATION_FAILED' in output or not re.search(r'OK \(\d+ tests?\)', output):
                raise RuntimeError(test + ' failed')
            skipped[test] = len(re.findall(r'INSTRUMENTATION_STATUS_CODE: -[34]', output))
            completed.append(test)
        (reports/'testbed-screen.png').write_bytes(device('exec-out', 'run-as', 'dev.phonecheck', 'cat', 'files/testbed-screen.png').stdout)
        summary = {'timestamp': datetime.now(timezone.utc).isoformat(),
                   'serial': args.serial, 'api': api, 'completed': completed, 'skipped': skipped,
                   'mac': 'production Companion/Transport in isolated test bundle',
                   'physical_device': False}
        (reports/'results.json').write_text(json.dumps(summary, indent=2) + '\n')
        print('Emulator UI and end-to-end notification flow passed', flush=True)
    finally:
        (directory/'command.json').write_text(json.dumps({'id': 'cleanup', 'action': 'stop'}))
        try: host.wait(timeout=3)
        except subprocess.TimeoutExpired:
            host.terminate(); host.wait(timeout=3)
        server.shutdown(); server.server_close(); log.close()
        subprocess.run(['security', 'delete-generic-password', '-s', 'dev.phonecheck.mac.e2e.pairing', '-a', 'phone'],
                       capture_output=True)
        device('shell', 'run-as', 'dev.phonecheck', 'rm', '-f', 'files/e2e-pairing')
        device('shell', 'am', 'broadcast', '-n', 'dev.phonecheck.fixture/.FixtureReceiver', '-a', 'fixture.CLEAR_ALL')
        device('shell', 'pm', 'clear', 'dev.phonecheck')
