"""Generate the abstract artwork used by reading reports, keepsakes and the
theme picker (assets/report/ and assets/reading_previews/).

The upstream illustrations were not published with the source, so Shiori
draws its own scenes from each theme's palette. Deterministic: the same seed
always produces the same files.

    uv run --with pillow python tools/generate_report_art.py
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
REPORT = ROOT / 'assets' / 'report'
PREVIEWS = ROOT / 'assets' / 'reading_previews'
LANDSCAPE = (1600, 1000)
PORTRAIT = (1000, 1600)


def rgb(value: int) -> tuple[int, int, int]:
    return (value >> 16) & 255, (value >> 8) & 255, value & 255


def mix(a, b, t: float):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(size, top, bottom) -> Image.Image:
    w, h = size
    image = Image.new('RGB', size)
    draw = ImageDraw.Draw(image)
    for y in range(h):
        draw.line([(0, y), (w, y)], fill=mix(top, bottom, y / max(1, h - 1)))
    return image


def glow(image, center, radius, color, strength=0.55):
    layer = Image.new('RGB', image.size, (0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius], fill=color)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.6))
    mask = layer.convert('L').point(lambda v: min(255, int(v * strength)))
    image.paste(color, mask=mask)


def ridge(w, base, amplitude, rng, roughness=7):
    points, phase = [], [rng.uniform(0, math.tau) for _ in range(4)]
    for x in range(0, w + 41, 40):
        y = base
        for k in range(1, 5):
            y += amplitude / k * math.sin(x / (w / (roughness * k / 3)) + phase[k - 1])
        points.append((x, y))
    return points


def layered_hills(image, colors, rng, start=0.45, step=0.11, amplitude=60, shadow=False):
    w, h = image.size
    for i, color in enumerate(colors):
        base = h * (start + i * step)
        polygon = ridge(w, base, amplitude * (1 - i * 0.12), rng) + [(w + 40, h), (0, h)]
        if shadow:
            shade = Image.new('L', image.size, 0)
            ImageDraw.Draw(shade).polygon([(x, y - 14) for x, y in polygon], fill=110)
            shade = shade.filter(ImageFilter.GaussianBlur(18))
            image.paste((0, 0, 0), mask=shade.point(lambda v: v // 2))
        ImageDraw.Draw(image).polygon(polygon, fill=color)


def archive(size, rng):
    paper, ink, accent = rgb(0xf4f3ef), rgb(0x24312e), rgb(0x2a8178)
    image = gradient(size, paper, mix(paper, accent, 0.12))
    draw = ImageDraw.Draw(image)
    w, h = size
    x = w * 0.12
    while x < w * 0.88:
        width = rng.randint(int(w * 0.035), int(w * 0.07))
        top = h * rng.uniform(0.22, 0.42)
        tone = mix(paper, rng.choice([accent, ink, rgb(0x9b8141)]), rng.uniform(0.25, 0.8))
        draw.rounded_rectangle([x, top, x + width, h * 0.86], radius=6, fill=tone)
        draw.line([(x + width * 0.2, top + 30), (x + width * 0.8, top + 30)], fill=mix(tone, paper, 0.6), width=3)
        x += width + rng.randint(4, 14)
    draw.rectangle([0, h * 0.86, w, h * 0.89], fill=mix(ink, paper, 0.25))
    return image


def harbor(size, rng):
    deep, mist, accent = rgb(0x141e26), rgb(0x3b5560), rgb(0x8db9b0)
    image = gradient(size, mix(deep, mist, 0.7), deep)
    w, h = size
    glow(image, (w * 0.7, h * 0.32), min(w, h) * 0.12, mix(accent, (255, 255, 255), 0.4), 0.7)
    layered_hills(image, [mix(deep, mist, t) for t in (0.55, 0.38, 0.2)], rng, start=0.5, step=0.07, amplitude=26)
    draw = ImageDraw.Draw(image)
    draw.rectangle([w * 0.2, h * 0.47, w * 0.205, h * 0.62], fill=mix(accent, deep, 0.2))
    glow(image, (w * 0.2025, h * 0.46), 18, rgb(0xf3d48c), 0.9)
    for i in range(22):
        y = h * (0.66 + i * 0.016)
        x0 = w * rng.uniform(0.0, 0.5)
        draw.line([(x0, y), (x0 + w * rng.uniform(0.15, 0.5), y)], fill=mix(deep, accent, rng.uniform(0.08, 0.25)), width=2)
    return image.filter(ImageFilter.GaussianBlur(1.2))


SEASONS = {
    'spring': (rgb(0xf6ece9), rgb(0xe3b5bf), rgb(0x7b8d62)),
    'summer': (rgb(0xeef5ef), rgb(0x8fc1a4), rgb(0x3f7d63)),
    'autumn': (rgb(0xf5ede0), rgb(0xd99a5b), rgb(0x9b5a3a)),
    'winter': (rgb(0xeef1f4), rgb(0xb7c6d4), rgb(0x5a6f83)),
}


def season(name):
    def draw_season(size, rng):
        sky, petal, ground = SEASONS[name]
        image = gradient(size, sky, mix(sky, petal, 0.35))
        w, h = size
        if name == 'summer':
            glow(image, (w * 0.75, h * 0.25), min(w, h) * 0.13, (255, 236, 180), 0.85)
        layered_hills(image, [mix(ground, sky, 0.55), mix(ground, sky, 0.3), ground], rng, start=0.58, step=0.1, amplitude=40)
        draw = ImageDraw.Draw(image)
        for _ in range(140 if name in ('spring', 'winter') else 70):
            x, y = rng.uniform(0, w), rng.uniform(0, h * 0.85)
            r = rng.uniform(3, 11)
            color = (255, 255, 255) if name == 'winter' else mix(petal, (255, 255, 255), rng.uniform(0, 0.4))
            if name == 'autumn':
                draw.polygon([(x, y - r), (x + r * 0.7, y), (x, y + r), (x - r * 0.7, y)], fill=mix(petal, ground, rng.uniform(0, 0.6)))
            else:
                draw.ellipse([x - r, y - r, x + r, y + r], fill=color)
        return image
    return draw_season


def night_desk(size, rng):
    night, gold = rgb(0x0e1116), rgb(0xd9b66f)
    image = gradient(size, rgb(0x1a2230), night)
    w, h = size
    draw = ImageDraw.Draw(image)
    window = [w * 0.55, h * 0.12, w * 0.88, h * 0.58]
    draw.rectangle(window, fill=rgb(0x18243a))
    for _ in range(60):
        x, y = rng.uniform(window[0], window[2]), rng.uniform(window[1], window[3])
        r = rng.uniform(1, 2.6)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=mix(gold, (255, 255, 255), 0.6))
    glow(image, (w * 0.8, h * 0.24), 40, (245, 232, 200), 0.95)
    draw = ImageDraw.Draw(image)
    draw.line([(window[0], window[1] + (window[3] - window[1]) / 2), (window[2], window[1] + (window[3] - window[1]) / 2)], fill=night, width=8)
    draw.line([((window[0] + window[2]) / 2, window[1]), ((window[0] + window[2]) / 2, window[3])], fill=night, width=8)
    draw.rectangle([0, h * 0.72, w, h], fill=rgb(0x15110d))
    glow(image, (w * 0.28, h * 0.62), min(w, h) * 0.22, gold, 0.6)
    draw = ImageDraw.Draw(image)
    draw.polygon([(w * 0.22, h * 0.5), (w * 0.34, h * 0.5), (w * 0.31, h * 0.6), (w * 0.25, h * 0.6)], fill=gold)
    draw.rounded_rectangle([w * 0.36, h * 0.66, w * 0.6, h * 0.72], radius=4, fill=rgb(0xece5d4))
    return image


def papercut(size, rng):
    image = gradient(size, rgb(0x34332f), rgb(0x272727))
    w, h = size
    glow(image, (w * 0.62, h * 0.3), min(w, h) * 0.15, rgb(0xdad5c7), 0.5)
    tones = [mix(rgb(0x272727), rgb(0xf2efe7), t) for t in (0.75, 0.55, 0.38, 0.22, 0.1)]
    layered_hills(image, tones, rng, start=0.38, step=0.11, amplitude=70, shadow=True)
    return image


def curtain_open(size, rng):
    black, brass, cream = rgb(0x0b0c0e), rgb(0xb99a6b), rgb(0xeee4ce)
    image = gradient(size, rgb(0x15171b), black)
    w, h = size
    light = Image.new('L', size, 0)
    ImageDraw.Draw(light).polygon([(w * 0.42, 0), (w * 0.58, 0), (w * 0.78, h), (w * 0.22, h)], fill=120)
    image.paste(mix(brass, cream, 0.5), mask=light.filter(ImageFilter.GaussianBlur(60)))
    draw = ImageDraw.Draw(image)
    for side in (0, 1):
        for i in range(9):
            x = w * (0.02 + i * 0.022) if side == 0 else w * (0.98 - i * 0.022)
            draw.line([(x, 0), (x + (12 if side == 0 else -12), h)], fill=mix(rgb(0x5a1f1f), black, i / 12), width=int(w * 0.024))
    draw.ellipse([w * 0.35, h * 0.86, w * 0.65, h * 0.94], fill=mix(brass, black, 0.4))
    return image


def mountain_dawn(size, rng):
    paper, ink, accent = rgb(0xf5f0e6), rgb(0x303b34), rgb(0x9d704d)
    image = gradient(size, mix(paper, accent, 0.18), paper)
    w, h = size
    glow(image, (w * 0.66, h * 0.36), min(w, h) * 0.09, mix(accent, (255, 210, 170), 0.5), 0.9)
    layers = [mix(paper, ink, t) for t in (0.18, 0.32, 0.5, 0.72)]
    layered_hills(image, layers, rng, start=0.42, step=0.12, amplitude=90)
    return image.filter(ImageFilter.GaussianBlur(0.8))


def train(size, rng):
    sky, navy, orange = rgb(0xf2f8fb), rgb(0x1b3d54), rgb(0xe47843)
    image = gradient(size, rgb(0xaecedf), sky)
    w, h = size
    glow(image, (w * 0.2, h * 0.3), min(w, h) * 0.1, (255, 244, 220), 0.8)
    draw = ImageDraw.Draw(image)
    for _ in range(5):
        x, y = rng.uniform(0, w), rng.uniform(h * 0.08, h * 0.35)
        for k in range(4):
            r = rng.uniform(30, 60)
            draw.ellipse([x + k * 45 - r, y - r * 0.6, x + k * 45 + r, y + r * 0.6], fill=(255, 255, 255))
    layered_hills(image, [mix(sky, rgb(0x6f9a8a), 0.5), rgb(0x6f9a8a)], rng, start=0.55, step=0.08, amplitude=30)
    track = h * 0.74
    draw.rectangle([0, track + 34, w, track + 40], fill=mix(navy, sky, 0.3))
    x = w * 0.08
    for car in range(5):
        draw.rounded_rectangle([x, track - 60, x + w * 0.16, track + 30], radius=14, fill=navy if car else orange)
        for k in range(4):
            wx = x + 16 + k * (w * 0.16 - 24) / 4
            draw.rounded_rectangle([wx, track - 44, wx + (w * 0.16 - 48) / 4, track - 10], radius=4, fill=mix(sky, orange, 0.15))
        x += w * 0.165
    return image


THEMES = {
    'char_cover': (archive, LANDSCAPE),
    'scene_mist_harbor': (harbor, LANDSCAPE),
    'scene_mist_harbor_portrait': (harbor, PORTRAIT),
    'char_night_desk': (night_desk, LANDSCAPE),
    'char_papercut': (papercut, LANDSCAPE),
    'char_pv_open': (curtain_open, LANDSCAPE),
    'scene_mountain_dawn': (mountain_dawn, LANDSCAPE),
    'scene_mountain_dawn_portrait': (mountain_dawn, PORTRAIT),
    'char_pv_train': (train, LANDSCAPE),
    **{f'char_season_{name}': (season(name), LANDSCAPE) for name in SEASONS},
}

PREVIEW_SOURCES = {
    'archive': archive, 'shelf': harbor, 'editorial': season('spring'),
    'constellation': night_desk, 'signal': papercut, 'score': curtain_open,
    'ink': mountain_dawn, 'festival': train,
}


def main():
    REPORT.mkdir(parents=True, exist_ok=True)
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    for name, (painter, size) in THEMES.items():
        painter(size, random.Random(name)).save(REPORT / f'{name}.webp', quality=82, method=6)
    for name, painter in PREVIEW_SOURCES.items():
        image = painter(LANDSCAPE, random.Random(name)).resize((600, 375), Image.LANCZOS)
        image.save(PREVIEWS / f'{name}-117.webp', quality=82, method=6)
    print('wrote', len(THEMES), 'report images and', len(PREVIEW_SOURCES), 'previews')


if __name__ == '__main__':
    main()
