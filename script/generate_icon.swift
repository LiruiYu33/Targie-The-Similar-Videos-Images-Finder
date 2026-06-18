#!/usr/bin/env swift
// Targie — Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu
//
// This file is part of Targie. Licensed under GPL-3.0-or-later.
// See the LICENSE file at the project root for the full text.
//
// Renders the Targie app icon at 1024×1024 to a PNG file.
// Design: two overlapping video frames (with play triangles) under a
// magnifying glass, communicating "find similar videos".
//
// Usage: swift script/generate_icon.swift <output.png>

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate_icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let size: CGFloat = 1024
let scale: CGFloat = 1
let pixelSize = Int(size * scale)
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let context = CGContext(
    data: nil,
    width: pixelSize,
    height: pixelSize,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("failed to create CGContext\n".utf8))
    exit(1)
}

context.scaleBy(x: scale, y: scale)
context.setShouldAntialias(true)
context.interpolationQuality = .high

// MARK: - Safe-area padding
// Only the *artwork* (video frames + magnifying glass) is scaled into a
// centered ~82% inset so it doesn't crowd the tile edges. The background
// tile itself fills the entire canvas — the system applies the squircle
// mask for the Dock / app switcher, and a full-bleed background avoids a
// transparent margin that would show through as a gray frame in Quick Look
// (which previews the icon image directly, without any mask).
let artworkScale: CGFloat = 0.90

let tileColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
let glassTint = CGColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)

// MARK: - Background tile (flat fill + liquid-glass layers)

let tileRect = CGRect(x: 0, y: 0, width: size, height: size)
// macOS applies its own squircle mask to the .icns at render time. We fill
// the background across the entire square canvas (no rounded-rect path, no
// transparent corners) so no view — including Finder list view and Quick
// Look, which may not apply the mask at small sizes — can show the desktop
// color bleeding through a transparent margin as a gray frame.
let cornerRadius: CGFloat = size * 0.225  // used only for the inner edge rim

// Build a CGGradient from the glass tint at one alpha to the same tint at
// another alpha. Keeps the liquid-glass layers subtle and flat in spirit.
func glassGradient(fromAlpha a0: CGFloat, toAlpha a1: CGFloat) -> CGGradient {
    let c0 = glassTint.copy(alpha: a0)!
    let c1 = glassTint.copy(alpha: a1)!
    return CGGradient(
        colorsSpace: colorSpace,
        colors: [c0, c1] as CFArray,
        locations: [0, 1]
    )!
}

context.saveGState()
// Clip to the full square (the system squircle mask rounds the corners);
// drawing a rounded-rect here would leave transparent corners that show
// through as gray in Finder list view.
context.clip(to: tileRect)

// Base flat fill
context.setFillColor(tileColor)
context.fill(tileRect)

// (a) Top polish highlight — strong→transparent, covering top ~45%.
// CG y is up, so "top" is the high-y end of the tile.
let topHighlight = glassGradient(fromAlpha: 0.32, toAlpha: 0)
context.saveGState()
context.drawLinearGradient(
    topHighlight,
    start: CGPoint(x: 0, y: size * 0.92),
    end: CGPoint(x: 0, y: size * 0.52),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
context.restoreGState()

// (b) Bottom reflection band — transparent→subtle tint over bottom ~25%.
let bottomGlow = glassGradient(fromAlpha: 0, toAlpha: 0.15)
context.saveGState()
context.drawLinearGradient(
    bottomGlow,
    start: CGPoint(x: 0, y: size * 0.30),
    end: CGPoint(x: 0, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
context.restoreGState()

// (c) Inner edge highlight stroke — a thin bright rim just inside the tile.
context.saveGState()
let edgeInset = size * 0.012
let edgePath = CGPath(
    roundedRect: tileRect.insetBy(dx: edgeInset, dy: edgeInset),
    cornerWidth: cornerRadius - edgeInset,
    cornerHeight: cornerRadius - edgeInset,
    transform: nil
)
context.addPath(edgePath)
context.setStrokeColor(glassTint.copy(alpha: 0.35)!)
context.setLineWidth(size * 0.008)
context.strokePath()
context.restoreGState()

context.restoreGState()

// MARK: - Artwork (scaled into the centered safe-area inset)

context.saveGState()
context.translateBy(x: size * (1 - artworkScale) / 2, y: size * (1 - artworkScale) / 2)
context.scaleBy(x: artworkScale, y: artworkScale)

// MARK: - Two overlapping video frames

func drawVideoFrame(center: CGPoint, frameSize: CGSize, rotation: CGFloat, fill: CGColor, stroke: CGColor) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: rotation)

    let rect = CGRect(x: -frameSize.width / 2, y: -frameSize.height / 2, width: frameSize.width, height: frameSize.height)
    let r = frameSize.width * 0.09
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

    // soft drop shadow
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.018, color: CGColor(gray: 0, alpha: 0.45))

    // fill
    context.addPath(path)
    context.setFillColor(fill)
    context.fillPath()

    // stroke (no shadow on stroke)
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.addPath(path)
    context.setStrokeColor(stroke)
    context.setLineWidth(frameSize.width * 0.018)
    context.strokePath()

    // play triangle, centered, pointing right
    let triSize = frameSize.width * 0.28
    let triHeight = triSize * 0.866  // equilateral
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: -triHeight / 3, y: triSize / 2))
    tri.addLine(to: CGPoint(x: -triHeight / 3, y: -triSize / 2))
    tri.addLine(to: CGPoint(x: triHeight * 2 / 3, y: 0))
    tri.closeSubpath()
    context.addPath(tri)
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
    context.fillPath()

    context.restoreGState()
}

let frameW: CGFloat = size * 0.52
let frameH: CGFloat = frameW * 9.0 / 16.0  // 16:9 video frame

// Back frame: cool teal, tilted left, slightly higher
drawVideoFrame(
    center: CGPoint(x: size * 0.42, y: size * 0.56),
    frameSize: CGSize(width: frameW, height: frameH),
    rotation: -0.10,
    fill: CGColor(red: 0.32, green: 0.78, blue: 0.82, alpha: 1.0),
    stroke: CGColor(red: 0.85, green: 0.97, blue: 0.99, alpha: 1.0)
)

// Front frame: warm coral, tilted right, slightly lower — overlapping
drawVideoFrame(
    center: CGPoint(x: size * 0.58, y: size * 0.46),
    frameSize: CGSize(width: frameW, height: frameH),
    rotation: 0.08,
    fill: CGColor(red: 0.96, green: 0.55, blue: 0.42, alpha: 1.0),
    stroke: CGColor(red: 1.0, green: 0.92, blue: 0.88, alpha: 1.0)
)

// MARK: - Magnifying glass on top

let glassCenter = CGPoint(x: size * 0.66, y: size * 0.36)
let glassRadius = size * 0.16
let ringWidth = size * 0.05

// drop shadow under the whole glass
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.025, color: CGColor(gray: 0, alpha: 0.55))

// Lens fill — translucent so the overlap reads through
let lensRect = CGRect(
    x: glassCenter.x - glassRadius,
    y: glassCenter.y - glassRadius,
    width: glassRadius * 2,
    height: glassRadius * 2
)
context.addEllipse(in: lensRect)
context.setFillColor(CGColor(red: 0.92, green: 0.97, blue: 1.0, alpha: 0.32))
context.fillPath()

// Lens highlight (small bright crescent top-left)
let highlightRect = lensRect.insetBy(dx: glassRadius * 0.3, dy: glassRadius * 0.3)
context.saveGState()
context.translateBy(x: -glassRadius * 0.25, y: glassRadius * 0.25)
context.addEllipse(in: highlightRect)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
context.fillPath()
context.restoreGState()

// Ring
context.addEllipse(in: lensRect)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
context.setLineWidth(ringWidth)
context.strokePath()

// Handle — angled bottom-right
let handleStart = CGPoint(
    x: glassCenter.x + cos(-.pi / 4) * (glassRadius + ringWidth * 0.4),
    y: glassCenter.y + sin(-.pi / 4) * (glassRadius + ringWidth * 0.4)
)
let handleLength = size * 0.22
let handleEnd = CGPoint(
    x: handleStart.x + cos(-.pi / 4) * handleLength,
    y: handleStart.y + sin(-.pi / 4) * handleLength
)
context.move(to: handleStart)
context.addLine(to: handleEnd)
context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
context.setLineWidth(ringWidth * 1.1)
context.setLineCap(.round)
context.strokePath()

context.restoreGState()  // pop the glass shadow
context.restoreGState()  // pop the artwork safe-area scale

// MARK: - Write PNG

guard let cgImage = context.makeImage() else {
    FileHandle.standardError.write(Data("failed to render image\n".utf8))
    exit(1)
}

let pngType = UTType.png.identifier as CFString
guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, pngType, 1, nil) else {
    FileHandle.standardError.write(Data("failed to create PNG destination\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("failed to write PNG\n".utf8))
    exit(1)
}

print("wrote \(outputURL.path)")
