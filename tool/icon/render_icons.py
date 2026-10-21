"""Renders the Extracter app-icon drafts (and, with --final <name>, all Android
launcher/adaptive sizes plus the 512 px Play icon). Pure Pillow, no SVG tools."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

TEAL = (15, 110, 102)
TEAL_DARK = (10, 79, 73)
MINT = (227, 241, 239)
WHITE = (255, 255, 255)
INK = (26, 26, 24)
S = 1024  # master size


def rounded_bar(d, cx, cy, w, h, fill):
    d.rounded_rectangle([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], radius=w / 2, fill=fill)


def waveform(d, cx, cy, scale, fill, heights=(0.22, 0.48, 0.82, 0.36, 0.66, 0.30, 0.18)):
    n = len(heights)
    bar_w = 0.068 * S * scale
    gap = 0.052 * S * scale
    total = n * bar_w + (n - 1) * gap
    x0 = cx - total / 2 + bar_w / 2
    for i, h in enumerate(heights):
        rounded_bar(d, x0 + i * (bar_w + gap), cy, bar_w, h * S * 0.62 * scale, fill)


def foreground_a(d):
    waveform(d, S / 2, S / 2, 0.9, WHITE)


def foreground_b(d):
    # Sound bars on the left become text lines on the right.
    bar_w, gap = 0.058 * S, 0.042 * S
    x = S * 0.20
    for h in (0.20, 0.44, 0.70, 0.40):
        rounded_bar(d, x, S / 2, bar_w, h * S * 0.62, WHITE)
        x += bar_w + gap
    line_h = 0.062 * S
    left = x + 0.01 * S
    for i, (y, w) in enumerate(((-0.16, 0.30), (0.0, 0.26), (0.16, 0.20))):
        d.rounded_rectangle([left, S / 2 + y * S - line_h / 2, left + w * S, S / 2 + y * S + line_h / 2],
                            radius=line_h / 2, fill=MINT if i else WHITE)


def foreground_c(d):
    # A page with a folded corner: waveform on top, text lines below.
    pw, ph = 0.50 * S, 0.60 * S
    x0, y0 = (S - pw) / 2, (S - ph) / 2
    fold = 0.13 * S
    page = [(x0, y0 + 0.03 * S), (x0 + pw - fold, y0), (x0 + pw, y0 + fold), (x0 + pw, y0 + ph), (x0, y0 + ph)]
    d.rounded_rectangle([x0, y0, x0 + pw, y0 + ph], radius=0.05 * S, fill=WHITE)
    d.polygon([(x0 + pw - fold, y0 - 1), (x0 + pw + 1, y0 - 1), (x0 + pw + 1, y0 + fold)], fill=TEAL)
    d.polygon([(x0 + pw - fold, y0), (x0 + pw - fold, y0 + fold), (x0 + pw, y0 + fold)], fill=MINT)
    waveform(d, S / 2, y0 + ph * 0.32, 0.42, TEAL, heights=(0.3, 0.6, 1.0, 0.5, 0.8, 0.4))
    lh = 0.04 * S
    for y, w in ((0.62, 0.32), (0.76, 0.24)):
        d.rounded_rectangle([x0 + 0.09 * S, y0 + ph * y - lh / 2, x0 + 0.09 * S + w * S, y0 + ph * y + lh / 2],
                            radius=lh / 2, fill=TEAL_DARK)
    del page


DRAFTS = {'a_waveform': foreground_a, 'b_wave_to_text': foreground_b, 'c_page': foreground_c}


def background(size=S):
    """Teal with a soft top-left highlight."""
    bg = Image.new('RGB', (size, size), TEAL)
    glow = Image.new('L', (size, size), 0)
    ImageDraw.Draw(glow).ellipse([-size * 0.3, -size * 0.35, size * 0.8, size * 0.6], fill=60)
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.12))
    return Image.composite(Image.new('RGB', (size, size), (34, 140, 130)), bg, glow)


def foreground(name, size=S, inset=1.0):
    """Transparent foreground; inset < 1 shrinks it into the adaptive-icon safe zone."""
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    DRAFTS[name](ImageDraw.Draw(fg))
    if inset != 1.0:
        small = fg.resize((int(S * inset), int(S * inset)), Image.LANCZOS)
        fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        fg.paste(small, ((S - small.width) // 2, (S - small.height) // 2), small)
    return fg.resize((size, size), Image.LANCZOS)


def full_icon(name, size=S):
    img = background(S).convert('RGBA')
    img.alpha_composite(foreground(name))
    return img.resize((size, size), Image.LANCZOS)


def drafts(out):
    out.mkdir(parents=True, exist_ok=True)
    tiles = []
    for name in DRAFTS:
        icon = full_icon(name, 512)
        icon.save(out / f'draft_{name}.png')
        mask = Image.new('L', (512, 512), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, 511, 511], radius=112, fill=255)
        tile = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
        tile.paste(icon, (0, 0), mask)
        tiles.append(tile)
    sheet = Image.new('RGB', (3 * 512 + 4 * 64, 512 + 128), (246, 246, 243))
    for i, t in enumerate(tiles):
        sheet.paste(t, (64 + i * (512 + 64), 64), t)
    sheet.save(out / 'drafts_sheet.png')


if __name__ == '__main__' and len(sys.argv) == 1:
    root = Path(__file__).resolve().parent
    drafts(root / 'out')
    print('drafts in', root / 'out')


DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
ADAPTIVE_INSET = 0.8  # keeps the mark inside the 66 dp safe zone of the 108 dp layer


def android(name, res):
    for density, scale in DENSITIES.items():
        d = res / f'mipmap-{density}'
        d.mkdir(parents=True, exist_ok=True)
        legacy = int(48 * scale)
        full_icon(name, legacy).convert('RGB').save(d / 'ic_launcher.png')
        mask = Image.new('L', (legacy, legacy), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, legacy - 1, legacy - 1], fill=255)
        rnd = Image.new('RGBA', (legacy, legacy), (0, 0, 0, 0))
        rnd.paste(full_icon(name, legacy), (0, 0), mask)
        rnd.save(d / 'ic_launcher_round.png')
        layer = int(108 * scale)
        background(layer).save(d / 'ic_launcher_background.png')
        fg = foreground(name, layer, ADAPTIVE_INSET)
        fg.save(d / 'ic_launcher_foreground.png')
        # Themed icons (Android 13+): the system tints this alpha mask.
        mono = Image.new('RGBA', fg.size, (255, 255, 255, 0))
        mono.putalpha(fg.getchannel('A'))
        mono.save(d / 'ic_launcher_monochrome.png')
    anydpi = res / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background" />\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
           '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />\n'
           '</adaptive-icon>\n')
    for f in ('ic_launcher.xml', 'ic_launcher_round.xml'):
        (anydpi / f).write_text(xml)


def store(name, out):
    out.mkdir(parents=True, exist_ok=True)
    full_icon(name, 512).convert('RGB').save(out / 'play_icon_512.png')


if __name__ == '__main__' and len(sys.argv) > 2 and sys.argv[1] == '--final':
    root = Path(__file__).resolve().parents[2]
    android(sys.argv[2], root / 'android/app/src/main/res')
    store(sys.argv[2], root / 'store/google_play')
    print('final icons written for', sys.argv[2])
