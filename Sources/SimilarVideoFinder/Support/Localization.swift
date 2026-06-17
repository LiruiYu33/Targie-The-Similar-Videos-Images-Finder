// Targie — Find similar videos on macOS.
// Copyright (C) 2026 Lirui Yu
//
// This file is part of Targie.
//
// Targie is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Targie is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Targie.  If not, see <https://www.gnu.org/licenses/>.
//
// If you reuse this code (modified or not), you must keep this notice
// and credit the original author (Lirui Yu).

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    static let defaultLanguage = AppLanguage.english
    var id: String { rawValue }
    var menuLabel: String { self == .english ? "English" : "简体中文" }
}

private struct AppLanguageKey: EnvironmentKey {
    static let defaultValue = AppLanguage.defaultLanguage
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageKey.self] }
        set { self[AppLanguageKey.self] = newValue }
    }
}

enum L10n {
    static func text(_ language: AppLanguage, _ english: String, _ chinese: String) -> String {
        language == .english ? english : chinese
    }

    static func appName(_ l: AppLanguage) -> String { text(l, "Targie", "Targie") }
    static func chooseFolder(_ l: AppLanguage) -> String { text(l, "Choose Folder", "选择文件夹") }
    static func changeFolder(_ l: AppLanguage) -> String { text(l, "Change Folder", "更换文件夹") }
    static func addFolders(_ l: AppLanguage) -> String { text(l, "Add Folders", "添加文件夹") }
    static func removeFolder(_ l: AppLanguage) -> String { text(l, "Remove Folder", "移除文件夹") }
    static func foldersSelected(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) folders selected", "已添加 \(count) 个文件夹") }
    static func dragFoldersHint(_ l: AppLanguage) -> String { text(l, "Drag one or more folders into this window.", "可将一个或多个文件夹拖入此窗口。") }
    static func startScan(_ l: AppLanguage) -> String { text(l, "Start Scan", "开始扫描") }
    static func cancelScan(_ l: AppLanguage) -> String { text(l, "Cancel Scan", "取消扫描") }
    static func language(_ l: AppLanguage) -> String { text(l, "Language", "语言") }
    static func videos(_ l: AppLanguage) -> String { text(l, "Videos", "视频") }
    static func images(_ l: AppLanguage) -> String { text(l, "Images", "图片") }
    static func allMedia(_ l: AppLanguage) -> String { text(l, "All", "全部") }
    static func selectedCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) files selected", "已选择 \(count) 个文件") }
    static func deleteSelected(_ count: Int, _ l: AppLanguage) -> String { text(l, "Delete Selected (\(count))…", "删除所选 (\(count))…") }
    static func operationFailed(_ l: AppLanguage) -> String { text(l, "Operation Failed", "操作失败") }
    static func ok(_ l: AppLanguage) -> String { text(l, "OK", "好") }
    static func unknownError(_ l: AppLanguage) -> String { text(l, "Unknown error", "未知错误") }
    static func similarVideos(_ l: AppLanguage) -> String { text(l, "Similar Videos", "相似视频") }
    static func similarMedia(_ l: AppLanguage) -> String { text(l, "Similar Media", "相似媒体") }
    static func displayThreshold(_ l: AppLanguage) -> String { text(l, "Display Threshold", "显示阈值") }
    static func displayThresholdHelp(_ l: AppLanguage) -> String { text(l, "≥ 72% recommended; below that false positives increase.", "建议 ≥ 72%；低于此值误报增多。") }
    static func skippedFiles(_ count: Int, _ l: AppLanguage) -> String { text(l, "Skipped \(count) unreadable files", "跳过 \(count) 个无法读取的文件") }
    static func noSimilarVideos(_ l: AppLanguage) -> String { text(l, "No Similar Videos Found", "没有发现相似视频") }
    static func noSimilarMedia(_ l: AppLanguage) -> String { text(l, "No Similar Media Found", "没有发现相似媒体") }
    static func waitingToScan(_ l: AppLanguage) -> String { text(l, "Ready to Scan", "等待扫描") }
    static func lowerThresholdHint(_ l: AppLanguage) -> String { text(l, "Lower the display threshold to review more results.", "可以降低显示阈值后再查看。") }
    static func chooseAndScanHint(_ l: AppLanguage) -> String { text(l, "Add folders and start scanning.", "添加文件夹并开始扫描。") }
    static func similarGroup(_ index: Int, _ l: AppLanguage) -> String { text(l, "Similar Group \(index)", "相似组 \(index)") }
    static func videoCountAndScore(_ count: Int, _ score: String, _ l: AppLanguage) -> String { text(l, "\(count) videos · \(score)", "\(count) 个 · \(score)") }
    static func mediaCountAndScore(_ count: Int, _ score: String, _ l: AppLanguage) -> String { text(l, "\(count) files · \(score)", "\(count) 个文件 · \(score)") }
    static func compareVideos(_ l: AppLanguage) -> String { text(l, "Compare Videos", "组内视频对比") }
    static func compareMedia(_ l: AppLanguage) -> String { text(l, "Compare Media", "组内媒体对比") }
    static func compareHint(_ l: AppLanguage) -> String { text(l, "Select a video and preview it on the right before deleting.", "选择一个视频，在右侧预览后决定是否删除。") }
    static func compareMediaHint(_ l: AppLanguage) -> String { text(l, "Select a file and preview it on the right before deleting.", "选择一个文件，在右侧预览后决定是否删除。") }
    static func highestSimilarity(_ score: String, _ l: AppLanguage) -> String { text(l, "Highest similarity \(score)", "最高相似度 \(score)") }
    static func selectGroup(_ l: AppLanguage) -> String { text(l, "Select a Similar Group", "选择一个相似组") }
    static func resultsOnLeft(_ l: AppLanguage) -> String { text(l, "Scan results appear in the sidebar.", "扫描结果会显示在左侧。") }
    static func videoComparison(_ l: AppLanguage) -> String { text(l, "Video Comparison", "视频对比") }
    static func similarVideoCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) Similar Videos", "\(count) 个相似视频") }
    static func mediaComparison(_ l: AppLanguage) -> String { text(l, "Media Comparison", "媒体对比") }
    static func similarMediaCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) Similar Files", "\(count) 个相似文件") }
    static func fileSize(_ l: AppLanguage) -> String { text(l, "File Size", "文件大小") }
    static func duration(_ l: AppLanguage) -> String { text(l, "Duration", "时长") }
    static func resolution(_ l: AppLanguage) -> String { text(l, "Resolution", "分辨率") }
    static func path(_ l: AppLanguage) -> String { text(l, "Path", "路径") }
    static func openDefaultPlayer(_ l: AppLanguage) -> String { text(l, "Open in Default Player", "默认播放器打开") }
    static func showInFinder(_ l: AppLanguage) -> String { text(l, "Show in Finder", "在 Finder 中显示") }
    static func deleteVideo(_ l: AppLanguage) -> String { text(l, "Delete This Video…", "删除这个视频…") }
    static func deleteMedia(_ l: AppLanguage) -> String { text(l, "Delete This File…", "删除这个文件…") }
    static func selectVideo(_ l: AppLanguage) -> String { text(l, "Select a Video", "选择一个视频") }
    static func selectVideoHint(_ l: AppLanguage) -> String { text(l, "Click a video in the comparison area to preview it.", "在中间的对比列表中单击视频即可预览。") }
    static func selectMedia(_ l: AppLanguage) -> String { text(l, "Select a File", "选择一个文件") }
    static func selectMediaHint(_ l: AppLanguage) -> String { text(l, "Click a file in the comparison area to preview it.", "在中间的对比列表中单击文件即可预览。") }
    static func previewAndDetails(_ l: AppLanguage) -> String { text(l, "Preview & Details", "预览与详情") }
    static func deleteHow(_ l: AppLanguage) -> String { text(l, "How would you like to delete the selected files?", "如何删除所选文件？") }
    static func permanentWarningTitle(_ l: AppLanguage) -> String { text(l, "Permanently Delete Selected Files?", "永久删除所选文件？") }
    static func trashExplanation(_ l: AppLanguage) -> String { text(l, "Moving to Trash is recoverable. Permanent deletion requires another confirmation.", "移到废纸篓后仍可恢复。永久删除会再询问一次。") }
    static func cancel(_ l: AppLanguage) -> String { text(l, "Cancel", "取消") }
    static func permanentDelete(_ l: AppLanguage) -> String { text(l, "Delete Permanently…", "永久删除…") }
    static func moveToTrash(_ l: AppLanguage) -> String { text(l, "Move to Trash", "移到废纸篓") }
    static func irreversible(_ l: AppLanguage) -> String { text(l, "This bypasses Trash and cannot be undone.", "此操作不会经过废纸篓，文件将无法恢复。") }
    static func back(_ l: AppLanguage) -> String { text(l, "Back", "返回") }
    static func confirmPermanent(_ l: AppLanguage) -> String { text(l, "Confirm Permanent Delete", "确认永久删除") }
    static func chooseVideoFolder(_ l: AppLanguage) -> String { text(l, "Choose Folders to Scan", "选择要扫描的文件夹") }
    static func unknown(_ l: AppLanguage) -> String { text(l, "Unknown", "未知") }
    static func noVideoTrack(_ l: AppLanguage) -> String { text(l, "No readable video track was found", "未找到可读取的视频轨道") }
    static func unreadableImage(_ l: AppLanguage) -> String { text(l, "Image could not be read", "图片无法读取") }
    static func fileMissing(_ l: AppLanguage) -> String { text(l, "The file no longer exists", "文件已不存在") }
    static func deletionFailed(_ message: String, _ l: AppLanguage) -> String { text(l, "Deletion failed: \(message)", "删除失败：\(message)") }

    // Browse feature
    static func browse(_ l: AppLanguage) -> String { text(l, "Browse", "浏览") }
    static func filter(_ l: AppLanguage) -> String { text(l, "Filter", "筛选") }
    static func name(_ l: AppLanguage) -> String { text(l, "Name", "名称") }
    static func modifiedTime(_ l: AppLanguage) -> String { text(l, "Modified", "修改时间") }
    static func thumbnail(_ l: AppLanguage) -> String { text(l, "Preview", "缩略图") }
    static func mediaType(_ l: AppLanguage) -> String { text(l, "Media Type", "媒体类型") }
    static func width(_ l: AppLanguage) -> String { text(l, "Width", "宽") }
    static func height(_ l: AppLanguage) -> String { text(l, "Height", "高") }
    static func clearFilter(_ l: AppLanguage) -> String { text(l, "Clear Filter", "清除筛选") }
    static func browseItemCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) items", "\(count) 项") }
    static func noItemsToBrowse(_ l: AppLanguage) -> String { text(l, "No Items to Browse", "无可浏览的文件") }
    static func noItemsBrowseHint(_ l: AppLanguage) -> String { text(l, "Add folders and browse to see files.", "添加文件夹并浏览以查看文件。") }
    static func discoveringFiles(_ l: AppLanguage) -> String { text(l, "Discovering files…", "正在发现文件…") }

    // Resolution sort
    static func resolutionSort(_ l: AppLanguage) -> String { text(l, "Resolution Sort", "分辨率排序") }
    static func sortBy(_ l: AppLanguage) -> String { text(l, "Sort by", "排序依据") }
    static func sortByWidth(_ l: AppLanguage) -> String { text(l, "Width (left)", "宽度（左）") }
    static func sortByHeight(_ l: AppLanguage) -> String { text(l, "Height (right)", "高度（右）") }
    static func sortDirection(_ l: AppLanguage) -> String { text(l, "Direction", "方向") }
    static func ascending(_ l: AppLanguage) -> String { text(l, "Ascending", "升序") }
    static func descending(_ l: AppLanguage) -> String { text(l, "Descending", "降序") }

    static func evidence(_ value: SimilarityEvidence, _ l: AppLanguage) -> String {
        switch value {
        case .identicalContentHash: text(l, "Identical content", "内容完全一致")
        case .similarPerceptualHash: text(l, "Matching fingerprint", "指纹匹配")
        case .similarFrames: text(l, "Similar frames", "画面相似")
        case .similarDuration: text(l, "Similar duration", "时长接近")
        case .similarDimensions: text(l, "Similar resolution", "分辨率接近")
        case .similarSize: text(l, "Similar file size", "文件大小接近")
        case .similarName: text(l, "Similar file name", "文件名接近")
        }
    }

    static func scanStage(_ stage: ScanStage, _ l: AppLanguage) -> String {
        switch stage {
        case .idle: text(l, "Ready to scan", "等待扫描")
        case .discovering: text(l, "Finding media files", "正在查找媒体文件")
        case .readingMetadata: text(l, "Reading media information", "正在读取媒体信息")
        case .prehashing: text(l, "Filtering candidates", "正在筛选候选")
        case .hashing: text(l, "Computing media fingerprints", "正在计算媒体指纹")
        case .comparing: text(l, "Comparing media", "正在比较媒体")
        case .completed: text(l, "Scan complete", "扫描完成")
        case .cancelled: text(l, "Scan cancelled", "扫描已取消")
        }
    }
}
