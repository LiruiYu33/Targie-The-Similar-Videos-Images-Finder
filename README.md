# Targie

[简体中文](README_ZH.md)

> **macOS only.** Targie is a native macOS 14+ application. There is no Windows or Linux build, and none is planned.

Targie finds similar videos and images across selected folders by combining metadata, content hashes, perceptual fingerprints, and visual features.

## Features

- Switches between Videos, Images, and All scan modes and remembers the selected mode.
- Adds multiple folders through the picker or Finder drag and drop, then compares media across all selected folders.
- Recursively scans common video formats plus JPEG, PNG, HEIC, WebP, TIFF, GIF, and BMP images.
- Uses SHA-256, cached perceptual fingerprints, metadata, and reusable Vision features while isolating unreadable files.
- Keeps video and image groups separate for side-by-side review with static in-app previews.
- Opens videos in the default player and reveals either media type in Finder.
- Supports explicit multi-selection and partial-success batch deletion.
- Requires an explicit choice between moving files to Trash and permanent deletion, with a second confirmation for permanent deletion.
- Supports English and Simplified Chinese with instant switching and remembered preference.

![Screenshot](asset/Screenshot.png)

## Build (macOS only)

```bash
swift test
./script/build_app.sh
```

The generated application is located at:

```text
dist/Targie.app
```

For development, build and launch with:

```bash
./script/build_and_run.sh
```

The app is ad-hoc signed for local use. Distribution through the internet or the App Store requires a Developer ID, notarization, and the appropriate packaging workflow.

## License

Targie is licensed under the **[GNU General Public License v3.0](LICENSE)**.

Copyright (C) 2026 Lirui Yu.

If you reuse this code (modified or not):

- You **must** keep the copyright notice and credit the original author (Lirui Yu).
- Any derivative work you distribute **must** also be released under GPL-3.0 (or a later GPL version), with full source code available to its users.
- Closed-source / proprietary redistribution is **not** permitted.

See the [LICENSE](LICENSE) file for the full legal text.

## Contributing

Pull requests are welcome. Every commit must be signed off under the [Developer Certificate of Origin (DCO)](DCO) — pass `-s` to `git commit`. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.
