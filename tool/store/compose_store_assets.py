"""Composes Google Play marketing assets from raw app captures.

Input : store/google_play/raw/{en,ru}_<n>_<screen>.png  (1080x1920 app renders)
Output: store/google_play/<lang>/phone_<n>.png           (1080x1920 ad-style screenshots)
        store/google_play/<lang>/feature_graphic.png     (1024x500)
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2] / 'store' / 'google_play'
FONT = '/System/Library/Fonts/HelveticaNeue.ttc'
BOLD, MEDIUM = 1, 10
TEAL_TOP, TEAL_BOTTOM = (19, 128, 118), (8, 66, 61)
WHITE, MINT, FRAME = (255, 255, 255), (198, 232, 226), (17, 20, 19)
W, H = 1080, 1920

# Order on the store page: strongest message first.
SCREENS = [
    ('1_transcribe', {
        'en': ('Turn any audio or video into text', 'Text appears as it plays · MP3, MP4, MKV…'),
        'ru': ('Любое аудио и видео\u00a0— в текст', 'Текст появляется сразу · MP3, MP4, MKV…'),
    }),
    ('5_models', {
        'en': ('100% offline and private', 'Nothing is uploaded. Download a model once.'),
        'ru': ('Полностью офлайн и\u00a0приватно', 'Ничего не уходит в сеть. Модель — один раз.'),
    }),
    ('2_history', {
        'en': ('Every transcript, searchable', 'Find any word across all your recordings'),
        'ru': ('Все расшифровки под рукой', 'Поиск по любому слову во всех записях'),
    }),
    ('3_transcript', {
        'en': ('A timestamp for every sentence', 'Export as TXT, SRT or VTT subtitles'),
        'ru': ('Таймкод для каждой фразы', 'Экспорт в TXT, SRT и VTT'),
    }),
    ('4_copy', {
        'en': ('Copy with or without timestamps', 'Clean paragraphs, ready to paste'),
        'ru': ('Копируйте с таймкодами или без', 'Аккуратные абзацы — сразу в заметки'),
    }),
]

FEATURE = {
    'en': ('Extracter', 'Audio & video to text — fully offline'),
    'ru': ('Extracter', 'Аудио и видео в текст — без интернета'),
}


def font(index, size):
    return ImageFont.truetype(FONT, size, index=index)


def gradient(w, h):
    top, bottom = Image.new('RGB', (w, h), TEAL_TOP), Image.new('RGB', (w, h), TEAL_BOTTOM)
    mask = Image.linear_gradient('L').resize((w, h))
    img = Image.composite(bottom, top, mask)
    # Two soft light blobs for depth.
    glow = Image.new('L', (w, h), 0)
    g = ImageDraw.Draw(glow)
    g.ellipse([-w * 0.35, -h * 0.12, w * 0.65, h * 0.38], fill=70)
    g.ellipse([w * 0.55, h * 0.55, w * 1.4, h * 1.15], fill=45)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.12))
    return Image.composite(Image.new('RGB', (w, h), (60, 170, 158)), img, glow)


def wrap(draw, text, fnt, max_w):
    words, lines, line = text.split(' '), [], ''
    for word in words:
        trial = f'{line} {word}'.strip()
        if draw.textlength(trial, font=fnt) <= max_w:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    return lines


def centered_text(draw, y, text, fnt, fill, max_w, spacing):
    for line in wrap(draw, text, fnt, max_w):
        draw.text(((W - draw.textlength(line, font=fnt)) / 2, y), line, font=fnt, fill=fill)
        y += fnt.size + spacing
    return y


def phone(screen):
    """The capture inside a slim device frame with rounded corners and a shadow."""
    sw = 800
    shot = screen.resize((sw, int(screen.height * sw / screen.width)), Image.LANCZOS)
    bezel, radius = 22, 70
    fw, fh = sw + 2 * bezel, shot.height + 2 * bezel
    frame = Image.new('RGBA', (fw, fh), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([0, 0, fw - 1, fh - 1], radius=radius, fill=FRAME)
    mask = Image.new('L', shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, shot.height - 1], radius=radius - bezel, fill=255)
    frame.paste(shot, (bezel, bezel), mask)
    shadow = Image.new('RGBA', (fw + 120, fh + 120), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([60, 70, fw + 60, fh + 70], radius=radius, fill=(0, 0, 0, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(28))
    shadow.alpha_composite(frame, (60, 60))
    return shadow


def screenshot(raw, headline, subline):
    img = gradient(W, H).convert('RGBA')
    d = ImageDraw.Draw(img)
    y = centered_text(d, 120, headline, font(BOLD, 82), WHITE, W - 140, 14)
    centered_text(d, y + 22, subline, font(MEDIUM, 40), MINT, W - 160, 10)
    device = phone(raw)
    # The phone runs off the bottom edge, as in typical store ads.
    img.alpha_composite(device, ((W - device.width) // 2, 470))
    return img.convert('RGB')


def feature_graphic(icon, title, tagline):
    fw, fh = 1024, 500
    img = gradient(fw, fh).convert('RGBA')
    size = 260
    ic = icon.resize((size, size), Image.LANCZOS)
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=60, fill=255)
    shadow = Image.new('RGBA', (size + 80, size + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([40, 50, size + 40, size + 50], radius=60, fill=(0, 0, 0, 90))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)), (50, (fh - size) // 2 - 40))
    img.paste(ic, (90, (fh - size) // 2), mask)
    d = ImageDraw.Draw(img)
    x = 90 + size + 60
    d.text((x, 150), title, font=font(BOLD, 96), fill=WHITE)
    y = 270
    for line in wrap(d, tagline, font(MEDIUM, 40), fw - x - 50):
        d.text((x, y), line, font=font(MEDIUM, 40), fill=MINT)
        y += 52
    return img.convert('RGB')


def main():
    icon = Image.open(ROOT / 'play_icon_512.png').convert('RGBA')
    for lang in ('en', 'ru'):
        out = ROOT / lang
        out.mkdir(parents=True, exist_ok=True)
        for n, (screen, captions) in enumerate(SCREENS, start=1):
            raw = Image.open(ROOT / 'raw' / f'{lang}_{screen}.png').convert('RGB')
            screenshot(raw, *captions[lang]).save(out / f'phone_{n}.png')
        feature_graphic(icon, *FEATURE[lang]).save(out / 'feature_graphic.png')
        print('wrote', out)


if __name__ == '__main__':
    main()
