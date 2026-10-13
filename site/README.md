# Targie website

Static site published with GitHub Pages. There is no framework or build
dependency; `script/build_site.py` uses only the Python standard library.

## Layout

| Path | Purpose |
|---|---|
| `site/static/` | Copied as-is: `style.css`, favicon, `img/` (screenshots as WebP, social card) |
| `releases/vX.Y.Z.md` | Release notes in seven languages; the changelog pages are generated from these |
| `script/build_site.py` | Page copy for all languages, templates, sitemap, link check |
| `.github/workflows/pages.yml` | Builds on every change to the inputs above and deploys from `main` |

## Preview locally

```bash
python3 script/build_site.py --out _site --base-url http://localhost:8000/
python3 -m http.server 8000 --directory _site
```

## Publishing a new version

Add `releases/vX.Y.Z.md` (same `## English`, `## 简体中文`, ... headings as the
existing files) and merge it. The home page's download button and version
badge follow the newest file, and the release date comes from the `vX.Y.Z` git
tag. The button links to
`releases/download/vX.Y.Z/Targie-vX.Y.Z-macos-universal.zip`, so publish the
GitHub release with that asset name.

## Editing copy

Page text lives in the `STR` table at the top of `script/build_site.py`, one
block per language with identical keys. Changing screenshots means replacing the
files in `site/static/img/` (keep ~1600 px wide WebP, and update the `height`
values in `home()` if the aspect ratio changes).
