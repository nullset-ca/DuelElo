# Branding

- `logo.svg` — the logo (hand-drawn vector). Exports: `logo-400/512/1024.png`.
- `banner.svg` → `banner-1280x640.png` — GitHub social preview / store banner.
- In-game icon: `DuelElo/Media/icon.tga` (64x64, uncompressed 32-bit, bottom-left origin).

Regenerate (needs `brew install librsvg`):

```
rsvg-convert -w 512 -h 512 branding/logo.svg -o branding/logo-512.png
rsvg-convert -w 1280 -h 640 branding/banner.svg -o branding/banner-1280x640.png
rsvg-convert -w 64 -h 64 branding/logo.svg -o branding/icon-64.png
python3 branding/png_to_tga.py branding/icon-64.png DuelElo/Media/icon.tga
```
