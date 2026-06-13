# Scan Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove avoidable quadratic work and repeated video decoding from Targie's similarity scan.

**Architecture:** Build candidate pairs through a bounded neighboring-bucket index, load video metadata with capped concurrency while preserving stable output order, and extract Vision feature prints once per video before pair scoring. Keep the existing perceptual hash, BK-tree, scoring, and persistent hash cache behavior.

**Tech Stack:** Swift 6, Swift Concurrency, AVFoundation, Vision, XCTest

---

### Task 1: Indexed prehash candidates

**Files:**
- Create: `Sources/SimilarVideoFinder/Services/PrehashCandidateFinder.swift`
- Create: `Tests/SimilarVideoFinderTests/PrehashCandidateFinderTests.swift`
- Modify: `Sources/SimilarVideoFinder/Services/SimilarityPipeline.swift`

- [x] Test compatible neighboring buckets, normalized-name fallback, and sparse scaling.
- [x] Run the focused test and verify it fails.
- [x] Implement the neighboring-bucket index and wire it into the pipeline.
- [x] Run the focused test and verify it passes.

### Task 2: Concurrent metadata loading

**Files:**
- Modify: `Sources/SimilarVideoFinder/Services/VideoScanner.swift`
- Modify: `Tests/SimilarVideoFinderTests/VideoScannerTests.swift`

- [x] Test capped concurrent loading with stable result ordering.
- [x] Run the focused test and verify it fails.
- [x] Add capped task-group loading.
- [x] Run the focused test and verify it passes.

### Task 3: Reuse Vision features

**Files:**
- Modify: `Sources/SimilarVideoFinder/Services/FrameFeatureExtractor.swift`
- Modify: `Sources/SimilarVideoFinder/Services/SimilarityPipeline.swift`

- [x] Expose per-video extraction and compare cached observations.
- [x] Run focused and full tests.

### Task 4: Verification

- [x] Run `swift test`.
- [x] Build the release app bundle.
- [x] Review the final diff for unrelated changes.
