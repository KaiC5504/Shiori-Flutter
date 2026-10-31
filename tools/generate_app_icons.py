"""Generate Shiori's app icon set from assets/branding/app-icon-source.png.

The source is a paper-cut silhouette with two ribbons. It is recoloured, not
redrawn: masks for the paper, ribbons and drop shadow are keyed out at the
source's own resolution, upsampled, then re-thresholded, so the 4096 px masters
have crisp anti-aliased edges instead of an enlarged JPEG blur.

    uv run --with pillow --with numpy python tools/generate_app_icons.py
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / 'assets' / 'branding'
APPICON = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
MASTER = 4096


def to_image(a: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))


def to_array(image: Image.Image) -> np.ndarray:
    return np.asarray(image).astype(np.float32) / 255


def hexc(value: str) -> np.ndarray:
    value = value.lstrip('#')
    return np.array([int(value[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)


class Layers:
    def __init__(self, source: Image.Image, size: int):
        self.size = size
        self.scale = size / source.size[0]
        px = to_array(source.convert('RGB'))
        r, g, b = px[..., 0], px[..., 1], px[..., 2]
        lum = 0.299 * r + 0.587 * g + 0.114 * b
        bg = float(np.median(np.concatenate([lum[:40, :40].ravel(), lum[-40:, -40:].ravel()])))

        paper = np.clip((px.max(axis=2) - (bg + 0.05)) / 0.55, 0, 1)
        ribbon = np.clip((r - g - 0.06) / 0.15, 0, 1) * paper
        # The colour key stops ~1 px short of the paper edge, which leaves a light halo.
        ribbon = to_array(to_image(ribbon).filter(ImageFilter.MaxFilter(3))) * paper
        shade = np.clip(lum / max(np.percentile(lum[paper > 0.95], 60), 1e-3), 0.75, 1.08)
        soft = to_array(to_image(lum).filter(ImageFilter.GaussianBlur(4)))
        drop = np.clip((bg - 0.02 - soft) / 0.05, 0, 1) * (1 - paper)
        # Sharpened, the shadow inside the ribbon cut-outs reads as grey smudges.
        drop *= 1 - to_array(to_image(ribbon).filter(ImageFilter.MaxFilter(31)))
        panel = to_array(to_image(ribbon).filter(ImageFilter.MinFilter(9)))

        self.paper = self.crisp(paper)
        self.ribbon = self.crisp(ribbon) * self.paper
        self.panel = self.crisp(panel) * self.ribbon
        self.rim = self.ribbon - self.panel
        self.silhouette = self.paper * (1 - self.ribbon)
        self.shade = self.up(shade / 1.1) * 1.1
        self.drop = self.up(drop, blur=self.scale)

    def up(self, a: np.ndarray, blur: float = 0) -> np.ndarray:
        image = to_image(a).resize((self.size, self.size), Image.BICUBIC)
        if blur:
            image = image.filter(ImageFilter.GaussianBlur(blur))
        return to_array(image)

    def crisp(self, a: np.ndarray, width: float = 0.07) -> np.ndarray:
        # A sub-pixel blur irons out JPEG stair-steps before the edge is re-sharpened.
        t = np.clip((self.up(a, blur=0.6 * self.scale) - (0.5 - width)) / (2 * width), 0, 1)
        return t * t * (3 - 2 * t)

    def gradient(self, top: str, bottom: str) -> np.ndarray:
        t = np.linspace(0, 1, self.size, dtype=np.float32)[:, None, None]
        return hexc(top) * (1 - t) + hexc(bottom) * t

    def compose(self, background, silhouette, rim, panel, shadow: float, emboss: bool = True) -> Image.Image:
        out = np.broadcast_to(background, (self.size, self.size, 3)).astype(np.float32).copy()
        out *= 1 - self.drop[..., None] * shadow
        shade = self.shade[..., None] if emboss else 1.0
        for mask, colour in ((self.silhouette, silhouette), (self.rim, rim), (self.panel, panel)):
            m = mask[..., None]
            out = out * (1 - m) + colour * shade * m
        return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    layers = Layers(Image.open(BRANDING / 'app-icon-source.png'), MASTER)
    violet = layers.gradient('#B79CF2', '#7650C9')
    grey = hexc('#9A9A9A')
    icons = {
        'light': layers.compose(hexc('#F2ECE3'), hexc('#24222A'), hexc('#0E0D12'), violet, shadow=0),
        'dark': layers.compose(hexc('#262626'), hexc('#F7F3EE'), hexc('#16151B'), violet, shadow=0.35),
        # iOS recolours the tinted icon from its luminance, so it stays greyscale.
        'tinted': layers.compose(hexc('#000000'), hexc('#FFFFFF'), grey, grey, shadow=0, emboss=False),
    }
    for name, icon in icons.items():
        icon.save(BRANDING / f'app-icon-{name}.png', optimize=True)
        suffix = '' if name == 'light' else f'-{name}'
        icon.resize((1024, 1024), Image.LANCZOS).save(APPICON / f'AppIcon{suffix}.png', optimize=True)
        print(f'{name}: {MASTER}px master + 1024px iOS icon')
    icons['light'].resize((512, 512), Image.LANCZOS).save(BRANDING / 'app-icon.png', optimize=True)


if __name__ == '__main__':
    main()
