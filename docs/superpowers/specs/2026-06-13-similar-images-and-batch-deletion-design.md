# Targie Similar Images and Batch Deletion Design

## Goal

Extend Targie from a similar-video finder into a similar-media finder. Users can scan a selected folder in one of three modes: videos, images, or both. Image matching must detect exact duplicates plus images changed by recompression, resizing, format conversion, light color adjustment, or a modest watermark.

The feature also adds explicit multi-selection and batch deletion for both videos and images. Targie never selects or deletes files automatically.

## Product Decisions

- The toolbar uses a segmented control with `Videos`, `Images`, and `All`.
- The default mode is `All`; the last selected mode persists across launches.
- In `All`, video groups and image groups are shown in separate sidebar sections. Images and videos never belong to the same similarity group.
- Supported image formats are JPEG, PNG, HEIC, WebP, TIFF, GIF, and BMP. Animated GIF files are compared using their static representative frame only.
- Both videos and images support multi-selection and batch deletion.
- Batch deletion offers `Move to Trash` and `Delete Permanently`. Permanent deletion requires a second explicit warning.
- The existing English and Simplified Chinese interface remains fully localized.

## Architecture

### Unified Media Model

Replace the video-only domain model with a shared `MediaItem` model containing:

- stable scan identifier
- file URL, name, size, modification date, and thumbnail data
- pixel width and height
- media kind: image or video
- optional video duration

The shared group and relation types operate on `MediaItem`. Media-specific values stay optional only where they are genuinely inapplicable; image scoring must not interpret a missing video duration as zero-duration evidence.

Existing video behavior is migrated to the unified types rather than maintained through a second parallel model. UI selection, grouping, deletion, formatting, and cache identity use media-neutral names.

### Scanning

Introduce `ScanMode` with `videos`, `images`, and `all`.

- `VideoScanner` continues to use AVFoundation for video metadata and thumbnails.
- `ImageScanner` recursively discovers supported image extensions and loads dimensions and a bounded thumbnail through ImageIO or Core Graphics.
- A coordinating scanner runs only the scanner required by the selected mode. In `all`, video and image discovery may run concurrently, but each loader keeps its own bounded concurrency.
- The scanner returns loaded items and per-file issues without failing the entire scan because one file is corrupt, unsupported, missing, or unreadable.
- Scan progress identifies the active media kind and combines both scanner totals into one stable overall fraction in `all` mode.

### Similarity Pipelines

Video and image items use separate matching pipelines behind a common processing interface. The coordinator processes each media kind independently and merges the resulting groups for presentation.

Video matching retains the existing quick prehash, perceptual hash, BK-tree candidate search, and persistent cache behavior.

Image matching uses:

1. Metadata and thumbnail-derived quick buckets to avoid unrestricted pairwise comparison.
2. A perceptual image hash for recompression, resizing, and format conversion tolerance.
3. Vision FeaturePrint verification for plausible candidates to improve tolerance for light color changes and modest watermarks.
4. SHA-256 only for likely exact duplicates, such as equal-size files with matching perceptual hashes.
5. A score calibrated independently from video scoring.

Image FeaturePrint extraction is performed once per image per scan and cached in memory while candidates are compared. Persistent cache records store reusable image perceptual features keyed by canonical path, file size, modification time, media kind, and feature algorithm version. A changed file or algorithm version invalidates the record.

Image decoding and Vision work use a small bounded task group, targeted at two to four concurrent items. Autorelease scopes are used around image decoding where appropriate so large image buffers are released promptly.

Changing the visible similarity threshold only rebuilds groups from existing relations. It does not rescan files or recompute image features.

## User Interface

### Toolbar and Sidebar

The toolbar places the `Videos / Images / All` segmented control near folder and scan controls. Changing mode clears results from the prior scan and makes the required new scan explicit, avoiding stale results presented under a different mode.

The sidebar shows:

- a video section when video results exist
- an image section when image results exist
- group count, item count, maximum similarity, and reclaimable size

In a single-media mode, only that media section appears.

### Group Comparison and Preview

Each media card includes a checkbox independent of the current inspector selection. Selecting a card for inspection does not silently select it for deletion.

The comparison toolbar displays the number of checked items and enables batch deletion when at least one existing file is checked.

- Images use a large static image preview.
- Videos use the existing static thumbnail preview and an `Open in Default Player` action.
- Both media kinds provide `Show in Finder`.
- Video playback is not embedded again because the previous AVPlayer bridge was a crash source.

## Deletion Semantics

The selection set stores media identifiers and is reconciled whenever results change.

For a batch deletion:

1. Targie displays the selected count and the affected file paths.
2. The user chooses `Move to Trash`, `Delete Permanently`, or cancel.
3. Permanent deletion opens a second irreversible-action warning.
4. Files are deleted individually with bounded, conservative concurrency.
5. Successfully deleted items are removed from groups, relations, inspector selection, and the checked set.
6. Failed items remain visible and checked, with a per-file error summary.
7. Groups with fewer than two remaining items disappear.

This partial-success behavior prevents the interface from claiming that a failed deletion succeeded and allows the user to retry only failed files.

Single-file deletion remains available and follows the same confirmation rules.

## Localization and Persistence

Add English and Simplified Chinese strings for:

- scan modes and media section headings
- image metadata and image-specific scan stages
- selection counts and batch actions
- permanent batch deletion warnings
- partial deletion results and per-file failures

Persist `ScanMode` in `UserDefaults` using a stable raw value. Invalid or obsolete persisted values fall back to `all`. Language persistence continues unchanged.

## Error Handling

- A corrupt or unreadable image produces a `ScanIssue` and does not stop scanning.
- A failed perceptual hash or FeaturePrint excludes only that item or candidate relation.
- Missing files are ignored during comparison and reported before deletion.
- Cache read or write failure falls back to uncached processing.
- Cancellation stops scheduling new decoding work and discards incomplete scan results consistently with the existing video flow.
- Loading and comparison concurrency remain bounded to prevent memory spikes on large folders.

## Testing

Tests must cover:

- recursive discovery and stable ordering for every supported image extension
- exclusion of unsupported files and hidden package contents
- dimensions, thumbnails, and static GIF representative-frame loading
- corrupt and unreadable image issue reporting without scan termination
- perceptual similarity across resizing, recompression, and format conversion fixtures
- FeaturePrint verification for light color changes and modest watermarks
- persistent image cache hits, invalidation after modification, and algorithm-version invalidation
- separate video and image grouping in `all` mode
- threshold changes rebuilding groups without feature extraction
- scan-mode persistence and invalid-value fallback
- checkbox selection remaining independent from inspector selection
- batch trash and permanent-delete confirmation flows
- partial batch deletion success with failed items retained
- existing video scan, grouping, cache, preview, and deletion regression tests

## Acceptance Criteria

- Users can choose `Videos`, `Images`, or `All` before scanning.
- The selected mode is restored on the next launch.
- Common image formats are discovered recursively and shown in image-only groups.
- Recompressed, resized, format-converted, lightly color-adjusted, and modestly watermarked versions of an image can be grouped at an appropriate threshold.
- Images and videos never form a mixed similarity group.
- A second unchanged scan reuses persistent image hashes and is observably faster than the first.
- One corrupt image cannot abort the remaining scan.
- Users can explicitly check multiple videos and/or images and choose trash or permanent deletion.
- Permanent deletion always requires a second confirmation.
- Partial deletion failures are accurately represented, with failed files retained.
- Large folders do not create unbounded image decoding or Vision tasks.
- Existing video behavior remains functional and all user-facing additions are available in English and Simplified Chinese.

## Non-Goals

- RAW camera formats.
- Semantic subject matching between different photographs.
- Robust detection of heavy crops, arbitrary rotations, or small screenshot regions.
- Animated GIF sequence comparison.
- Cross-type image-to-video-frame matching.
- Automatic quality ranking or automatic duplicate selection.
- Background folder monitoring or a permanent media library index.
