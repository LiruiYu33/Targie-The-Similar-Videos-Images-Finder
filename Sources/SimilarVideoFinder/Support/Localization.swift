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

    static let defaultLanguage = AppLanguage.english
    var id: String { rawValue }

    var menuLabel: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .spanish: "Español"
        case .french: "Français"
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
        _ traditionalChinese: String? = nil,
        _ spanish: String? = nil,
        _ french: String? = nil
    ) -> String {
        switch language {
        case .english: english
        case .simplifiedChinese: simplifiedChinese
        case .traditionalChinese: traditionalChinese ?? simplifiedChinese
        case .spanish: spanish ?? english
        case .french: french ?? english
        }
    }

    static func appName(_ l: AppLanguage) -> String { text(l, "Targie", "Targie", "Targie", "Targie", "Targie") }
    static func chooseFolder(_ l: AppLanguage) -> String { text(l, "Choose Folder", "选择文件夹", "選擇資料夾", "Elegir carpeta", "Choisir un dossier") }
    static func changeFolder(_ l: AppLanguage) -> String { text(l, "Change Folder", "更换文件夹", "更換資料夾", "Cambiar carpeta", "Changer de dossier") }
    static func addFolders(_ l: AppLanguage) -> String { text(l, "Add Folders", "添加文件夹", "新增資料夾", "Añadir carpetas", "Ajouter des dossiers") }
    static func clearFolders(_ l: AppLanguage) -> String { text(l, "Clear Folder Selection", "清除文件夹选择", "清除資料夾選擇", "Borrar selección de carpetas", "Effacer la sélection de dossiers") }
    static func removeFolder(_ l: AppLanguage) -> String { text(l, "Remove Folder", "移除文件夹", "移除資料夾", "Quitar carpeta", "Supprimer le dossier") }
    static func foldersSelected(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) folders selected", "已添加 \(count) 个文件夹", "已新增 \(count) 個資料夾", "\(count) carpetas seleccionadas", "\(count) dossiers sélectionnés") }
    static func dragFoldersHint(_ l: AppLanguage) -> String { text(l, "Drag one or more folders into this window.", "可将一个或多个文件夹拖入此窗口。", "可將一個或多個資料夾拖入此視窗。", "Arrastra una o más carpetas a esta ventana.", "Faites glisser un ou plusieurs dossiers dans cette fenêtre.") }
    static func startScan(_ l: AppLanguage) -> String { text(l, "Start Scan", "开始扫描", "開始掃描", "Iniciar análisis", "Lancer l’analyse") }
    static func cancelScan(_ l: AppLanguage) -> String { text(l, "Cancel Scan", "取消扫描", "取消掃描", "Cancelar análisis", "Annuler l’analyse") }
    static func language(_ l: AppLanguage) -> String { text(l, "Language", "语言", "語言", "Idioma", "Langue") }
    static func videos(_ l: AppLanguage) -> String { text(l, "Videos", "视频", "影片", "Vídeos", "Vidéos") }
    static func images(_ l: AppLanguage) -> String { text(l, "Images", "图片", "圖片", "Imágenes", "Images") }
    static func allMedia(_ l: AppLanguage) -> String { text(l, "All", "全部", "全部", "Todo", "Tout") }
    static func selectedCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) files selected", "已选择 \(count) 个文件", "已選擇 \(count) 個檔案", "\(count) archivos seleccionados", "\(count) fichiers sélectionnés") }
    static func deleteSelected(_ count: Int, _ l: AppLanguage) -> String { text(l, "Delete Selected (\(count))…", "删除所选 (\(count))…", "刪除所選 (\(count))…", "Eliminar seleccionados (\(count))…", "Supprimer la sélection (\(count))…") }
    static func operationFailed(_ l: AppLanguage) -> String { text(l, "Operation Failed", "操作失败", "操作失敗", "Error en la operación", "Échec de l’opération") }
    static func ok(_ l: AppLanguage) -> String { text(l, "OK", "好", "好", "Aceptar", "OK") }
    static func unknownError(_ l: AppLanguage) -> String { text(l, "Unknown error", "未知错误", "未知錯誤", "Error desconocido", "Erreur inconnue") }
    static func similarVideos(_ l: AppLanguage) -> String { text(l, "Similar Videos", "相似视频", "相似影片", "Vídeos similares", "Vidéos similaires") }
    static func similarMedia(_ l: AppLanguage) -> String { text(l, "Similar Media", "相似媒体", "相似媒體", "Medios similares", "Médias similaires") }
    static func displayThreshold(_ l: AppLanguage) -> String { text(l, "Display Threshold", "显示阈值", "顯示閾值", "Umbral de visualización", "Seuil d’affichage") }
    static func displayThresholdHelp(_ l: AppLanguage) -> String { text(l, "≥ 72% recommended; below that false positives increase.", "建议 ≥ 72%；低于此值误报增多。", "建議 ≥ 72%；低於此值誤報會增加。", "Se recomienda ≥ 72%; por debajo aumentan los falsos positivos.", "≥ 72 % recommandé ; en dessous, les faux positifs augmentent.") }
    static func skippedFiles(_ count: Int, _ l: AppLanguage) -> String { text(l, "Skipped \(count) unreadable files", "跳过 \(count) 个无法读取的文件", "略過 \(count) 個無法讀取的檔案", "Se omitieron \(count) archivos ilegibles", "\(count) fichiers illisibles ignorés") }
    static func noSimilarVideos(_ l: AppLanguage) -> String { text(l, "No Similar Videos Found", "没有发现相似视频", "未找到相似影片", "No se encontraron vídeos similares", "Aucune vidéo similaire trouvée") }
    static func noSimilarMedia(_ l: AppLanguage) -> String { text(l, "No Similar Media Found", "没有发现相似媒体", "未找到相似媒體", "No se encontraron medios similares", "Aucun média similaire trouvé") }
    static func waitingToScan(_ l: AppLanguage) -> String { text(l, "Ready to Scan", "等待扫描", "準備掃描", "Listo para analizar", "Prêt à analyser") }
    static func lowerThresholdHint(_ l: AppLanguage) -> String { text(l, "Lower the display threshold to review more results.", "可以降低显示阈值后再查看。", "可降低顯示閾值以查看更多結果。", "Reduce el umbral de visualización para revisar más resultados.", "Réduisez le seuil d’affichage pour voir plus de résultats.") }
    static func chooseAndScanHint(_ l: AppLanguage) -> String { text(l, "Add folders and start scanning.", "添加文件夹并开始扫描。", "新增資料夾並開始掃描。", "Añade carpetas e inicia el análisis.", "Ajoutez des dossiers et lancez l’analyse.") }
    static func similarGroup(_ index: Int, _ l: AppLanguage) -> String { text(l, "Similar Group \(index)", "相似组 \(index)", "相似群組 \(index)", "Grupo similar \(index)", "Groupe similaire \(index)") }
    static func videoCountAndScore(_ count: Int, _ score: String, _ l: AppLanguage) -> String { text(l, "\(count) videos · \(score)", "\(count) 个 · \(score)", "\(count) 個 · \(score)", "\(count) vídeos · \(score)", "\(count) vidéos · \(score)") }
    static func mediaCountAndScore(_ count: Int, _ score: String, _ l: AppLanguage) -> String { text(l, "\(count) files · \(score)", "\(count) 个文件 · \(score)", "\(count) 個檔案 · \(score)", "\(count) archivos · \(score)", "\(count) fichiers · \(score)") }
    static func compareVideos(_ l: AppLanguage) -> String { text(l, "Compare Videos", "组内视频对比", "群組內影片對比", "Comparar vídeos", "Comparer les vidéos") }
    static func compareMedia(_ l: AppLanguage) -> String { text(l, "Compare Media", "组内媒体对比", "群組內媒體對比", "Comparar medios", "Comparer les médias") }
    static func compareHint(_ l: AppLanguage) -> String { text(l, "Select a video and preview it on the right before deleting.", "选择一个视频，在右侧预览后决定是否删除。", "選擇一部影片，在右側預覽後再決定是否刪除。", "Selecciona un vídeo y previsualízalo a la derecha antes de eliminarlo.", "Sélectionnez une vidéo et prévisualisez-la à droite avant de la supprimer.") }
    static func compareMediaHint(_ l: AppLanguage) -> String { text(l, "Select a file and preview it on the right before deleting.", "选择一个文件，在右侧预览后决定是否删除。", "選擇一個檔案，在右側預覽後再決定是否刪除。", "Selecciona un archivo y previsualízalo a la derecha antes de eliminarlo.", "Sélectionnez un fichier et prévisualisez-le à droite avant de le supprimer.") }
    static func highestSimilarity(_ score: String, _ l: AppLanguage) -> String { text(l, "Highest similarity \(score)", "最高相似度 \(score)", "最高相似度 \(score)", "Mayor similitud \(score)", "Similarité maximale \(score)") }
    static func selectGroup(_ l: AppLanguage) -> String { text(l, "Select a Similar Group", "选择一个相似组", "選擇一個相似群組", "Selecciona un grupo similar", "Sélectionnez un groupe similaire") }
    static func resultsOnLeft(_ l: AppLanguage) -> String { text(l, "Scan results appear in the sidebar.", "扫描结果会显示在左侧。", "掃描結果會顯示在側邊欄。", "Los resultados del análisis aparecerán en la barra lateral.", "Les résultats de l’analyse apparaîtront dans la barre latérale.") }
    static func videoComparison(_ l: AppLanguage) -> String { text(l, "Video Comparison", "视频对比", "影片對比", "Comparación de vídeos", "Comparaison de vidéos") }
    static func similarVideoCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) Similar Videos", "\(count) 个相似视频", "\(count) 部相似影片", "\(count) vídeos similares", "\(count) vidéos similaires") }
    static func mediaComparison(_ l: AppLanguage) -> String { text(l, "Media Comparison", "媒体对比", "媒體對比", "Comparación de medios", "Comparaison de médias") }
    static func similarMediaCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) Similar Files", "\(count) 个相似文件", "\(count) 個相似檔案", "\(count) archivos similares", "\(count) fichiers similaires") }
    static func fileSize(_ l: AppLanguage) -> String { text(l, "File Size", "文件大小", "檔案大小", "Tamaño", "Taille du fichier") }
    static func duration(_ l: AppLanguage) -> String { text(l, "Duration", "时长", "時長", "Duración", "Durée") }
    static func resolution(_ l: AppLanguage) -> String { text(l, "Resolution", "分辨率", "解析度", "Resolución", "Résolution") }
    static func path(_ l: AppLanguage) -> String { text(l, "Path", "路径", "路徑", "Ruta", "Chemin") }
    static func openDefaultPlayer(_ l: AppLanguage) -> String { text(l, "Open in Default Player", "默认播放器打开", "使用預設播放器開啟", "Abrir en el reproductor predeterminado", "Ouvrir dans le lecteur par défaut") }
    static func showInFinder(_ l: AppLanguage) -> String { text(l, "Show in Finder", "在 Finder 中显示", "在 Finder 中顯示", "Mostrar en Finder", "Afficher dans le Finder") }
    static func deleteVideo(_ l: AppLanguage) -> String { text(l, "Delete This Video…", "删除这个视频…", "刪除此影片…", "Eliminar este vídeo…", "Supprimer cette vidéo…") }
    static func deleteMedia(_ l: AppLanguage) -> String { text(l, "Delete This File…", "删除这个文件…", "刪除此檔案…", "Eliminar este archivo…", "Supprimer ce fichier…") }
    static func selectVideo(_ l: AppLanguage) -> String { text(l, "Select a Video", "选择一个视频", "選擇一部影片", "Selecciona un vídeo", "Sélectionnez une vidéo") }
    static func selectVideoHint(_ l: AppLanguage) -> String { text(l, "Click a video in the comparison area to preview it.", "在中间的对比列表中单击视频即可预览。", "在中間的對比列表中點選影片即可預覽。", "Haz clic en un vídeo en el área de comparación para previsualizarlo.", "Cliquez sur une vidéo dans la zone de comparaison pour la prévisualiser.") }
    static func selectMedia(_ l: AppLanguage) -> String { text(l, "Select a File", "选择一个文件", "選擇一個檔案", "Selecciona un archivo", "Sélectionnez un fichier") }
    static func selectMediaHint(_ l: AppLanguage) -> String { text(l, "Click a file in the comparison area to preview it.", "在中间的对比列表中单击文件即可预览。", "在中間的對比列表中點選檔案即可預覽。", "Haz clic en un archivo en el área de comparación para previsualizarlo.", "Cliquez sur un fichier dans la zone de comparaison pour le prévisualiser.") }
    static func previewAndDetails(_ l: AppLanguage) -> String { text(l, "Preview & Details", "预览与详情", "預覽與詳細資訊", "Vista previa y detalles", "Aperçu et détails") }
    static func deleteHow(_ l: AppLanguage) -> String { text(l, "How would you like to delete the selected files?", "如何删除所选文件？", "要如何刪除所選檔案？", "¿Cómo quieres eliminar los archivos seleccionados?", "Comment souhaitez-vous supprimer les fichiers sélectionnés ?") }
    static func permanentWarningTitle(_ l: AppLanguage) -> String { text(l, "Permanently Delete Selected Files?", "永久删除所选文件？", "永久刪除所選檔案？", "¿Eliminar permanentemente los archivos seleccionados?", "Supprimer définitivement les fichiers sélectionnés ?") }
    static func trashExplanation(_ l: AppLanguage) -> String { text(l, "Moving to Trash is recoverable. Permanent deletion requires another confirmation.", "移到废纸篓后仍可恢复。永久删除会再询问一次。", "移到垃圾桶後仍可復原。永久刪除會再確認一次。", "Mover a la papelera permite recuperar los archivos. La eliminación permanente requiere otra confirmación.", "Le déplacement vers la corbeille est réversible. La suppression définitive nécessite une autre confirmation.") }
    static func cancel(_ l: AppLanguage) -> String { text(l, "Cancel", "取消", "取消", "Cancelar", "Annuler") }
    static func permanentDelete(_ l: AppLanguage) -> String { text(l, "Delete Permanently…", "永久删除…", "永久刪除…", "Eliminar permanentemente…", "Supprimer définitivement…") }
    static func moveToTrash(_ l: AppLanguage) -> String { text(l, "Move to Trash", "移到废纸篓", "移到垃圾桶", "Mover a la papelera", "Déplacer vers la corbeille") }
    static func trashShortcutHint(_ l: AppLanguage) -> String { text(l, "Press Space to move to Trash.", "按空格键移到废纸篓。", "按空白鍵移到垃圾桶。", "Pulsa Espacio para mover a la papelera.", "Appuyez sur Espace pour déplacer vers la corbeille.") }
    static func irreversible(_ l: AppLanguage) -> String { text(l, "This bypasses Trash and cannot be undone.", "此操作不会经过废纸篓，文件将无法恢复。", "此操作會略過垃圾桶，無法復原。", "Esto omite la papelera y no se puede deshacer.", "Cette action contourne la corbeille et ne peut pas être annulée.") }
    static func back(_ l: AppLanguage) -> String { text(l, "Back", "返回", "返回", "Atrás", "Retour") }
    static func confirmPermanent(_ l: AppLanguage) -> String { text(l, "Confirm Permanent Delete", "确认永久删除", "確認永久刪除", "Confirmar eliminación permanente", "Confirmer la suppression définitive") }
    static func clearCache(_ l: AppLanguage) -> String { text(l, "Clear Cache", "清除缓存", "清除快取", "Borrar caché", "Vider le cache") }
    static func clearCacheConfirmTitle(_ l: AppLanguage) -> String { text(l, "Clear the cache?", "要清除缓存吗？", "要清除快取嗎？", "¿Borrar la caché?", "Vider le cache ?") }
    static func clearCacheConfirmMessage(_ thumbnailMB: String, _ hashMB: String, _ l: AppLanguage) -> String { text(l, "Currently \(thumbnailMB) MB of thumbnails and \(hashMB) MB of hash data are cached. Clearing them means the next scan must recompute everything, so it will be noticeably slower. We don't recommend doing this often.", "当前缓存了 \(thumbnailMB) MB 缩略图和 \(hashMB) MB 哈希数据。清除后下次扫描需全部重算，会明显变慢。不建议经常清理。", "目前快取了 \(thumbnailMB) MB 縮圖和 \(hashMB) MB 哈希資料。清除後下次掃描需全部重算，會明顯變慢。不建議經常清理。", "Actualmente hay \(thumbnailMB) MB de miniaturas y \(hashMB) MB de datos hash en la caché. Borrarlos obliga al próximo análisis a recalcular todo, lo que será notablemente más lento. No se recomienda hacerlo con frecuencia.", "Actuellement \(thumbnailMB) Mo de vignettes et \(hashMB) Mo de données de hachage sont en cache. Les vider oblige la prochaine analyse à tout recalculer, ce qui sera nettement plus lent. Nous déconseillons de le faire souvent.") }
    static func chooseVideoFolder(_ l: AppLanguage) -> String { text(l, "Choose Folders to Scan", "选择要扫描的文件夹", "選擇要掃描的資料夾", "Elige carpetas para analizar", "Choisir les dossiers à analyser") }
    static func unknown(_ l: AppLanguage) -> String { text(l, "Unknown", "未知", "未知", "Desconocido", "Inconnu") }
    static func noVideoTrack(_ l: AppLanguage) -> String { text(l, "No readable video track was found", "未找到可读取的视频轨道", "未找到可讀取的影片軌道", "No se encontró ninguna pista de vídeo legible", "Aucune piste vidéo lisible n’a été trouvée") }
    static func unreadableImage(_ l: AppLanguage) -> String { text(l, "Image could not be read", "图片无法读取", "圖片無法讀取", "No se pudo leer la imagen", "L’image n’a pas pu être lue") }
    static func fileMissing(_ l: AppLanguage) -> String { text(l, "The file no longer exists", "文件已不存在", "檔案已不存在", "El archivo ya no existe", "Le fichier n’existe plus") }
    static func deletionFailed(_ message: String, _ l: AppLanguage) -> String { text(l, "Deletion failed: \(message)", "删除失败：\(message)", "刪除失敗：\(message)", "Error al eliminar: \(message)", "Échec de la suppression : \(message)") }

    // Browse feature
    static func browse(_ l: AppLanguage) -> String { text(l, "Browse", "浏览", "瀏覽", "Explorar", "Parcourir") }
    static func filter(_ l: AppLanguage) -> String { text(l, "Filter", "筛选", "篩選", "Filtrar", "Filtrer") }
    static func select(_ l: AppLanguage) -> String { text(l, "Select", "选择", "選擇", "Seleccionar", "Sélectionner") }
    static func done(_ l: AppLanguage) -> String { text(l, "Done", "完成", "完成", "Listo", "Terminé") }
    static func selectAll(_ l: AppLanguage) -> String { text(l, "Select All", "全选", "全選", "Seleccionar todo", "Tout sélectionner") }
    static func clearSelection(_ l: AppLanguage) -> String { text(l, "Clear", "清除", "清除", "Borrar", "Effacer") }
    static func name(_ l: AppLanguage) -> String { text(l, "Name", "名称", "名稱", "Nombre", "Nom") }
    static func modifiedTime(_ l: AppLanguage) -> String { text(l, "Modified", "修改时间", "修改時間", "Modificado", "Modifié") }
    static func thumbnail(_ l: AppLanguage) -> String { text(l, "Preview", "缩略图", "縮圖", "Vista previa", "Aperçu") }
    static func mediaType(_ l: AppLanguage) -> String { text(l, "Media Type", "媒体类型", "媒體類型", "Tipo de medio", "Type de média") }
    static func width(_ l: AppLanguage) -> String { text(l, "Width", "宽", "寬", "Ancho", "Largeur") }
    static func height(_ l: AppLanguage) -> String { text(l, "Height", "高", "高", "Alto", "Hauteur") }
    static func clearFilter(_ l: AppLanguage) -> String { text(l, "Clear Filter", "清除筛选", "清除篩選", "Borrar filtro", "Effacer le filtre") }
    static func browseItemCount(_ count: Int, _ l: AppLanguage) -> String { text(l, "\(count) items", "\(count) 项", "\(count) 項", "\(count) elementos", "\(count) éléments") }
    static func noItemsToBrowse(_ l: AppLanguage) -> String { text(l, "No Items to Browse", "无可浏览的文件", "沒有可瀏覽的檔案", "No hay elementos para explorar", "Aucun élément à parcourir") }
    static func noItemsBrowseHint(_ l: AppLanguage) -> String { text(l, "Add folders and browse to see files.", "添加文件夹并浏览以查看文件。", "新增資料夾並瀏覽以查看檔案。", "Añade carpetas y explora para ver archivos.", "Ajoutez des dossiers et parcourez-les pour voir les fichiers.") }
    static func discoveringFiles(_ l: AppLanguage) -> String { text(l, "Discovering files…", "正在发现文件…", "正在搜尋檔案…", "Buscando archivos…", "Recherche de fichiers…") }
    static func searchFiles(_ l: AppLanguage) -> String { text(l, "Search files", "搜索文件", "搜尋檔案", "Buscar archivos", "Rechercher des fichiers") }

    // Resolution sort
    static func resolutionSort(_ l: AppLanguage) -> String { text(l, "Resolution Sort", "分辨率排序", "解析度排序", "Ordenar por resolución", "Tri par résolution") }
    static func sortBy(_ l: AppLanguage) -> String { text(l, "Sort by", "排序依据", "排序依據", "Ordenar por", "Trier par") }
    static func sortByWidth(_ l: AppLanguage) -> String { text(l, "Width (left)", "宽度（左）", "寬度（左）", "Ancho (izquierda)", "Largeur (gauche)") }
    static func sortByHeight(_ l: AppLanguage) -> String { text(l, "Height (right)", "高度（右）", "高度（右）", "Alto (derecha)", "Hauteur (droite)") }
    static func sortDirection(_ l: AppLanguage) -> String { text(l, "Direction", "方向", "方向", "Dirección", "Sens") }
    static func sort(_ l: AppLanguage) -> String { text(l, "Sort", "排序", "排序", "Ordenar", "Trier") }
    static func sortSimilarity(_ l: AppLanguage) -> String { text(l, "Similarity", "相似度", "相似度", "Similitud", "Similarité") }
    static func ascending(_ l: AppLanguage) -> String { text(l, "Ascending", "升序", "升冪", "Ascendente", "Croissant") }
    static func descending(_ l: AppLanguage) -> String { text(l, "Descending", "降序", "降冪", "Descendente", "Décroissant") }

    static func evidence(_ value: SimilarityEvidence, _ l: AppLanguage) -> String {
        switch value {
        case .identicalContentHash: text(l, "Identical content", "内容完全一致", "內容完全一致", "Contenido idéntico", "Contenu identique")
        case .similarPerceptualHash: text(l, "Matching fingerprint", "指纹匹配", "指紋相符", "Huella coincidente", "Empreinte correspondante")
        case .similarFrames: text(l, "Similar frames", "画面相似", "畫面相似", "Fotogramas similares", "Images similaires")
        case .similarDuration: text(l, "Similar duration", "时长接近", "時長接近", "Duración similar", "Durée similaire")
        case .similarDimensions: text(l, "Similar resolution", "分辨率接近", "解析度接近", "Resolución similar", "Résolution similaire")
        case .similarSize: text(l, "Similar file size", "文件大小接近", "檔案大小接近", "Tamaño de archivo similar", "Taille de fichier similaire")
        case .similarName: text(l, "Similar file name", "文件名接近", "檔名接近", "Nombre de archivo similar", "Nom de fichier similaire")
        }
    }

    static func scanStage(_ stage: ScanStage, _ l: AppLanguage) -> String {
        switch stage {
        case .idle: text(l, "Ready to scan", "等待扫描", "準備掃描", "Listo para analizar", "Prêt à analyser")
        case .discovering: text(l, "Finding media files", "正在查找媒体文件", "正在尋找媒體檔案", "Buscando archivos multimedia", "Recherche des fichiers multimédias")
        case .readingMetadata: text(l, "Reading media information", "正在读取媒体信息", "正在讀取媒體資訊", "Leyendo información multimedia", "Lecture des informations multimédias")
        case .prehashing: text(l, "Filtering candidates", "正在筛选候选", "正在篩選候選項目", "Filtrando candidatos", "Filtrage des candidats")
        case .hashing: text(l, "Computing media fingerprints", "正在计算媒体指纹", "正在計算媒體指紋", "Calculando huellas multimedia", "Calcul des empreintes multimédias")
        case .comparing: text(l, "Comparing media", "正在比较媒体", "正在比較媒體", "Comparando medios", "Comparaison des médias")
        case .completed: text(l, "Scan complete", "扫描完成", "掃描完成", "Análisis completado", "Analyse terminée")
        case .cancelled: text(l, "Scan cancelled", "扫描已取消", "掃描已取消", "Análisis cancelado", "Analyse annulée")
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
                "Recherche des paires candidates"
            )
        case .checkingPairCache:
            return text(
                l,
                "Checking pair cache",
                "正在检查配对缓存",
                "正在檢查配對快取",
                "Comprobando caché de pares",
                "Vérification du cache des paires"
            )
        case .comparingUncached:
            return text(
                l,
                "Comparing uncached pairs",
                "正在比较未缓存配对",
                "正在比較未快取配對",
                "Comparando pares sin caché",
                "Comparaison des paires non mises en cache"
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
                "Finding candidate pairs: \(completed) of \(total)",
                "正在查找候选配对：\(completed) / \(total)",
                "正在尋找候選配對：\(completed) / \(total)",
                "Buscando pares candidatos: \(completed) de \(total)",
                "Recherche des paires candidates : \(completed) sur \(total)"
            )
        case .checkingPairCache:
            let clampedHits = max(0, min(progress.cacheHits, progress.cacheTotal))
            return text(
                l,
                "Checking pair cache: hits \(clampedHits) of \(progress.cacheTotal)",
                "正在检查配对缓存：命中 \(clampedHits) / \(progress.cacheTotal)",
                "正在檢查配對快取：命中 \(clampedHits) / \(progress.cacheTotal)",
                "Comprobando caché de pares: \(clampedHits) de \(progress.cacheTotal)",
                "Vérification du cache des paires : \(clampedHits) sur \(progress.cacheTotal)"
            )
        case .comparingUncached:
            return text(
                l,
                "Comparing uncached pairs: \(completed) of \(total)",
                "正在比较未缓存配对：\(completed) / \(total)",
                "正在比較未快取配對：\(completed) / \(total)",
                "Comparando pares sin caché: \(completed) de \(total)",
                "Comparaison des paires non mises en cache : \(completed) sur \(total)"
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
                "Métadonnées en cache : \(clampedHits) sur \(total)"
            )
        case .fingerprint:
            return text(
                l,
                "Fingerprint cache hits: \(clampedHits) of \(total)",
                "指纹缓存命中：\(clampedHits) / \(total)",
                "指紋快取命中：\(clampedHits) / \(total)",
                "Aciertos de caché de huellas: \(clampedHits) de \(total)",
                "Empreintes en cache : \(clampedHits) sur \(total)"
            )
        case .relation:
            return text(
                l,
                "Pair comparison cache hits: \(clampedHits) of \(total)",
                "配对比较缓存命中：\(clampedHits) / \(total)",
                "配對比較快取命中：\(clampedHits) / \(total)",
                "Aciertos de caché de comparaciones: \(clampedHits) de \(total)",
                "Comparaisons en cache : \(clampedHits) sur \(total)"
            )
        }
    }
}
