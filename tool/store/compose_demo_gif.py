"""Builds docs/images/demo.gif from the frames of integration_test/demo_gif_test.dart.

Input : build/demo_frames/<index>_<hold ms>.png   (540x960 app frames)
Output: docs/images/demo.gif                        (phone mockup on the brand gradient)
Needs the ffmpeg CLI for palette-based GIF encoding.
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

from compose_store_assets import gradient, phone

REPO = Path(__file__).resolve().parents[2]
FRAMES = REPO / 'build' / 'demo_frames'
OUT = REPO / 'docs' / 'images' / 'demo.gif'
W, H = 440, 800


def compose(raw):
    bg = gradient(W, H).convert('RGBA')
    device = phone(raw)
    dh = H - 60
    device = device.resize((device.width * dh // device.height, dh), Image.LANCZOS)
    bg.alpha_composite(device, ((W - device.width) // 2, 30))
    return bg.convert('RGB')


def main():
    frames = sorted(FRAMES.glob('*.png'))
    if not frames:
        raise SystemExit(f'no frames in {FRAMES}; run integration_test/demo_gif_test.dart first')
    with tempfile.TemporaryDirectory() as tmp:
        concat = []
        for i, path in enumerate(frames):
            hold_ms = int(path.stem.split('_')[1])
            out = Path(tmp) / f'{i:03d}.png'
            compose(Image.open(path).convert('RGB')).save(out)
            concat += [f"file '{out}'", f'duration {hold_ms / 1000:.2f}']
        concat.append(f"file '{out}'")  # concat demuxer needs the last frame repeated
        listing = Path(tmp) / 'frames.txt'
        listing.write_text('\n'.join(concat))
        OUT.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ['ffmpeg', '-loglevel', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(listing),
             '-vf', 'split[a][b];[a]palettegen=max_colors=128:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a',
             '-loop', '0', str(OUT)],
            check=True,
        )
    print('wrote', OUT, f'{OUT.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
