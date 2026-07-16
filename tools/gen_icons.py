#!/usr/bin/env python3
"""Generates the app icon (comic cat face in the game's pastel style):
web/favicon.png, web/icons/*, assets/icon/icon.png.

Usage: python3 gen_icons.py [project_root]
"""
import os
import sys

from PIL import Image, ImageDraw

INK = (107, 81, 56, 255)        # 0xFF6B5138
CREAM = (245, 233, 211, 255)    # page
FUR = (253, 248, 240, 255)      # cat base
PATCH = (240, 168, 104, 255)    # orange patch
EYE = (74, 54, 40, 255)
PINK = (242, 196, 196, 255)
NOSE = (232, 154, 154, 255)
BLUSH = (242, 160, 160, 110)

S = 512


def draw_icon(maskable=False):
    img = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = 0 if maskable else 24
    # rounded background card
    d.rounded_rectangle([pad, pad, S - pad, S - pad],
                        radius=0 if maskable else 96,
                        fill=CREAM, outline=None if maskable else INK,
                        width=0 if maskable else 14)
    cx, cy = S // 2, S // 2 + 26
    w = 6  # more compact face for maskable safe-zone
    r = 150 if not maskable else 128

    def ellipse(box, **kw):
        d.ellipse(box, **kw)

    # ears
    d.polygon([(cx - r + 20, cy - r + 40), (cx - r - 10, cy - r - 60),
               (cx - 30, cy - r + 6)], fill=PATCH, outline=INK, width=12)
    d.polygon([(cx + r - 20, cy - r + 40), (cx + r + 10, cy - r - 60),
               (cx + 30, cy - r + 6)], fill=FUR, outline=INK, width=12)
    d.polygon([(cx - r + 30, cy - r + 26), (cx - r + 12, cy - r - 30),
               (cx - 52, cy - r + 6)], fill=PINK)
    d.polygon([(cx + r - 30, cy - r + 26), (cx + r - 12, cy - r - 30),
               (cx + 52, cy - r + 6)], fill=PINK)
    # head
    ellipse([cx - r, cy - r, cx + r, cy + r], fill=FUR, outline=INK, width=14)
    # patch over left eye (clip approx: draw and re-outline)
    patch = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    pd = ImageDraw.Draw(patch)
    pd.ellipse([cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6],
               fill=(255, 255, 255, 255))
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ld.ellipse([cx - r - 30, cy - r - 20, cx - 4, cy - 10], fill=PATCH)
    img.paste(Image.composite(layer, Image.new('RGBA', (S, S), (0, 0, 0, 0)),
                              patch.split()[3].point(lambda a: a)),
              (0, 0), Image.composite(layer, Image.new('RGBA', (S, S)),
                                      patch.split()[3]).split()[3])
    # eyes — big and glossy
    er = 44
    for ex in (cx - 62, cx + 62):
        ellipse([ex - er, cy - 30 - er, ex + er, cy - 30 + er], fill=EYE)
        ellipse([ex - er + 12, cy - 30 - er + 10,
                 ex - er + 40, cy - 30 - er + 38], fill=(255, 255, 255, 255))
        ellipse([ex + 8, cy - 8, ex + 22, cy + 4], fill=(255, 255, 255, 170))
    # blush
    ellipse([cx - 128, cy + 26, cx - 68, cy + 56], fill=BLUSH)
    ellipse([cx + 68, cy + 26, cx + 128, cy + 56], fill=BLUSH)
    # nose + mouth
    d.polygon([(cx - 14, cy + 18), (cx + 14, cy + 18), (cx, cy + 38)],
              fill=NOSE, outline=INK, width=6)
    d.arc([cx - 40, cy + 26, cx, cy + 66], 20, 160, fill=INK, width=10)
    d.arc([cx, cy + 26, cx + 40, cy + 66], 20, 160, fill=INK, width=10)
    # whiskers
    for i, dy in enumerate((-6, 12, 30)):
        d.line([(cx - r + 24, cy + 14 + dy), (cx - r - 26, cy + 4 + dy * 1.4)],
               fill=INK, width=7)
        d.line([(cx + r - 24, cy + 14 + dy), (cx + r + 26, cy + 4 + dy * 1.4)],
               fill=INK, width=7)
    return img


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(os.path.dirname(__file__), '..')
    icon = draw_icon()
    mask = draw_icon(maskable=True)

    outs = {
        os.path.join(root, 'assets', 'icon', 'icon.png'): (icon, 512),
        os.path.join(root, 'web', 'icons', 'Icon-512.png'): (icon, 512),
        os.path.join(root, 'web', 'icons', 'Icon-192.png'): (icon, 192),
        os.path.join(root, 'web', 'icons', 'Icon-maskable-512.png'):
            (mask, 512),
        os.path.join(root, 'web', 'icons', 'Icon-maskable-192.png'):
            (mask, 192),
        os.path.join(root, 'web', 'favicon.png'): (icon, 32),
    }
    for path, (im, size) in outs.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        im.resize((size, size), Image.LANCZOS).save(path)
        print('wrote', path)
    # favicon.ico (multi-size)
    ico = os.path.join(root, 'web', 'favicon.ico')
    icon.resize((64, 64), Image.LANCZOS).save(
        ico, sizes=[(16, 16), (32, 32), (48, 48)])
    print('wrote', ico)


if __name__ == '__main__':
    main()
