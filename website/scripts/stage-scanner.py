"""Stage a demo QR in a real Google scanner capture; retain native scanner chrome."""
from pathlib import Path
from PIL import Image, ImageOps
import math
root=Path(__file__).resolve().parents[1]
source=Image.open(root/'assets/captures/android-scanner.png').convert('RGBA')
w,h=source.size
feed=ImageOps.fit(Image.open(root/'assets/brands/vscode-blurred.jpg').convert('RGBA'),(w,h))
card=Image.open(root/'video/public/mac-pairing.jpg').convert('RGBA').crop((398,0,1042,1000))
card=card.resize((990,1537),Image.Resampling.LANCZOS)
feed.alpha_composite(card,(145,620))
# Preserve the real OS status/navigation bars and scanner title/close affordance.
feed.paste(source.crop((0,0,w,156)),(0,0))
feed.paste(source.crop((0,h-75,w,h)),(0,h-75))
chrome=Image.new('RGBA',(w,h),(0,0,0,0))
a=source.load(); b=chrome.load()
colors=[(66,133,244),(251,188,5),(52,168,83),(234,67,53)]
for y in range(156,h-75):
    for x in range(w):
        r,g,bl,alpha=a[x,y]
        header=y<345 and (((x-101)**2+(y-260)**2<46**2) or (min(r,g,bl)>220))
        reticle=250<x<1035 and 1000<y<1910 and any((r-c[0])**2+(g-c[1])**2+(bl-c[2])**2<1700 for c in colors)
        footer=y>2600 and max(r,g,bl)-min(r,g,bl)<25 and min(r,g,bl)>135
        if header or reticle or footer: b[x,y]=(r,g,bl,255)
feed.alpha_composite(chrome)
feed.convert('RGB').save(root/'video/public/android-scanner-staged.webp',quality=94)
Image.open(root/'assets/captures/android-scanner.png').save(root/'video/public/android-scanner.webp',quality=94)

# Keep the clock consistent across this staged phone sequence, using actual OS pixels.
paired=Image.open(root/'video/public/android-pairing.webp').convert('RGB')
result=feed.convert('RGB')
for y in range(150):
    for x in range(330):
        pixel=paired.getpixel((x,y))
        result.putpixel((x,y),pixel if min(pixel)<120 else (255,255,255))
result.save(root/'video/public/android-scanner-staged.webp',quality=94)
