"""Extract feature screenshots from the recorded native UI, without demo overlays."""
from pathlib import Path
from PIL import Image
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
ffdir = root / 'video/node_modules/@remotion/compositor-darwin-arm64'
env = dict(os.environ, DYLD_LIBRARY_PATH=str(ffdir))
assets = root / 'public/assets'
# Coordinates reference the 1600 × 1700 native column, before editorial zooms.
shots = [
    ('media', 'music', 1, (90, 40, 1430, 1110)),
    ('reply', 'reply-send', .15, (90, 450, 1430, 1530)),
    ('search', 'search', 1.1, (90, 40, 1430, 1050)),
    ('dismiss', 'dismiss', .05, (90, 40, 1430, 1050)),
    ('wifi', 'cloud', .2, (90, 40, 1430, 455)),
    ('cloud', 'cloud', 2, (90, 40, 1430, 455)),
]
with tempfile.TemporaryDirectory(prefix='phone-check-features-') as temp:
    for name, clip, at, crop in shots:
        frame = Path(temp) / (name + '.png')
        subprocess.run([
            str(ffdir / 'ffmpeg'), '-v', 'error', '-ss', str(at),
            '-i', str(root / 'video/public/native' / (clip + '.mp4')),
            '-frames:v', '1', '-y', str(frame),
        ], check=True, env=env)
        Image.open(frame).crop(crop).save(assets / ('feature-' + name + '.webp'), quality=94)
Image.open(root / 'assets/captures/android-pairing.png').save(assets / 'android-pairing.webp', quality=92)
print('Prepared six native feature screenshots and Android pairing capture.')

# Two genuine native headers in one diagonal composition. App pixels stay intact.
from PIL import ImageDraw, ImageOps, ImageFilter
size = (1600, 560)
backdrop = ImageOps.fit(Image.open(root / 'assets/brands/vscode-blurred.jpg').convert('RGB'), size)
left = backdrop.copy().convert('RGBA')
right = backdrop.copy().convert('RGBA')
left.alpha_composite(Image.new('RGBA', size, (4, 65, 216, 105)))
right.alpha_composite(Image.new('RGBA', size, (117, 88, 178, 105)))
for layer, name, position in [(left, 'wifi', (25, 125)), (right, 'cloud', (795, 195))]:
    image = Image.open(assets / ('feature-' + name + '.webp')).convert('RGBA')
    image = image.resize((780, 242), Image.Resampling.LANCZOS)
    edge = Image.new('L', image.size, 0)
    ImageDraw.Draw(edge).rectangle((10, 10, 770, 232), fill=255)
    image.putalpha(edge.filter(ImageFilter.GaussianBlur(8)).point(lambda v: round(v * .18)))
    layer.alpha_composite(image, position)
    # Enlarge the same native SF Symbol used by the app, rather than enlarging
    # the screenshot's small raster glyph. Keep the actual panel faint behind it.
    symbol = Image.open(root / 'assets/brands' / ('native-' + name + '.png')).convert('RGBA')
    symbol = symbol.crop(symbol.getbbox())
    symbol.thumbnail((245, 230), Image.Resampling.LANCZOS)
    center = (400, 250) if name == 'wifi' else (1200, 310)
    layer.alpha_composite(symbol, (center[0] - symbol.width // 2, center[1] - symbol.height // 2))
mask = Image.new('L', size, 0)
ImageDraw.Draw(mask).polygon([(950, 0), (1600, 0), (1600, 560), (650, 560)], fill=255)
combined = Image.composite(right, left, mask).convert('RGB')
ImageDraw.Draw(combined).line([(950, 0), (650, 560)], fill=(145, 154, 221), width=2)
combined.save(assets / 'feature-connection.webp', quality=95)
