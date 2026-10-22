"""Composes the README images from the store assets.

Output: docs/images/banner.png       (1280x640, also usable as the GitHub social preview)
        docs/images/screenshots.png  (the five English store screenshots side by side)
Run after compose_store_assets.py.
"""
from pathlib import Path
from PIL import Image, ImageDraw

from compose_store_assets import BOLD, MEDIUM, MINT, ROOT, WHITE, font, gradient, phone

OUT = Path(__file__).resolve().parents[2] / 'docs' / 'images'


def banner():
    w, h = 1280, 640
    img = gradient(w, h).convert('RGBA')
    icon = Image.open(ROOT / 'play_icon_512.png').convert('RGBA').resize((150, 150), Image.LANCZOS)
    mask = Image.new('L', icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 149, 149], radius=36, fill=255)
    img.paste(icon, (90, 150), mask)
    d = ImageDraw.Draw(img)
    d.text((90, 330), 'Extracter', font=font(BOLD, 104), fill=WHITE)
    y = 460
    for line in ('Any audio or video to text.', 'Fully offline, on your device.'):
        d.text((94, y), line, font=font(MEDIUM, 40), fill=MINT)
        y += 54
    # Two real screens in the right half, the back one offset down.
    for name, x, top in (('en_3_transcript', 975, 150), ('en_1_transcribe', 735, 90)):
        device = phone(Image.open(ROOT / 'raw' / f'{name}.png').convert('RGB'))
        dh = 560
        device = device.resize((device.width * dh // device.height, dh), Image.LANCZOS)
        img.alpha_composite(device, (x, top))
    return img.convert('RGB')


def strip():
    shots = [Image.open(ROOT / 'en' / f'phone_{n}.png').convert('RGB') for n in range(1, 6)]
    sw, gap = 360, 24
    sh = shots[0].height * sw // shots[0].width
    # Transparent, so the rounded corners look right in GitHub's light and dark themes.
    img = Image.new('RGBA', (5 * sw + 4 * gap, sh), (0, 0, 0, 0))
    for i, shot in enumerate(shots):
        small = shot.resize((sw, sh), Image.LANCZOS)
        mask = Image.new('L', (sw, sh), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=28, fill=255)
        img.paste(small, (i * (sw + gap), 0), mask)
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    banner().save(OUT / 'banner.png', optimize=True)
    strip().save(OUT / 'screenshots.png', optimize=True)
    print('wrote', OUT)


if __name__ == '__main__':
    main()
