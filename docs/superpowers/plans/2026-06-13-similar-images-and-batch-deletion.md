# Similar Images and Batch Deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add image similarity scanning and explicit batch deletion for images and videos while preserving the existing fast, stable video workflow.

**Architecture:** Migrate video-only domain types to media-neutral types, but keep video and image scanning/scoring implementations separate. A coordinator runs the selected `videos`, `images`, or `all` mode and merges same-kind groups only. Use test-first changes and commit after each task.

**Tech Stack:** Swift 6, SwiftUI, AppKit, AVFoundation, ImageIO/CoreGraphics, Vision, GRDB, XCTest, SwiftPM.

---

## Handoff Rules

- Read the approved design first: `docs/superpowers/specs/2026-06-13-similar-images-and-batch-deletion-design.md`.
- Work on the current `dev` branch unless the user requests another branch.
- Preserve all existing user changes. Do not reset or rewrite history.
- Use `apply_patch` for manual edits.
- Follow red-green-refactor: add a failing focused test, run it, implement the minimum behavior, rerun focused tests, then run the full suite at milestones.
- Keep all commits signed off with `git commit --signoff`.
- Do not reintroduce embedded `AVPlayer` or SwiftUI `VideoPlayer`; crash reports previously implicated that bridge.
- Never run Vision once per candidate pair. Extract each image feature at most once per scan and reuse it.
- Bound image decode/Vision concurrency to at most four tasks.
- A corrupt or unreadable file must create a `ScanIssue`, not abort the scan.
- Images and videos must never appear in the same `SimilarityGroup`.

## Planned File Structure

- Rename `Models/VideoModels.swift` to `Models/MediaModels.swift`: shared media, relation, group, scan-mode, progress, and issue types.
- Keep `Services/VideoScanner.swift`: video-only loading.
- Create `Services/ImageScanner.swift`: image discovery, dimensions, bounded thumbnail decoding, and issue isolation.
- Rename/generalize `Services/PerceptualHasher.swift` only where shared primitives are useful; keep video frame hashing separate from the new image hash API.
- Create `Services/ImagePerceptualHasher.swift`: image pHash from a decoded `CGImage`.
- Create `Services/ImageFeatureExtractor.swift`: Vision FeaturePrint extraction and per-scan cache.
- Create `Services/ImageSimilarityPipeline.swift`: image candidates, hashes, feature verification, scoring, and grouping.
- Create `Services/MediaScanCoordinator.swift`: mode-specific scanning and processing, progress merging, and same-kind result merging.
- Generalize `Services/HashCache.swift`: media kind plus algorithm version in persistent cache validity.
- Generalize `Stores/ScanViewModel.swift`: media-neutral selection, scan mode, checked IDs, and batch deletion.
- Rename `Views/VideoCardView.swift` to `Views/MediaCardView.swift`; update sidebar, detail, inspector, confirmation, and content views.

### Task 1: Introduce Media-Neutral Domain Types

**Files:**
- Rename: `Sources/SimilarVideoFinder/Models/VideoModels.swift` -> `Sources/SimilarVideoFinder/Models/MediaModels.swift`
- Modify: all source and test references to `VideoItem`, `SimilarityGroup.videos`, `selectedVideoID`, and `selectedVideo`
- Test: `Tests/SimilarVideoFinderTests/MediaModelTests.swift`

- [ ] Write failing tests for `MediaKind`, `ScanMode`, image items with `duration == nil`, video items with duration, and groups rejecting mixed media kinds.
- [ ] Run `swift test --filter MediaModelTests`; verify compile/test failure because the new API does not exist.
- [ ] Add:

```swift
enum MediaKind: String, Codable, Sendable { case video, image }
enum ScanMode: String, CaseIterable, Identifiable, Sendable {
    case videos, images, all
    var id: String { rawValue }
}

struct MediaItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: MediaKind
    let url: URL
    let fileSize: Int64
    let duration: Double?
    let width: Int
    let height: Int
    let modifiedAt: Date?
    let thumbnailData: Data?
}
```

- [ ] Rename group properties to `items` and selection properties to `selectedMediaID`/`selectedMedia`; update tests without changing video behavior.
- [ ] Run `swift test`; expect all existing tests plus `MediaModelTests` to pass.
- [ ] Commit with `git commit --signoff -m "refactor: generalize video models to media"`.

### Task 2: Add Image Discovery and Metadata Loading

**Files:**
- Create: `Sources/SimilarVideoFinder/Services/ImageScanner.swift`
- Create: `Tests/SimilarVideoFinderTests/ImageScannerTests.swift`
- Modify: `Sources/SimilarVideoFinder/Models/MediaModels.swift`

- [ ] Write failing discovery tests for `jpg`, `jpeg`, `png`, `heic`, `webp`, `tif`, `tiff`, `gif`, and `bmp`, recursive stable ordering, hidden files, and package descendants.
- [ ] Write a failing loader test that creates a small PNG fixture and expects dimensions, `.image`, `duration == nil`, and thumbnail data.
- [ ] Write a failing test where one injected loader throws and the remaining images still return with one `ScanIssue`.
- [ ] Run `swift test --filter ImageScannerTests`; verify expected failures.
- [ ] Implement `ImageScanner` using `CGImageSourceCreateWithURL`, `CGImageSourceCopyPropertiesAtIndex`, and `CGImageSourceCreateThumbnailAtIndex`. Set thumbnail max pixel size to 720 and apply orientation transforms.
- [ ] Limit loader concurrency with the same bounded task-group pattern as `VideoScanner`, defaulting to `min(4, max(2, activeProcessorCount / 2))`.
- [ ] Load GIF index zero only. Return issues per file and never throw an individual decode error out of the scan.
- [ ] Run `swift test --filter ImageScannerTests`, then `swift test --filter 'ImageScannerTests|VideoScannerTests'`.
- [ ] Commit with `git commit --signoff -m "feat: scan supported image formats"`.

### Task 3: Add Image Perceptual Hashing

**Files:**
- Create: `Sources/SimilarVideoFinder/Services/ImagePerceptualHasher.swift`
- Create: `Tests/SimilarVideoFinderTests/ImagePerceptualHasherTests.swift`
- Modify: `Sources/SimilarVideoFinder/Services/PerceptualHasher.swift` only to expose genuinely shared DCT/grayscale helpers

- [ ] Write failing tests proving identical pixels hash identically and resized/re-encoded fixtures stay above the chosen pHash similarity threshold.
- [ ] Write a failing test proving clearly different fixtures fall outside the candidate distance.
- [ ] Run `swift test --filter ImagePerceptualHasherTests`; verify failure because the image hasher is absent.
- [ ] Implement a 64-bit image pHash: orientation-correct decode, 32x32 grayscale downsample, 2D DCT, top-left 8x8 low-frequency coefficients excluding DC, median threshold, byte packing, and Hamming similarity.
- [ ] Keep video DCT-3D behavior unchanged and do not route images through AVFoundation.
- [ ] Run the focused tests and `swift test --filter PerceptualHasherTests`.
- [ ] Commit with `git commit --signoff -m "feat: add image perceptual hashing"`.

### Task 4: Generalize Persistent Hash Cache

**Files:**
- Modify: `Sources/SimilarVideoFinder/Services/HashCache.swift`
- Modify: `Tests/SimilarVideoFinderTests/HashCacheTests.swift`

- [ ] Add failing tests for distinct image/video cache identities, algorithm-version invalidation, file-size invalidation, and modification-date invalidation.
- [ ] Run `swift test --filter HashCacheTests`; verify new tests fail.
- [ ] Add `mediaKind` and `algorithmVersion` columns through a new GRDB migration. Do not edit the existing v1 migration.
- [ ] Change lookup to require path, size, modification date, kind, and algorithm version. Use stable versions such as `video-dct3d-v1` and `image-phash-v1`.
- [ ] Update `CacheRecord.make`/conversion helpers to accept `MediaItem` and a generic perceptual hash value.
- [ ] Run `swift test --filter HashCacheTests` and video pipeline cache tests.
- [ ] Commit with `git commit --signoff -m "feat: cache media hashes by algorithm"`.

### Task 5: Add Vision Image Feature Extraction With Per-Scan Reuse

**Files:**
- Create: `Sources/SimilarVideoFinder/Services/ImageFeatureExtractor.swift`
- Create: `Tests/SimilarVideoFinderTests/ImageFeatureExtractorTests.swift`

- [ ] Write failing tests using an injected extractor to prove each image is extracted once even when used in several comparisons.
- [ ] Add a failing error-isolation test proving one extraction failure returns no score for that pair without throwing from the whole comparison.
- [ ] Run `swift test --filter ImageFeatureExtractorTests`; verify expected failure.
- [ ] Implement `VNGenerateImageFeaturePrintRequest` over an orientation-correct `CGImage` and compare observations with `computeDistance`.
- [ ] Add an actor-backed per-scan cache keyed by media ID. Cache both success and failure so an unreadable image is not retried for every pair.
- [ ] Wrap image decode/request work in `autoreleasepool` where synchronous APIs permit it.
- [ ] Run focused tests.
- [ ] Commit with `git commit --signoff -m "feat: extract reusable image features"`.

### Task 6: Implement the Image Similarity Pipeline

**Files:**
- Create: `Sources/SimilarVideoFinder/Services/ImageSimilarityPipeline.swift`
- Create: `Sources/SimilarVideoFinder/Services/ImageSimilarityScoring.swift`
- Create: `Tests/SimilarVideoFinderTests/ImageSimilarityPipelineTests.swift`
- Create: `Tests/SimilarVideoFinderTests/ImageSimilarityScoringTests.swift`

- [ ] Write failing tests for exact duplicates, resized/recompressed images, format-converted images, light color adjustment, modest watermark, and unrelated images.
- [ ] Add a failing test that counts feature extraction and ensures it is once per image, not once per pair.
- [ ] Add a failing test that threshold changes regroup existing relations without recomputing features.
- [ ] Run the focused tests and confirm expected failures.
- [ ] Implement cheap candidate buckets from aspect ratio, dimensions, file size, and thumbnail statistics. Include neighboring buckets so small transformations do not disappear at boundaries.
- [ ] Compute/cache pHash with at most four concurrent tasks, build a BK-tree, and process each pair once.
- [ ] Use SHA-256 only when equal-size files have identical pHash. Use FeaturePrint only for plausible pHash candidates and reuse the per-scan cache.
- [ ] Calibrate a separate image score and evidence set. Store all relations down to the minimum UI threshold (`0.72`) so slider changes require regrouping only.
- [ ] Run focused tests and then `swift test --filter 'ImageSimilarityPipelineTests|SimilarityPipelineResilienceTests'`.
- [ ] Commit with `git commit --signoff -m "feat: group similar images"`.

### Task 7: Coordinate Video, Image, and All Scan Modes

**Files:**
- Create: `Sources/SimilarVideoFinder/Services/MediaScanCoordinator.swift`
- Create: `Tests/SimilarVideoFinderTests/MediaScanCoordinatorTests.swift`
- Modify: `Sources/SimilarVideoFinder/Stores/ScanViewModel.swift`

- [ ] Write failing tests proving `.videos` invokes only video services, `.images` only image services, and `.all` invokes both.
- [ ] Add a failing test proving merged results contain separate image and video groups and no mixed group.
- [ ] Add failing progress and cancellation tests for `.all`.
- [ ] Run `swift test --filter MediaScanCoordinatorTests`; verify failure.
- [ ] Define scanner/processor protocols so tests inject fakes. Return a neutral `MediaProcessingResult(items:relations:groups:issues:)`.
- [ ] Implement mode coordination. Concurrent video/image work is allowed, but each underlying service retains its own concurrency cap.
- [ ] Update `ScanViewModel.startScan()` to call the coordinator, expose issues immediately, and prune cache with all valid media paths.
- [ ] Run focused tests plus the complete suite.
- [ ] Commit with `git commit --signoff -m "feat: add selectable media scan modes"`.

### Task 8: Persist Scan Mode and Localize Media UI

**Files:**
- Modify: `Sources/SimilarVideoFinder/Views/ContentView.swift`
- Modify: `Sources/SimilarVideoFinder/Support/Localization.swift`
- Modify: `Tests/SimilarVideoFinderTests/LocalizationTests.swift`
- Create: `Tests/SimilarVideoFinderTests/ScanModePersistenceTests.swift`

- [ ] Write failing tests for English/Chinese scan-mode labels and invalid stored raw values falling back to `.all`.
- [ ] Run focused tests and verify failure.
- [ ] Add `@AppStorage("scanMode")`, default `.all`, and bind the toolbar segmented picker to a validated `ScanMode` value.
- [ ] When mode changes, cancel any active scan and clear results/selections so stale groups are not relabeled.
- [ ] Add media-neutral strings for sections, counts, scan stages, image metadata, and empty states.
- [ ] Run `swift test --filter 'LocalizationTests|ScanModePersistenceTests'`.
- [ ] Commit with `git commit --signoff -m "feat: localize and persist scan mode"`.

### Task 9: Add Explicit Multi-Selection and Partial-Success Batch Deletion

**Files:**
- Modify: `Sources/SimilarVideoFinder/Stores/ScanViewModel.swift`
- Modify: `Sources/SimilarVideoFinder/Services/DeletionService.swift`
- Modify: `Sources/SimilarVideoFinder/Views/DeleteConfirmationView.swift`
- Modify: `Tests/SimilarVideoFinderTests/ScanViewModelTests.swift`
- Modify: `Tests/SimilarVideoFinderTests/DeletionServiceTests.swift`

- [ ] Add failing tests proving inspector selection does not check an item, checked IDs are reconciled after regrouping, and successful batch deletion removes items/relations/groups.
- [ ] Add a failing partial-success test: successful files disappear, failed files remain checked and visible, and errors identify each failed path.
- [ ] Run `swift test --filter 'ScanViewModelTests|DeletionServiceTests'`; verify failure.
- [ ] Replace single-item prompt payload with `[MediaItem]` while preserving single-delete entry points. Add `checkedMediaIDs: Set<UUID>` and toggle/select-all helpers.
- [ ] Delete files individually with conservative bounded concurrency. Return a `BatchDeletionResult` containing successful IDs and `(URL, error)` failures.
- [ ] Keep the method-choice screen and second permanent-delete confirmation for both single and batch operations.
- [ ] Run focused tests.
- [ ] Commit with `git commit --signoff -m "feat: add safe batch media deletion"`.

### Task 10: Generalize the Three-Column Interface

**Files:**
- Rename: `Sources/SimilarVideoFinder/Views/VideoCardView.swift` -> `Sources/SimilarVideoFinder/Views/MediaCardView.swift`
- Modify: `Sources/SimilarVideoFinder/Views/SidebarView.swift`
- Modify: `Sources/SimilarVideoFinder/Views/GroupDetailView.swift`
- Modify: `Sources/SimilarVideoFinder/Views/InspectorView.swift`
- Modify: `Sources/SimilarVideoFinder/Views/ContentView.swift`
- Modify: `Sources/SimilarVideoFinder/Support/Formatters.swift`
- Test: `Tests/SimilarVideoFinderTests/AppSmokeTests.swift`

- [ ] Add compile/smoke assertions for media views and add view-model tests for sidebar section ordering (`video`, then `image`) in `.all` mode.
- [ ] Run focused tests and verify failure/compile gaps.
- [ ] Show separate sidebar sections by group kind. In single-mode scans, show only the active kind.
- [ ] Add a checkbox to each card bound to `checkedMediaIDs`; keep card tap dedicated to inspector selection.
- [ ] Show selection count and batch-delete action above the grid.
- [ ] Render image cards/previews with their natural aspect ratio. Render video thumbnails statically and retain `Open in Default Player`. Both kinds retain Finder reveal.
- [ ] Ensure image metadata omits duration instead of displaying zero or unknown video time.
- [ ] Run `swift test --filter 'AppSmokeTests|ScanViewModelTests|LocalizationTests'` and `swift build`.
- [ ] Commit with `git commit --signoff -m "feat: present similar images and media selection"`.

### Task 11: Integration Fixtures, Documentation, and Final Verification

**Files:**
- Modify: `Tests/SimilarVideoFinderTests/MediaIntegrationTests.swift`
- Modify: `README.md`
- Modify: `README_ZH.md`
- Modify if needed: `script/build_app.sh`

- [ ] Add deterministic generated image fixtures for duplicate, resized, recompressed, color-adjusted, watermarked, and unrelated cases. Do not commit large binary fixtures when tests can generate them.
- [ ] Add an integration test scanning a folder containing videos, images, one corrupt image, and unsupported files; assert separate groups and one issue without termination.
- [ ] Run `swift test --filter MediaIntegrationTests`; fix only behavior required by the approved design.
- [ ] Update both READMEs with the three modes, supported formats, cache behavior, batch deletion safeguards, and build instructions.
- [ ] Run the full verification:

```bash
HOME="$PWD/.build/home" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
swift test
./script/build_app.sh
plutil -lint dist/Targie.app/Contents/Info.plist
xattr -cr dist/Targie.app
codesign --verify --deep --strict --verbose=2 dist/Targie.app
```

- [ ] Launch `dist/Targie.app`, manually check all three modes, inspect one image and one video, test checkbox independence, and verify both confirmation stages without permanently deleting valuable files.
- [ ] Check `~/Library/Logs/DiagnosticReports` for a new `SimilarVideoFinder-*.ips` report after the smoke run.
- [ ] Commit with `git commit --signoff -m "docs: document similar image workflow"`.

## Final Review Checklist

- [ ] `git diff --check` passes and the worktree contains no unrelated files.
- [ ] Full XCTest suite passes.
- [ ] Release app builds and strict code-sign verification passes after clearing Finder xattrs.
- [ ] Second unchanged image scan demonstrates cache reuse.
- [ ] Corrupt images are listed as skipped and do not stop results from appearing.
- [ ] Video and image groups remain separate in `all` mode.
- [ ] Feature extraction is per image, not per candidate pair.
- [ ] Batch deletion preserves failed files and requires the permanent-delete second confirmation.
- [ ] English and Simplified Chinese cover every new user-facing string.
