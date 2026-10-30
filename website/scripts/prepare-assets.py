"""Prepare native production captures; crop window chrome, never app pixels."""
from pathlib import Path
from PIL import Image
root = Path(__file__).resolve().parents[1]
assets = root / 'public/assets'
captures = root / 'assets/captures'
video = root / 'video/public'
video.mkdir(exist_ok=True)
image = Image.open(captures / 'mac-expanded-raw.png').convert('RGB')
image.crop((120,64,1320,1064)).save(assets/'mac-notifications.jpg',quality=92)
Image.open(captures/'android-connected.png').save(assets/'android-connected.webp',quality=92)
(video/'android-connected.webp').write_bytes((assets/'android-connected.webp').read_bytes())
for name in ['before','arrived','paused','dismissed','cloud','pairing']:
    image = Image.open(captures/f'mac-{name}-raw.png').convert('RGB')
    image.crop((0,64,1440,1064)).save(video/f'mac-{name}.jpg',quality=95)
Image.open(captures/'mac-arrived-raw.png').crop((398,676,1042,790)).save(video/'incoming-card.png')

(video/'galaxy-s26-frame.webp').write_bytes((root/'assets/brands/galaxy-s26-frame.webp').read_bytes())
Image.open(captures/'android-pairing.png').save(video/'android-pairing.webp',quality=92)
