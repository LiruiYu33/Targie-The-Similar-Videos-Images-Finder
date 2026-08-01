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
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case french = "fr"
    case japanese = "ja"
    case korean = "ko"

    static let defaultLanguage = AppLanguage.english
    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .spanish: "Español"
        case .french: "Français"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
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
    static func text(
        _ language: AppLanguage,
        _ english: String,
        _ simplifiedChinese: String,
        _ traditionalChinese: String,
        _ spanish: String,
        _ french: String,
        _ japanese: String,
        _ korean: String
    ) -> String {
        switch language {
        case .english: english
        case .simplifiedChinese: simplifiedChinese
        case .traditionalChinese: traditionalChinese
        case .spanish: spanish
        case .french: french
        case .japanese: japanese
        case .korean: korean
        }
    }

    static func appName(_ l: AppLanguage) -> String { text(l, "Targie", "Targie", "Targie", "Targie", "Targie", "Targie", "Targie") }
    static func chooseFolder(_ l: AppLanguage) -> String { text(l, "Choose Folder", "选择文件夹", "選擇資料夾", "Elegir carpeta", "Choisir un dossier", "フォルダを選択", "폴더 선택") }
    static func changeFolder(_ l: AppLanguage) -> String { text(l, "Change Folder", "更换文件夹", "更換資料夾", "Cambiar carpeta", "Changer de dossier", "フォルダを変更", "폴더 변경") }
    static func addFolders(_ l: AppLanguage) -> String { text(l, "Add Folders", "添加文件夹", "新增資料夾", "Añadir carpetas", "Ajouter des dossiers", "フォルダを追加", "폴더 추가") }
    static func clearFolders(_ l: AppLanguage) -> String { text(l, "Clear Folder Selection", "清除文件夹选择", "清除資料夾選擇", "Borrar selección de carpetas", "Effacer la sélection de dossiers", "フォルダ選択をクリア", "폴더 선택 지우기") }
    static func excludeSubfolders(_ l: AppLanguage) -> String { text(l, "Exclude Subfolders", "不包含子文件夹", "不包含子資料夾", "Excluir subcarpetas", "Exclure les sous-dossiers", "サブフォルダを含めない", "하위 폴더 제외") }
    static func removeFolder(_ l: AppLanguage) -> String { text(l, "Remove Folder", "移除文件夹", "移除資料夾", "Quitar carpeta", "Supprimer le dossier", "フォルダを削除", "폴더 제거") }
    static func foldersSelected(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) folders selected", "已添加 \(count) 个文件夹", "已新增 \(count) 個資料夾", "\(count) carpetas seleccionadas", "\(count) dossiers sélectionnés", "\(count)個のフォルダを選択", "\(count)개 폴더 선택됨") }
    static func dragFoldersHint(_ l: AppLanguage) -> String { text(l, "Drag one or more folders into this window.", "可将一个或多个文件夹拖入此窗口。", "可將一個或多個資料夾拖入此視窗。", "Arrastra una o más carpetas a esta ventana.", "Faites glisser un ou plusieurs dossiers dans cette fenêtre.", "1つ以上のフォルダをこのウィンドウにドラッグしてください。", "하나 이상의 폴더를 이 창으로 끌어오세요.") }
    static func startScan(_ l: AppLanguage) -> String { text(l, "Start Scan", "开始扫描", "開始掃描", "Iniciar análisis", "Lancer l’analyse", "スキャン開始", "스캔 시작") }
    static func cancelScan(_ l: AppLanguage) -> String { text(l, "Cancel Scan", "取消扫描", "取消掃描", "Cancelar análisis", "Annuler l’analyse", "スキャンをキャンセル", "스캔 취소") }
    static func language(_ l: AppLanguage) -> String { text(l, "Language", "语言", "語言", "Idioma", "Langue", "言語", "언어") }
    static func scanIntensity(_ l: AppLanguage) -> String { text(l, "Intensity", "强度", "強度", "Intensidad", "Intensité", "強度", "강도") }
    static func scanIntensityName(_ intensity: ScanIntensity, _ l: AppLanguage) -> String {
        switch intensity {
        case .cool:
            text(l, "Cool", "低温", "低溫", "Fresco", "Tempéré", "低温", "저온")
        case .balanced:
            text(l, "Balanced", "平衡", "平衡", "Equilibrado", "Équilibré", "バランス", "균형")
        case .fast:
            text(l, "Fast", "快速", "快速", "Rápido", "Rapide", "高速", "빠름")
        }
    }
    static func videos(_ l: AppLanguage) -> String { text(l, "Videos", "视频", "影片", "Vídeos", "Vidéos", "動画", "동영상") }
    static func images(_ l: AppLanguage) -> String { text(l, "Images", "图片", "圖片", "Imágenes", "Images", "画像", "이미지") }
    static func allMedia(_ l: AppLanguage) -> String { text(l, "All", "全部", "全部", "Todo", "Tout", "すべて", "전체") }
    static func selectedCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) files selected", "已选择 \(count) 个文件", "已選擇 \(count) 個檔案", "\(count) archivos seleccionados", "\(count) fichiers sélectionnés", "\(count)個のファイルを選択", "\(count)개 파일 선택됨") }
    static func deleteSelected(_ count: Int, _ l: AppLanguage) -> String { text(l, "Delete Selected (\(count))…", "删除所选 (\(count))…", "刪除所選 (\(count))…", "Eliminar seleccionados (\(count))…", "Supprimer la sélection (\(count))…", "選択項目を削除 (\(count))…", "선택 항목 삭제 (\(count))…") }
    static func operationFailed(_ l: AppLanguage) -> String { text(l, "Operation Failed", "操作失败", "操作失敗", "Error en la operación", "Échec de l’opération", "操作に失敗しました", "작업 실패") }
    static func ok(_ l: AppLanguage) -> String { text(l, "OK", "好", "好", "Aceptar", "OK", "OK", "확인") }
    static func unknownError(_ l: AppLanguage) -> String { text(l, "Unknown error", "未知错误", "未知錯誤", "Error desconocido", "Erreur inconnue", "不明なエラー", "알 수 없는 오류") }
    static func similarVideos(_ l: AppLanguage) -> String { text(l, "Similar Videos", "相似视频", "相似影片", "Vídeos similares", "Vidéos similaires", "類似動画", "유사한 동영상") }
    static func similarMedia(_ l: AppLanguage) -> String { text(l, "Similar Media", "相似媒体", "相似媒體", "Medios similares", "Médias similaires", "類似メディア", "유사한 미디어") }
    static func displayThreshold(_ l: AppLanguage) -> String { text(l, "Display Threshold", "显示阈值", "顯示閾值", "Umbral de visualización", "Seuil d’affichage", "表示しきい値", "표시 임계값") }
    static func displayThresholdHelp(_ l: AppLanguage) -> String { text(l, "≥ 72% recommended; below that false positives increase.", "建议 ≥ 72%；低于此值误报增多。", "建議 ≥ 72%；低於此值誤報會增加。", "Se recomienda ≥ 72%; por debajo aumentan los falsos positivos.", "≥ 72 % recommandé ; en dessous, les faux positifs augmentent.", "≥ 72% 推奨。それ未満では誤検出が増えます。", "≥ 72% 권장; 그보다 낮으면 오탐이 늘어납니다.") }
    static func skippedFiles(_ count: Int, _ l: AppLanguage) -> String { text(l, "Skipped \(count) unreadable files", "跳过 \(count) 个无法读取的文件", "略過 \(count) 個無法讀取的檔案", "Se omitieron \(count) archivos ilegibles", "\(count) fichiers illisibles ignorés", "読み取れないファイルを \(count) 件スキップしました", "읽을 수 없는 파일 \(count)개 건너뜀") }
    static func noSimilarVideos(_ l: AppLanguage) -> String { text(l, "No Similar Videos Found", "没有发现相似视频", "未找到相似影片", "No se encontraron vídeos similares", "Aucune vidéo similaire trouvée", "類似動画が見つかりません", "유사한 동영상을 찾지 못함") }
    static func noSimilarMedia(_ l: AppLanguage) -> String { text(l, "No Similar Media Found", "没有发现相似媒体", "未找到相似媒體", "No se encontraron medios similares", "Aucun média similaire trouvé", "類似メディアが見つかりません", "유사한 미디어를 찾지 못함") }
    static func waitingToScan(_ l: AppLanguage) -> String { text(l, "Ready to Scan", "等待扫描", "準備掃描", "Listo para analizar", "Prêt à analyser", "スキャン準備完了", "스캔 준비 완료") }
    static func lowerThresholdHint(_ l: AppLanguage) -> String { text(l, "Lower the display threshold to review more results.", "可以降低显示阈值后再查看。", "可降低顯示閾值以查看更多結果。", "Reduce el umbral de visualización para revisar más resultados.", "Réduisez le seuil d’affichage pour voir plus de résultats.", "表示しきい値を下げると、より多くの結果を確認できます。", "표시 임계값을 낮추면 더 많은 결과를 검토할 수 있습니다.") }
    static func chooseAndScanHint(_ l: AppLanguage) -> String { text(l, "Add folders and start scanning.", "添加文件夹并开始扫描。", "新增資料夾並開始掃描。", "Añade carpetas e inicia el análisis.", "Ajoutez des dossiers et lancez l’analyse.", "フォルダを追加してスキャンを開始してください。", "폴더를 추가하고 스캔을 시작하세요.") }
    static func similarGroup(_ index: Int, _ l: AppLanguage) -> String { text(l, "Similar Group \(index)", "相似组 \(index)", "相似群組 \(index)", "Grupo similar \(index)", "Groupe similaire \(index)", "類似グループ \(index)", "유사 그룹 \(index)") }
    static func videoCountAndScore(_ count: Int, _ score: String, _ l: AppLanguage) -> String { text(l, "\(count) videos · \(score)", "\(count) 个 · \(score)", "\(count) 個 · \(score)", "\(count) vídeos · \(score)", "\(count) vidéos · \(score)", "\(count)本 · \(score)", "\(count)개 동영상 · \(score)") }
    static func mediaCountAndScore(_ count: Int, _ score: String, _ l: AppLanguage) -> String { text(l, "\(count) files · \(score)", "\(count) 个文件 · \(score)", "\(count) 個檔案 · \(score)", "\(count) archivos · \(score)", "\(count) fichiers · \(score)", "\(count)個のファイル · \(score)", "\(count)개 파일 · \(score)") }
    static func compareVideos(_ l: AppLanguage) -> String { text(l, "Compare Videos", "组内视频对比", "群組內影片對比", "Comparar vídeos", "Comparer les vidéos", "動画を比較", "동영상 비교") }
    static func compareMedia(_ l: AppLanguage) -> String { text(l, "Compare Media", "组内媒体对比", "群組內媒體對比", "Comparar medios", "Comparer les médias", "メディアを比較", "미디어 비교") }
    static func compareHint(_ l: AppLanguage) -> String { text(l, "Select a video and preview it on the right before deleting.", "选择一个视频，在右侧预览后决定是否删除。", "選擇一部影片，在右側預覽後再決定是否刪除。", "Selecciona un vídeo y previsualízalo a la derecha antes de eliminarlo.", "Sélectionnez une vidéo et prévisualisez-la à droite avant de la supprimer.", "動画を選択し、右側でプレビューしてから削除してください。", "동영상을 선택하고 오른쪽에서 미리 본 뒤 삭제하세요.") }
    static func compareMediaHint(_ l: AppLanguage) -> String { text(l, "Select a file and preview it on the right before deleting.", "选择一个文件，在右侧预览后决定是否删除。", "選擇一個檔案，在右側預覽後再決定是否刪除。", "Selecciona un archivo y previsualízalo a la derecha antes de eliminarlo.", "Sélectionnez un fichier et prévisualisez-le à droite avant de le supprimer.", "ファイルを選択し、右側でプレビューしてから削除してください。", "파일을 선택하고 오른쪽에서 미리 본 뒤 삭제하세요.") }
    static func highestSimilarity(_ score: String, _ l: AppLanguage) -> String { text(l, "Highest similarity \(score)", "最高相似度 \(score)", "最高相似度 \(score)", "Mayor similitud \(score)", "Similarité maximale \(score)", "最高類似度 \(score)", "최고 유사도 \(score)") }
    static func selectGroup(_ l: AppLanguage) -> String { text(l, "Select a Similar Group", "选择一个相似组", "選擇一個相似群組", "Selecciona un grupo similar", "Sélectionnez un groupe similaire", "類似グループを選択", "유사 그룹 선택") }
    static func resultsOnLeft(_ l: AppLanguage) -> String { text(l, "Scan results appear in the sidebar.", "扫描结果会显示在左侧。", "掃描結果會顯示在側邊欄。", "Los resultados del análisis aparecerán en la barra lateral.", "Les résultats de l’analyse apparaîtront dans la barre latérale.", "スキャン結果はサイドバーに表示されます。", "스캔 결과는 사이드바에 표시됩니다.") }
    static func videoComparison(_ l: AppLanguage) -> String { text(l, "Video Comparison", "视频对比", "影片對比", "Comparación de vídeos", "Comparaison de vidéos", "動画比較", "동영상 비교") }
    static func similarVideoCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) Similar Videos", "\(count) 个相似视频", "\(count) 部相似影片", "\(count) vídeos similares", "\(count) vidéos similaires", "\(count)本の類似動画", "\(count)개 유사 동영상") }
    static func mediaComparison(_ l: AppLanguage) -> String { text(l, "Media Comparison", "媒体对比", "媒體對比", "Comparación de medios", "Comparaison de médias", "メディア比較", "미디어 비교") }
    static func similarMediaCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) Similar Files", "\(count) 个相似文件", "\(count) 個相似檔案", "\(count) archivos similares", "\(count) fichiers similaires", "\(count)個の類似ファイル", "\(count)개 유사 파일") }
    static func fileSize(_ l: AppLanguage) -> String { text(l, "File Size", "文件大小", "檔案大小", "Tamaño", "Taille du fichier", "ファイルサイズ", "파일 크기") }
    static func duration(_ l: AppLanguage) -> String { text(l, "Duration", "时长", "時長", "Duración", "Durée", "長さ", "길이") }
    static func resolution(_ l: AppLanguage) -> String { text(l, "Resolution", "分辨率", "解析度", "Resolución", "Résolution", "解像度", "해상도") }
    static func path(_ l: AppLanguage) -> String { text(l, "Path", "路径", "路徑", "Ruta", "Chemin", "パス", "경로") }
    static func openDefaultPlayer(_ l: AppLanguage) -> String { text(l, "Open in Default Player", "默认播放器打开", "使用預設播放器開啟", "Abrir en el reproductor predeterminado", "Ouvrir dans le lecteur par défaut", "既定のプレーヤーで開く", "기본 플레이어로 열기") }
    static func showInFinder(_ l: AppLanguage) -> String { text(l, "Show in Finder", "在 Finder 中显示", "在 Finder 中顯示", "Mostrar en Finder", "Afficher dans le Finder", "Finderで表示", "Finder에서 보기") }
    static func deleteVideo(_ l: AppLanguage) -> String { text(l, "Delete This Video…", "删除这个视频…", "刪除此影片…", "Eliminar este vídeo…", "Supprimer cette vidéo…", "この動画を削除…", "이 동영상 삭제…") }
    static func deleteMedia(_ l: AppLanguage) -> String { text(l, "Delete This File…", "删除这个文件…", "刪除此檔案…", "Eliminar este archivo…", "Supprimer ce fichier…", "このファイルを削除…", "이 파일 삭제…") }
    static func selectVideo(_ l: AppLanguage) -> String { text(l, "Select a Video", "选择一个视频", "選擇一部影片", "Selecciona un vídeo", "Sélectionnez une vidéo", "動画を選択", "동영상 선택") }
    static func selectVideoHint(_ l: AppLanguage) -> String { text(l, "Click a video in the comparison area to preview it.", "在中间的对比列表中单击视频即可预览。", "在中間的對比列表中點選影片即可預覽。", "Haz clic en un vídeo en el área de comparación para previsualizarlo.", "Cliquez sur une vidéo dans la zone de comparaison pour la prévisualiser.", "比較エリアの動画をクリックしてプレビューします。", "비교 영역의 동영상을 클릭해 미리 봅니다.") }
    static func selectMedia(_ l: AppLanguage) -> String { text(l, "Select a File", "选择一个文件", "選擇一個檔案", "Selecciona un archivo", "Sélectionnez un fichier", "ファイルを選択", "파일 선택") }
    static func selectMediaHint(_ l: AppLanguage) -> String { text(l, "Click a file in the comparison area to preview it.", "在中间的对比列表中单击文件即可预览。", "在中間的對比列表中點選檔案即可預覽。", "Haz clic en un archivo en el área de comparación para previsualizarlo.", "Cliquez sur un fichier dans la zone de comparaison pour le prévisualiser.", "比較エリアのファイルをクリックしてプレビューします。", "비교 영역의 파일을 클릭해 미리 봅니다.") }
    static func previewAndDetails(_ l: AppLanguage) -> String { text(l, "Preview & Details", "预览与详情", "預覽與詳細資訊", "Vista previa y detalles", "Aperçu et détails", "プレビューと詳細", "미리보기 및 세부 정보") }
    static func deleteHow(_ l: AppLanguage) -> String { text(l, "How would you like to delete the selected files?", "如何删除所选文件？", "要如何刪除所選檔案？", "¿Cómo quieres eliminar los archivos seleccionados?", "Comment souhaitez-vous supprimer les fichiers sélectionnés ?", "選択したファイルをどのように削除しますか？", "선택한 파일을 어떻게 삭제할까요?") }
    static func permanentWarningTitle(_ l: AppLanguage) -> String { text(l, "Permanently Delete Selected Files?", "永久删除所选文件？", "永久刪除所選檔案？", "¿Eliminar permanentemente los archivos seleccionados?", "Supprimer définitivement les fichiers sélectionnés ?", "選択したファイルを完全に削除しますか？", "선택한 파일을 영구 삭제할까요?") }
    static func trashExplanation(_ l: AppLanguage) -> String { text(l, "Moving to Trash is recoverable. Permanent deletion requires another confirmation.", "移到废纸篓后仍可恢复。永久删除会再询问一次。", "移到垃圾桶後仍可復原。永久刪除會再確認一次。", "Mover a la papelera permite recuperar los archivos. La eliminación permanente requiere otra confirmación.", "Le déplacement vers la corbeille est réversible. La suppression définitive nécessite une autre confirmation.", "ゴミ箱に移動すると復元できます。完全削除にはもう一度確認が必要です。", "휴지통으로 이동하면 복구할 수 있습니다. 영구 삭제는 한 번 더 확인해야 합니다.") }
    static func cancel(_ l: AppLanguage) -> String { text(l, "Cancel", "取消", "取消", "Cancelar", "Annuler", "キャンセル", "취소") }
    static func permanentDelete(_ l: AppLanguage) -> String { text(l, "Delete Permanently…", "永久删除…", "永久刪除…", "Eliminar permanentemente…", "Supprimer définitivement…", "完全に削除…", "영구 삭제…") }
    static func moveToTrash(_ l: AppLanguage) -> String { text(l, "Move to Trash", "移到废纸篓", "移到垃圾桶", "Mover a la papelera", "Déplacer vers la corbeille", "ゴミ箱に移動", "휴지통으로 이동") }
    static func trashShortcutHint(_ l: AppLanguage) -> String { text(l, "Press Space to move to Trash.", "按空格键移到废纸篓。", "按空白鍵移到垃圾桶。", "Pulsa Espacio para mover a la papelera.", "Appuyez sur Espace pour déplacer vers la corbeille.", "スペースキーでゴミ箱に移動します。", "스페이스를 눌러 휴지통으로 이동합니다.") }
    static func irreversible(_ l: AppLanguage) -> String { text(l, "This bypasses Trash and cannot be undone.", "此操作不会经过废纸篓，文件将无法恢复。", "此操作會略過垃圾桶，無法復原。", "Esto omite la papelera y no se puede deshacer.", "Cette action contourne la corbeille et ne peut pas être annulée.", "ゴミ箱を経由せず、元に戻せません。", "휴지통을 거치지 않으며 되돌릴 수 없습니다.") }
    static func back(_ l: AppLanguage) -> String { text(l, "Back", "返回", "返回", "Atrás", "Retour", "戻る", "뒤로") }
    static func confirmPermanent(_ l: AppLanguage) -> String { text(l, "Confirm Permanent Delete", "确认永久删除", "確認永久刪除", "Confirmar eliminación permanente", "Confirmer la suppression définitive", "完全削除を確認", "영구 삭제 확인") }
    static func clearCache(_ l: AppLanguage) -> String { text(l, "Clear Cache", "清除缓存", "清除快取", "Borrar caché", "Vider le cache", "キャッシュをクリア", "캐시 지우기") }
    static func settings(_ l: AppLanguage) -> String { text(l, "Settings", "设置", "設定", "Ajustes", "Réglages", "設定", "설정") }
    static func deepVerification(_ l: AppLanguage) -> String { text(l, "Deep Verification", "深度验证", "深度驗證", "Verificación profunda", "Vérification approfondie", "深度検証", "심층 검증") }
    static func deepVerificationHelp(_ l: AppLanguage) -> String { text(l, "Enables Vision frame comparison for borderline video pairs. The first scan is slower but more accurate. Applies to the next scan.", "对边界视频配对启用 Vision 帧比对。首次扫描更慢但更准确，对下一次扫描生效。", "對邊界影片配對啟用 Vision 幀比對。首次掃描較慢但更準確，對下一次掃描生效。", "Habilita la comparación de fotogramas con Vision para los pares de vídeos dudosos. El primer análisis es más lento pero más preciso. Se aplica al próximo análisis.", "Active la comparaison d'images par Vision pour les paires de vidéos limites. La première analyse est plus lente mais plus précise. S'applique à la prochaine analyse.", "境界付近の動画ペアに対し Vision でフレーム比較を行います。初回スキャンは遅くなりますがより正確です。次回のスキャンから適用されます。", "경계선에 있는 동영상 쌍에 대해 Vision 프레임 비교를 켭니다. 첫 스캔은 느려지지만 더 정확합니다. 다음 스캔부터 적용됩니다.") }
    static func clearCacheConfirmTitle(_ l: AppLanguage) -> String { text(l, "Clear the cache?", "要清除缓存吗？", "要清除快取嗎？", "¿Borrar la caché?", "Vider le cache ?", "キャッシュをクリアしますか？", "캐시를 지울까요?") }
    static func clearCacheConfirmMessage(_ thumbnailMB: String, _ hashMB: String, _ l: AppLanguage) -> String { text(l, "Currently \(thumbnailMB) MB of thumbnails and \(hashMB) MB of hash data are cached. Clearing them means the next scan must recompute everything, so it will be noticeably slower. We don't recommend doing this often.", "当前缓存了 \(thumbnailMB) MB 缩略图和 \(hashMB) MB 哈希数据。清除后下次扫描需全部重算，会明显变慢。不建议经常清理。", "目前快取了 \(thumbnailMB) MB 縮圖和 \(hashMB) MB 哈希資料。清除後下次掃描需全部重算，會明顯變慢。不建議經常清理。", "Actualmente hay \(thumbnailMB) MB de miniaturas y \(hashMB) MB de datos hash en la caché. Borrarlos obliga al próximo análisis a recalcular todo, lo que será notablemente más lento. No se recomienda hacerlo con frecuencia.", "Actuellement \(thumbnailMB) Mo de vignettes et \(hashMB) Mo de données de hachage sont en cache. Les vider oblige la prochaine analyse à tout recalculer, ce qui sera nettement plus lent. Nous déconseillons de le faire souvent.", "現在、\(thumbnailMB) MB のサムネイルと \(hashMB) MB のハッシュデータがキャッシュされています。クリアすると次回スキャンですべて再計算するため、かなり遅くなります。頻繁な実行はおすすめしません。", "현재 \(thumbnailMB) MB의 썸네일과 \(hashMB) MB의 해시 데이터가 캐시되어 있습니다. 지우면 다음 스캔에서 모두 다시 계산해야 해서 눈에 띄게 느려집니다. 자주 실행하는 것은 권장하지 않습니다.") }
    static func chooseVideoFolder(_ l: AppLanguage) -> String { text(l, "Choose Folders to Scan", "选择要扫描的文件夹", "選擇要掃描的資料夾", "Elige carpetas para analizar", "Choisir les dossiers à analyser", "スキャンするフォルダを選択", "스캔할 폴더 선택") }
    static func unknown(_ l: AppLanguage) -> String { text(l, "Unknown", "未知", "未知", "Desconocido", "Inconnu", "不明", "알 수 없음") }
    static func noVideoTrack(_ l: AppLanguage) -> String { text(l, "No readable video track was found", "未找到可读取的视频轨道", "未找到可讀取的影片軌道", "No se encontró ninguna pista de vídeo legible", "Aucune piste vidéo lisible n’a été trouvée", "読み取り可能な動画トラックが見つかりません", "읽을 수 있는 동영상 트랙을 찾지 못했습니다") }
    static func unreadableImage(_ l: AppLanguage) -> String { text(l, "Image could not be read", "图片无法读取", "圖片無法讀取", "No se pudo leer la imagen", "L’image n’a pas pu être lue", "画像を読み取れません", "이미지를 읽을 수 없습니다") }
    static func fileMissing(_ l: AppLanguage) -> String { text(l, "The file no longer exists", "文件已不存在", "檔案已不存在", "El archivo ya no existe", "Le fichier n’existe plus", "ファイルはもう存在しません", "파일이 더 이상 존재하지 않습니다") }
    static func deletionFailed(_ message: String, _ l: AppLanguage) -> String { text(l, "Deletion failed: \(message)", "删除失败：\(message)", "刪除失敗：\(message)", "Error al eliminar: \(message)", "Échec de la suppression : \(message)", "削除に失敗しました：\(message)", "삭제 실패: \(message)") }

    // Batch Deduplication
    static func cleanDuplicates(_ l: AppLanguage) -> String { text(l, "Clean Duplicates", "清理重复文件", "清理重複檔案", "Eliminar duplicados", "Nettoyer les doublons", "重複ファイルを削除", "중복 파일 정리") }
    static func deleteDuplicatesInGroup(_ l: AppLanguage) -> String { text(l, "Delete Duplicates in This Group", "删除本组重复项", "刪除本組重複項目", "Eliminar duplicados del grupo", "Supprimer les doublons du groupe", "このグループの重複を削除", "이 그룹의 중복 삭제") }
    static func keepStrategy(_ l: AppLanguage) -> String { text(l, "Keep strategy:", "保留策略：", "保留策略：", "Estrategia de conservación:", "Stratégie de conservation :", "保持方法：", "보관 전략:") }
    static func keepSmallest(_ l: AppLanguage) -> String { text(l, "Keep smallest file", "保留体积最小的文件", "保留體積最小的檔案", "Conservar el archivo más pequeño", "Garder le plus petit fichier", "最小のファイルを保持", "가장 작은 파일 유지") }
    static func keepLargest(_ l: AppLanguage) -> String { text(l, "Keep largest file", "保留体积最大的文件", "保留體積最大的檔案", "Conservar el archivo más grande", "Garder le plus grand fichier", "最大のファイルを保持", "가장 큰 파일 유지") }
    static func keepHighestResolution(_ l: AppLanguage) -> String { text(l, "Keep highest resolution", "保留分辨率最高的文件", "保留解析度最高的檔案", "Conservar la mayor resolución", "Garder la plus haute résolution", "最高解像度のファイルを保持", "가장 높은 해상도 유지") }
    static func keepOldest(_ l: AppLanguage) -> String { text(l, "Keep oldest file", "保留最早的文件", "保留最早的檔案", "Conservar el archivo más antiguo", "Garder le plus ancien fichier", "最も古いファイルを保持", "가장 오래된 파일 유지") }
    static func keepNewest(_ l: AppLanguage) -> String { text(l, "Keep newest file", "保留最新的文件", "保留最新的檔案", "Conservar el archivo más reciente", "Garder le plus récent fichier", "最も新しいファイルを保持", "가장 새로운 파일 유지") }
    static func groupsAffected(_ l: AppLanguage) -> String { text(l, "Groups affected", "涉及组数", "涉及群組數", "Grupos afectados", "Groupes concernés", "対象グループ", "영향받는 그룹") }
    static func filesToDelete(_ l: AppLanguage) -> String { text(l, "Files to delete", "待删除文件数", "待刪除檔案數", "Archivos a eliminar", "Fichiers à supprimer", "削除対象ファイル", "삭제할 파일") }
    static func spaceToReclaim(_ l: AppLanguage) -> String { text(l, "Space to reclaim", "可回收空间", "可回收空間", "Espacio a recuperar", "Espace à récupérer", "解放される容量", "회수 가능 공간") }
    static func noDuplicatesToRemove(_ l: AppLanguage) -> String { text(l, "No duplicate files to remove with the current strategy.", "当前策略下没有可删除的重复文件。", "目前策略下沒有可刪除的重複檔案。", "No hay archivos duplicados que eliminar con la estrategia actual.", "Aucun fichier en double à supprimer avec la stratégie actuelle.", "現在の方法では削除する重複ファイルはありません。", "현재 전략으로 삭제할 중복 파일이 없습니다.") }
    static func trashCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "Move \(count) to Trash", "将 \(count) 个文件移到废纸篓", "將 \(count) 個檔案移到垃圾桶", "Mover \(count) a la papelera", "Déplacer \(count) vers la corbeille", "\(count)件をゴミ箱に移動", "\(count)개를 휴지통으로 이동") }

    // Player
    static func pictureInPicture(_ l: AppLanguage) -> String { text(l, "Picture in Picture", "画中画", "子母畫面", "Imagen en imagen", "Image dans l’image", "ピクチャ・イン・ピクチャ", "화면 속 화면") }

    // Browse feature
    static func browse(_ l: AppLanguage) -> String { text(l, "Browse", "浏览", "瀏覽", "Explorar", "Parcourir", "閲覧", "찾아보기") }
    static func filter(_ l: AppLanguage) -> String { text(l, "Filter", "筛选", "篩選", "Filtrar", "Filtrer", "フィルタ", "필터") }
    static func select(_ l: AppLanguage) -> String { text(l, "Select", "选择", "選擇", "Seleccionar", "Sélectionner", "選択", "선택") }
    static func done(_ l: AppLanguage) -> String { text(l, "Done", "完成", "完成", "Listo", "Terminé", "完了", "완료") }
    static func selectAll(_ l: AppLanguage) -> String { text(l, "Select All", "全选", "全選", "Seleccionar todo", "Tout sélectionner", "すべて選択", "모두 선택") }
    static func clearSelection(_ l: AppLanguage) -> String { text(l, "Clear", "清除", "清除", "Borrar", "Effacer", "クリア", "지우기") }
    static func name(_ l: AppLanguage) -> String { text(l, "Name", "名称", "名稱", "Nombre", "Nom", "名前", "이름") }
    static func modifiedTime(_ l: AppLanguage) -> String { text(l, "Modified", "修改时间", "修改時間", "Modificado", "Modifié", "更新日時", "수정됨") }
    static func thumbnail(_ l: AppLanguage) -> String { text(l, "Preview", "缩略图", "縮圖", "Vista previa", "Aperçu", "プレビュー", "미리보기") }
    static func mediaType(_ l: AppLanguage) -> String { text(l, "Media Type", "媒体类型", "媒體類型", "Tipo de medio", "Type de média", "メディア種別", "미디어 유형") }
    static func width(_ l: AppLanguage) -> String { text(l, "Width", "宽", "寬", "Ancho", "Largeur", "幅", "너비") }
    static func height(_ l: AppLanguage) -> String { text(l, "Height", "高", "高", "Alto", "Hauteur", "高さ", "높이") }
    static func clearFilter(_ l: AppLanguage) -> String { text(l, "Clear Filter", "清除筛选", "清除篩選", "Borrar filtro", "Effacer le filtre", "フィルタをクリア", "필터 지우기") }
    static func browseItemCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) items", "\(count) 项", "\(count) 項", "\(count) elementos", "\(count) éléments", "\(count)項目", "\(count)개 항목") }
    static func noItemsToBrowse(_ l: AppLanguage) -> String { text(l, "No Items to Browse", "无可浏览的文件", "沒有可瀏覽的檔案", "No hay elementos para explorar", "Aucun élément à parcourir", "閲覧できる項目がありません", "찾아볼 항목 없음") }
    static func noItemsBrowseHint(_ l: AppLanguage) -> String { text(l, "Add folders and browse to see files.", "添加文件夹并浏览以查看文件。", "新增資料夾並瀏覽以查看檔案。", "Añade carpetas y explora para ver archivos.", "Ajoutez des dossiers et parcourez-les pour voir les fichiers.", "フォルダを追加して閲覧するとファイルを確認できます。", "폴더를 추가하고 찾아보면 파일을 볼 수 있습니다.") }
    static func discoveringFiles(_ l: AppLanguage) -> String { text(l, "Discovering files…", "正在发现文件…", "正在搜尋檔案…", "Buscando archivos…", "Recherche de fichiers…", "ファイルを検索中…", "파일 찾는 중…") }
    static func searchFiles(_ l: AppLanguage) -> String { text(l, "Search files", "搜索文件", "搜尋檔案", "Buscar archivos", "Rechercher des fichiers", "ファイルを検索", "파일 검색") }

    // Resolution sort
    static func resolutionSort(_ l: AppLanguage) -> String { text(l, "Resolution Sort", "分辨率排序", "解析度排序", "Ordenar por resolución", "Tri par résolution", "解像度ソート", "해상도 정렬") }
    static func sortBy(_ l: AppLanguage) -> String { text(l, "Sort by", "排序依据", "排序依據", "Ordenar por", "Trier par", "並び替え", "정렬 기준") }
    static func sortByWidth(_ l: AppLanguage) -> String { text(l, "Width (left)", "宽度（左）", "寬度（左）", "Ancho (izquierda)", "Largeur (gauche)", "幅（左）", "너비(왼쪽)") }
    static func sortByHeight(_ l: AppLanguage) -> String { text(l, "Height (right)", "高度（右）", "高度（右）", "Alto (derecha)", "Hauteur (droite)", "高さ（右）", "높이(오른쪽)") }
    static func sortDirection(_ l: AppLanguage) -> String { text(l, "Direction", "方向", "方向", "Dirección", "Sens", "方向", "방향") }
    static func sort(_ l: AppLanguage) -> String { text(l, "Sort", "排序", "排序", "Ordenar", "Trier", "ソート", "정렬") }
    static func sortSimilarity(_ l: AppLanguage) -> String { text(l, "Similarity", "相似度", "相似度", "Similitud", "Similarité", "類似度", "유사도") }
    static func ascending(_ l: AppLanguage) -> String { text(l, "Ascending", "升序", "升冪", "Ascendente", "Croissant", "昇順", "오름차순") }
    static func descending(_ l: AppLanguage) -> String { text(l, "Descending", "降序", "降冪", "Descendente", "Décroissant", "降順", "내림차순") }

    static func evidence(_ value: SimilarityEvidence, _ l: AppLanguage) -> String {
        switch value {
        case .identicalContentHash: text(l, "Identical content", "内容完全一致", "內容完全一致", "Contenido idéntico", "Contenu identique", "同一コンテンツ", "동일한 콘텐츠")
        case .similarPerceptualHash: text(l, "Matching fingerprint", "指纹匹配", "指紋相符", "Huella coincidente", "Empreinte correspondante", "フィンガープリント一致", "지문 일치")
        case .similarFrames: text(l, "Similar frames", "画面相似", "畫面相似", "Fotogramas similares", "Images similaires", "類似フレーム", "유사한 프레임")
        case .similarDuration: text(l, "Similar duration", "时长接近", "時長接近", "Duración similar", "Durée similaire", "類似した長さ", "유사한 길이")
        case .similarDimensions: text(l, "Similar resolution", "分辨率接近", "解析度接近", "Resolución similar", "Résolution similaire", "類似解像度", "유사한 해상도")
        case .similarSize: text(l, "Similar file size", "文件大小接近", "檔案大小接近", "Tamaño de archivo similar", "Taille de fichier similaire", "類似ファイルサイズ", "유사한 파일 크기")
        case .similarName: text(l, "Similar file name", "文件名接近", "檔名接近", "Nombre de archivo similar", "Nom de fichier similaire", "類似ファイル名", "유사한 파일 이름")
        }
    }

    static func scanStage(_ stage: ScanStage, _ l: AppLanguage) -> String {
        switch stage {
        case .idle: text(l, "Ready to scan", "等待扫描", "準備掃描", "Listo para analizar", "Prêt à analyser", "スキャン準備完了", "스캔 준비 완료")
        case .discovering: text(l, "Finding media files", "正在查找媒体文件", "正在尋找媒體檔案", "Buscando archivos multimedia", "Recherche des fichiers multimédias", "メディアファイルを検索中", "미디어 파일 찾는 중")
        case .readingMetadata: text(l, "Reading media information", "正在读取媒体信息", "正在讀取媒體資訊", "Leyendo información multimedia", "Lecture des informations multimédias", "メディア情報を読み取り中", "미디어 정보 읽는 중")
        case .prehashing: text(l, "Filtering candidates", "正在筛选候选", "正在篩選候選項目", "Filtrando candidatos", "Filtrage des candidats", "候補を絞り込み中", "후보 필터링 중")
        case .hashing: text(l, "Computing media fingerprints", "正在计算媒体指纹", "正在計算媒體指紋", "Calculando huellas multimedia", "Calcul des empreintes multimédias", "メディアフィンガープリントを計算中", "미디어 지문 계산 중")
        case .comparing: text(l, "Comparing media", "正在比较媒体", "正在比較媒體", "Comparando medios", "Comparaison des médias", "メディアを比較中", "미디어 비교 중")
        case .completed: text(l, "Scan complete", "扫描完成", "掃描完成", "Análisis completado", "Analyse terminée", "スキャン完了", "스캔 완료")
        case .cancelled: text(l, "Scan cancelled", "扫描已取消", "掃描已取消", "Análisis cancelado", "Analyse annulée", "スキャンをキャンセルしました", "스캔 취소됨")
        }
    }

    static func scanProgressTitle(_ progress: ScanProgress, _ l: AppLanguage) -> String {
        guard progress.stage == .comparing, let phase = progress.comparisonPhase else {
            return scanStage(progress.stage, l)
        }
        switch phase {
        case .findingCandidates:
            return text(
                l,
                "Finding candidate pairs",
                "正在查找候选配对",
                "正在尋找候選配對",
                "Buscando pares candidatos",
                "Recherche des paires candidates",
                "候補ペアを検索中",
                "후보 쌍 찾는 중"
            )
        case .checkingPairCache:
            return text(
                l,
                "Checking pair cache",
                "正在检查配对缓存",
                "正在檢查配對快取",
                "Comprobando caché de pares",
                "Vérification du cache des paires",
                "ペアキャッシュを確認中",
                "쌍 캐시 확인 중"
            )
        case .comparingUncached:
            return text(
                l,
                "Comparing uncached pairs",
                "正在比较未缓存配对",
                "正在比較未快取配對",
                "Comparando pares sin caché",
                "Comparaison des paires non mises en cache",
                "未キャッシュのペアを比較中",
                "캐시되지 않은 쌍 비교 중"
            )
        }
    }

    static func scanProgressDetail(_ progress: ScanProgress, _ l: AppLanguage) -> String {
        var parts: [String] = []
        if progress.stage == .comparing, let comparisonPhase = progress.comparisonPhase {
            parts.append(comparisonProgressText(phase: comparisonPhase, progress: progress, l))
            if !progress.currentFile.isEmpty {
                parts.append(progress.currentFile)
            }
            return parts.joined(separator: " - ")
        }
        if let cacheKind = progress.cacheKind, progress.cacheHits > 0, progress.cacheTotal > 0 {
            parts.append(cacheHitText(kind: cacheKind, hits: progress.cacheHits, total: progress.cacheTotal, l))
        }
        if !progress.currentFile.isEmpty {
            parts.append(progress.currentFile)
        }
        return parts.joined(separator: " - ")
    }

    private static func comparisonProgressText(phase: ScanComparisonPhase, progress: ScanProgress, _ l: AppLanguage) -> String {
        let total = max(progress.comparisonTotal, 0)
        let completed = max(0, min(progress.comparisonCompleted, total))
        switch phase {
        case .findingCandidates:
            return text(
                l,
                "Checked files: \(completed) of \(total)",
                "已检查文件：\(completed) / \(total)",
                "已檢查檔案：\(completed) / \(total)",
                "Archivos comprobados: \(completed) de \(total)",
                "Fichiers vérifiés : \(completed) sur \(total)",
                "確認済みファイル：\(completed) / \(total)",
                "확인한 파일: \(completed) / \(total)"
            )
        case .checkingPairCache:
            let clampedHits = max(0, min(progress.cacheHits, progress.cacheTotal))
            return text(
                l,
                "Checking pair cache: hits \(clampedHits) of \(progress.cacheTotal)",
                "正在检查配对缓存：命中 \(clampedHits) / \(progress.cacheTotal)",
                "正在檢查配對快取：命中 \(clampedHits) / \(progress.cacheTotal)",
                "Comprobando caché de pares: \(clampedHits) de \(progress.cacheTotal)",
                "Vérification du cache des paires : \(clampedHits) sur \(progress.cacheTotal)",
                "ペアキャッシュを確認中：命中 \(clampedHits) / \(progress.cacheTotal)",
                "쌍 캐시 확인 중: 적중 \(clampedHits) / \(progress.cacheTotal)"
            )
        case .comparingUncached:
            return text(
                l,
                "Comparing uncached pairs: \(completed) of \(total)",
                "正在比较未缓存配对：\(completed) / \(total)",
                "正在比較未快取配對：\(completed) / \(total)",
                "Comparando pares sin caché: \(completed) de \(total)",
                "Comparaison des paires non mises en cache : \(completed) sur \(total)",
                "未キャッシュのペアを比較中：\(completed) / \(total)",
                "캐시되지 않은 쌍 비교 중: \(completed) / \(total)"
            )
        }
    }

    private static func cacheHitText(kind: ScanProgressCacheKind, hits: Int, total: Int, _ l: AppLanguage) -> String {
        let clampedHits = max(0, min(hits, total))
        switch kind {
        case .metadata:
            return text(
                l,
                "Metadata cache hits: \(clampedHits) of \(total)",
                "元数据缓存命中：\(clampedHits) / \(total)",
                "中繼資料快取命中：\(clampedHits) / \(total)",
                "Aciertos de caché de metadatos: \(clampedHits) de \(total)",
                "Métadonnées en cache : \(clampedHits) sur \(total)",
                "メタデータキャッシュ命中：\(clampedHits) / \(total)",
                "메타데이터 캐시 적중: \(clampedHits) / \(total)"
            )
        case .fingerprint:
            return text(
                l,
                "Fingerprint cache hits: \(clampedHits) of \(total)",
                "指纹缓存命中：\(clampedHits) / \(total)",
                "指紋快取命中：\(clampedHits) / \(total)",
                "Aciertos de caché de huellas: \(clampedHits) de \(total)",
                "Empreintes en cache : \(clampedHits) sur \(total)",
                "フィンガープリントキャッシュ命中：\(clampedHits) / \(total)",
                "지문 캐시 적중: \(clampedHits) / \(total)"
            )
        case .relation:
            return text(
                l,
                "Pair comparison cache hits: \(clampedHits) of \(total)",
                "配对比较缓存命中：\(clampedHits) / \(total)",
                "配對比較快取命中：\(clampedHits) / \(total)",
                "Aciertos de caché de comparaciones: \(clampedHits) de \(total)",
                "Comparaisons en cache : \(clampedHits) sur \(total)",
                "ペア比較キャッシュ命中：\(clampedHits) / \(total)",
                "쌍 비교 캐시 적중: \(clampedHits) / \(total)"
            )
        }
    }
}
