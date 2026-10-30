"""Trim idle gaps only. No playback-rate, interpolation, or animation-speed changes."""
from pathlib import Path
from PIL import Image
from concurrent.futures import ThreadPoolExecutor
import subprocess, os, json, sys
root=Path(__file__).resolve().parents[1]
source=Path(sys.argv[1])
ffdir=root/'video/node_modules/@remotion/compositor-darwin-arm64'
env=dict(os.environ,DYLD_LIBRARY_PATH=str(ffdir))
clips=[('pairing',0,4.5),('arrival',10.8,3),('music',18.1,4),
       ('reply-expand',31,1.6),('reply-open',34.2,1.1),('reply-type',43,1.4),('reply-send',50.3,1.4),
       ('search',58.7,3),('search-clear',66.4,.7),('collapse',70.65,.8),('dismiss',77.0,2.8),('cloud',84.1,4)]
out=root/'video/public/native';out.mkdir(exist_ok=True)
def encode(clip):
    name,start,duration=clip
    subprocess.run([str(ffdir/'ffmpeg'),'-v','error','-ss',str(start),'-i',str(source),'-t',str(duration),
      '-vf','crop=1600:1700:1600:64','-c:v','libx264','-preset','fast','-crf','14','-threads','2',
      '-pix_fmt','yuv420p','-r','60','-fps_mode','cfr','-an','-movflags','+faststart','-y',str(out/(name+'.mp4'))],check=True,env=env)
    tail=out/(name+'-tail.png')
    subprocess.run([str(ffdir/'ffmpeg'),'-v','error','-ss',str(duration-1/60),
      '-i',str(out/(name+'.mp4')),'-frames:v','1','-y',str(tail)],check=True,env=env)
    Image.open(tail).save(out/(name+'-tail.webp'),quality=95)
    tail.unlink()
    print('Prepared',name,flush=True)
with ThreadPoolExecutor(max_workers=3) as pool:list(pool.map(encode,clips))
(out/'timeline.json').write_text(json.dumps([dict(name=n,sourceStart=s,duration=d,playbackRate=1) for n,s,d in clips],indent=2)+'\n')
