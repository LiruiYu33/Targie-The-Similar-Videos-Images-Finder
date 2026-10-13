#!/usr/bin/env python3
"""Builds the Targie website (GitHub Pages) into a static folder.

Usage:
    python3 script/build_site.py [--out _site] [--base-url URL]

Inputs
    site/static/        copied as-is (css, images, icons)
    releases/v*.md      one file per version; each holds the notes in all
                        seven languages under "## <Language>" headings

Outputs one home page and one changelog page per language, plus
sitemap.xml, robots.txt and 404.html. Uses only the standard library.

To publish a new version's notes, add releases/vX.Y.Z.md and merge; the
Pages workflow rebuilds the site.
"""

from __future__ import annotations

import argparse
import html
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = "LiruiYu33/Targie-The-Similar-Videos-Images-Finder"
DEFAULT_BASE_URL = "https://liruiyu33.github.io/Targie-The-Similar-Videos-Images-Finder/"
GITHUB_URL = f"https://github.com/{REPO}"


@dataclass(frozen=True)
class Lang:
    code: str          # key and URL folder ("" for the default language)
    html_lang: str     # <html lang> and hreflang
    name: str          # shown in the language menu
    md_heading: str    # "## <heading>" used in releases/*.md
    og_locale: str

    @property
    def folder(self) -> str:
        return "" if self.code == "en" else self.code


LANGS = [
    Lang("en", "en", "English", "English", "en_US"),
    Lang("zh", "zh-Hans", "简体中文", "简体中文", "zh_CN"),
    Lang("zh-hant", "zh-Hant", "繁體中文", "繁體中文", "zh_TW"),
    Lang("es", "es", "Español", "Español", "es_ES"),
    Lang("fr", "fr", "Français", "Français", "fr_FR"),
    Lang("ja", "ja", "日本語", "日本語", "ja_JP"),
    Lang("ko", "ko", "한국어", "한국어", "ko_KR"),
]

# Page copy. Keep the keys identical across languages.
STR: dict[str, dict] = {
    "en": {
        "title": "Targie — Find similar and duplicate photos & videos on Mac",
        "desc": "Targie is a free, open-source macOS app that finds similar and duplicate videos and photos across folders using perceptual hashing and Apple Vision. Review them side by side, then move the extras to the Trash.",
        "h1": "Find similar and duplicate photos & videos on your Mac",
        "sub": "Targie scans folders for near-identical videos and images — re-encoded, resized or recompressed copies included — so you can review them side by side and reclaim space safely.",
        "download": "Download for macOS",
        "github": "View on GitHub",
        "req": "Free & open source · macOS 14 or later · Apple Silicon and Intel",
        "latest": "Latest version",
        "nav": ["Features", "Screenshots", "Install", "FAQ", "Changelog"],
        "sections": ["Features", "Screenshots", "Download & install", "Frequently asked questions"],
        "features": [
            ("Videos and images in one scan", "Compares common video formats plus JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF and BMP across as many folders as you add, recursively."),
            ("Finds more than exact copies", "Combines SHA-256, perceptual fingerprints, metadata and Apple Vision features, so re-encoded, resized or recompressed versions are matched too."),
            ("Review side by side", "Similar files are grouped for side-by-side comparison with in-app previews. Open a video in your default player or reveal any file in Finder."),
            ("Delete with care", "Select with checkboxes or by dragging, then choose Trash or permanent deletion explicitly. Permanent deletion always asks a second time."),
            ("Browse mode", "A sortable, filterable table of every file in your folders, with resolution filters, search (⌘F) and batch selection."),
            ("Private and native", "Runs entirely on your Mac and never uploads your files. A native macOS app for Apple Silicon and Intel, available in seven languages."),
        ],
        "shots": [
            ("Drop folders to start", "Targie welcome screen"),
            ("Compare similar images side by side", "Similar images compared side by side in Targie"),
            ("Spot near-duplicate videos", "Similar videos grouped in Targie"),
            ("Browse every file in a sortable table", "Targie Browse mode with a sortable file table and preview"),
        ],
        "install": [
            "Download the latest Targie zip from the Releases page and unzip it.",
            "Drag Targie.app into your Applications folder.",
            "The app is ad-hoc signed, so macOS blocks the first launch. Right-click (or Control-click) Targie, choose Open, then click Open. Or open System Settings → Privacy & Security and click Allow Anyway. You only need to do this once.",
        ],
        "faq": [
            ("Is Targie free?", "Yes. Targie is free and open source under the GPL-3.0 license."),
            ("Does Targie upload my files?", "No. Scanning and comparison happen entirely on your Mac, and your files never leave it."),
            ("Why does macOS block Targie the first time?", "Targie is ad-hoc signed rather than notarized. Right-click the app and choose Open once; macOS won't ask again."),
            ("Does a high similarity score mean the files are duplicates?", "Scores indicate visual similarity, not the probability of an exact duplicate. Review files side by side before deleting them."),
            ("Is there a Windows or Linux version?", "No. Targie is a native macOS 14+ app and there are no plans for other platforms."),
        ],
        "changelog": "Changelog",
        "changelog_title": "Targie changelog — what's new in each version",
        "changelog_desc": "Release notes for every version of Targie, the free macOS app that finds similar and duplicate photos and videos.",
        "changelog_intro": "What's new in each version of Targie.",
        "all_releases": "All releases on GitHub",
        "home": "Home",
        "footer": "Targie is free software under the GNU GPL v3.0. © 2026 Lirui Yu.",
        "language": "Language",
        "not_found": "Page not found",
        "not_found_back": "Back to the home page",
    },
    "zh": {
        "title": "Targie — 在 Mac 上查找相似与重复的照片和视频",
        "desc": "Targie 是一款免费开源的 macOS 应用，借助感知哈希与 Apple Vision 在多个文件夹中查找相似和重复的视频与图片，并排比对后再安全清理。",
        "h1": "在 Mac 上查找相似与重复的照片和视频",
        "sub": "Targie 扫描文件夹中近乎相同的视频和图片——包括重新编码、缩放或重新压缩的副本——让你并排检查，安心释放空间。",
        "download": "下载 macOS 版",
        "github": "在 GitHub 上查看",
        "req": "免费开源 · 需要 macOS 14 或更新版本 · 支持 Apple Silicon 与 Intel",
        "latest": "最新版本",
        "nav": ["功能", "截图", "安装", "常见问题", "更新日志"],
        "sections": ["功能", "界面截图", "下载与安装", "常见问题"],
        "features": [
            ("一次扫描，视频和图片全搞定", "递归比较常见视频格式，以及 JPEG、PNG、HEIC、HEIF、WebP、TIFF、GIF 和 BMP 图片，可同时添加多个文件夹。"),
            ("不止找完全相同的文件", "综合 SHA-256、感知指纹、元数据和 Apple Vision 特征，重新编码、缩放或重新压缩的版本也能匹配。"),
            ("并排检查", "相似文件按组并排显示，并提供应用内预览。可用默认播放器打开视频，或在 Finder 中显示任意文件。"),
            ("谨慎删除", "可勾选或拖动框选文件，并明确选择移到废纸篓还是永久删除；永久删除会再次确认。"),
            ("浏览模式", "以可排序、可筛选的表格浏览文件夹中的所有文件，支持分辨率筛选、搜索（⌘F）和批量选择。"),
            ("私密且原生", "完全在本机运行，不会上传你的文件。原生 macOS 应用，支持 Apple Silicon 与 Intel，提供七种界面语言。"),
        ],
        "shots": [
            ("拖入文件夹即可开始", "Targie 欢迎界面"),
            ("并排比较相似图片", "Targie 中并排比较的相似图片"),
            ("找出近乎重复的视频", "Targie 中分组显示的相似视频"),
            ("在可排序的表格中浏览所有文件", "Targie 浏览模式：可排序的文件表格与预览"),
        ],
        "install": [
            "在 Releases 页面下载最新的 Targie 压缩包并解压。",
            "将 Targie.app 拖入“应用程序”文件夹。",
            "应用使用临时签名，首次启动时 macOS 会拦截。右键（或按住 Control 点击）Targie，选择“打开”，再点“打开”；也可前往“系统设置 → 隐私与安全性”，点击“仍然允许”。只需操作一次。",
        ],
        "faq": [
            ("Targie 免费吗？", "免费，并以 GPL-3.0 协议开源。"),
            ("Targie 会上传我的文件吗？", "不会。扫描和比较都在你的 Mac 上完成，文件不会离开本机。"),
            ("为什么 macOS 首次打开时会拦截？", "Targie 使用临时签名，未经公证。右键选择“打开”一次即可，之后不会再询问。"),
            ("相似度很高就一定是重复文件吗？", "分数表示视觉相似程度，并非文件重复的概率。删除前请并排检查。"),
            ("有 Windows 或 Linux 版本吗？", "没有。Targie 是原生 macOS 14+ 应用，也没有计划支持其他平台。"),
        ],
        "changelog": "更新日志",
        "changelog_title": "Targie 更新日志 — 每个版本的新内容",
        "changelog_desc": "Targie 每个版本的更新说明。Targie 是免费的 macOS 应用，用于查找相似和重复的照片与视频。",
        "changelog_intro": "Targie 每个版本的新内容。",
        "all_releases": "在 GitHub 上查看全部版本",
        "home": "首页",
        "footer": "Targie 是以 GNU GPL v3.0 授权的自由软件。© 2026 Lirui Yu。",
        "language": "语言",
        "not_found": "页面不存在",
        "not_found_back": "返回首页",
    },
    "zh-hant": {
        "title": "Targie — 在 Mac 上尋找相似與重複的照片和影片",
        "desc": "Targie 是一款免費開源的 macOS 應用程式，藉由感知雜湊與 Apple Vision 在多個資料夾中尋找相似和重複的影片與圖片，並排比對後再安全清理。",
        "h1": "在 Mac 上尋找相似與重複的照片和影片",
        "sub": "Targie 掃描資料夾中近乎相同的影片和圖片——包括重新編碼、縮放或重新壓縮的副本——讓你並排檢查，安心釋出空間。",
        "download": "下載 macOS 版",
        "github": "在 GitHub 上檢視",
        "req": "免費開源 · 需要 macOS 14 或更新版本 · 支援 Apple Silicon 與 Intel",
        "latest": "最新版本",
        "nav": ["功能", "截圖", "安裝", "常見問題", "更新日誌"],
        "sections": ["功能", "介面截圖", "下載與安裝", "常見問題"],
        "features": [
            ("一次掃描，影片和圖片一併處理", "遞迴比較常見影片格式，以及 JPEG、PNG、HEIC、HEIF、WebP、TIFF、GIF 和 BMP 圖片，可同時加入多個資料夾。"),
            ("不只找完全相同的檔案", "綜合 SHA-256、感知指紋、中繼資料和 Apple Vision 特徵，重新編碼、縮放或重新壓縮的版本也能比對出來。"),
            ("並排檢查", "相似檔案依群組並排顯示，並提供 App 內預覽。可用預設播放器開啟影片，或在 Finder 中顯示任何檔案。"),
            ("謹慎刪除", "可勾選或拖曳框選檔案，並明確選擇移到垃圾桶或永久刪除；永久刪除會再次確認。"),
            ("瀏覽模式", "以可排序、可篩選的表格瀏覽資料夾中的所有檔案，支援解析度篩選、搜尋（⌘F）和批次選取。"),
            ("私密且原生", "完全在本機執行，不會上傳你的檔案。原生 macOS 應用程式，支援 Apple Silicon 與 Intel，提供七種介面語言。"),
        ],
        "shots": [
            ("拖入資料夾即可開始", "Targie 歡迎畫面"),
            ("並排比較相似圖片", "Targie 中並排比較的相似圖片"),
            ("找出近乎重複的影片", "Targie 中分組顯示的相似影片"),
            ("在可排序的表格中瀏覽所有檔案", "Targie 瀏覽模式：可排序的檔案表格與預覽"),
        ],
        "install": [
            "在 Releases 頁面下載最新的 Targie 壓縮檔並解壓縮。",
            "將 Targie.app 拖入「應用程式」資料夾。",
            "App 使用暫時簽名，首次開啟時 macOS 會攔截。按右鍵（或按住 Control 點按）Targie，選擇「打開」，再按「打開」；也可前往「系統設定 → 隱私權與安全性」，按「仍要允許」。只需操作一次。",
        ],
        "faq": [
            ("Targie 免費嗎？", "免費，並以 GPL-3.0 授權開源。"),
            ("Targie 會上傳我的檔案嗎？", "不會。掃描和比對都在你的 Mac 上完成，檔案不會離開本機。"),
            ("為什麼 macOS 首次開啟時會攔截？", "Targie 使用暫時簽名，未經公證。按右鍵選擇「打開」一次即可，之後不會再詢問。"),
            ("相似度很高就一定是重複檔案嗎？", "分數表示視覺相似程度，並非檔案重複的機率。刪除前請並排檢查。"),
            ("有 Windows 或 Linux 版本嗎？", "沒有。Targie 是原生 macOS 14+ 應用程式，也沒有支援其他平台的計畫。"),
        ],
        "changelog": "更新日誌",
        "changelog_title": "Targie 更新日誌 — 每個版本的新內容",
        "changelog_desc": "Targie 每個版本的更新說明。Targie 是免費的 macOS 應用程式，用於尋找相似和重複的照片與影片。",
        "changelog_intro": "Targie 每個版本的新內容。",
        "all_releases": "在 GitHub 上檢視所有版本",
        "home": "首頁",
        "footer": "Targie 是以 GNU GPL v3.0 授權的自由軟體。© 2026 Lirui Yu。",
        "language": "語言",
        "not_found": "找不到頁面",
        "not_found_back": "回到首頁",
    },
    "es": {
        "title": "Targie — Encuentra fotos y vídeos similares y duplicados en tu Mac",
        "desc": "Targie es una app gratuita y de código abierto para macOS que encuentra vídeos e imágenes similares y duplicados en varias carpetas con hashing perceptual y Apple Vision. Compáralos lado a lado y mueve los sobrantes a la papelera.",
        "h1": "Encuentra fotos y vídeos similares y duplicados en tu Mac",
        "sub": "Targie analiza carpetas en busca de vídeos e imágenes casi idénticos —incluidas copias recodificadas, redimensionadas o recomprimidas— para que los revises lado a lado y recuperes espacio con seguridad.",
        "download": "Descargar para macOS",
        "github": "Ver en GitHub",
        "req": "Gratis y de código abierto · macOS 14 o posterior · Apple Silicon e Intel",
        "latest": "Última versión",
        "nav": ["Funciones", "Capturas", "Instalación", "Preguntas", "Novedades"],
        "sections": ["Funciones", "Capturas de pantalla", "Descarga e instalación", "Preguntas frecuentes"],
        "features": [
            ("Vídeos e imágenes en un solo análisis", "Compara formatos de vídeo habituales y también JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF y BMP en todas las carpetas que añadas, de forma recursiva."),
            ("Encuentra más que copias exactas", "Combina SHA-256, huellas perceptuales, metadatos y características de Apple Vision, así que también detecta versiones recodificadas, redimensionadas o recomprimidas."),
            ("Revisa lado a lado", "Los archivos similares se agrupan para compararlos lado a lado con vistas previas en la app. Abre un vídeo en tu reproductor predeterminado o muéstralo en Finder."),
            ("Elimina con cuidado", "Selecciona con casillas o arrastrando y elige de forma explícita entre la papelera y la eliminación permanente, que siempre pide una segunda confirmación."),
            ("Modo Browse", "Una tabla ordenable y filtrable con todos los archivos de tus carpetas, con filtros de resolución, búsqueda (⌘F) y selección por lotes."),
            ("Privada y nativa", "Se ejecuta por completo en tu Mac y nunca sube tus archivos. App nativa de macOS para Apple Silicon e Intel, disponible en siete idiomas."),
        ],
        "shots": [
            ("Suelta carpetas para empezar", "Pantalla de bienvenida de Targie"),
            ("Compara imágenes similares lado a lado", "Imágenes similares comparadas lado a lado en Targie"),
            ("Detecta vídeos casi duplicados", "Vídeos similares agrupados en Targie"),
            ("Explora todos los archivos en una tabla ordenable", "Modo Browse de Targie con tabla de archivos ordenable y vista previa"),
        ],
        "install": [
            "Descarga el zip más reciente de Targie desde la página de Releases y descomprímelo.",
            "Arrastra Targie.app a tu carpeta Aplicaciones.",
            "La app tiene firma ad hoc, por lo que macOS bloquea el primer arranque. Haz clic derecho (o Control-clic) en Targie, elige Abrir y vuelve a pulsar Abrir. También puedes ir a Ajustes del Sistema → Privacidad y seguridad y pulsar Abrir de todos modos. Solo hace falta una vez.",
        ],
        "faq": [
            ("¿Targie es gratis?", "Sí. Targie es gratuito y de código abierto bajo la licencia GPL-3.0."),
            ("¿Targie sube mis archivos?", "No. El análisis y la comparación se hacen por completo en tu Mac y tus archivos no salen de él."),
            ("¿Por qué macOS lo bloquea la primera vez?", "Targie tiene firma ad hoc y no está notarizada. Haz clic derecho y elige Abrir una vez; macOS no volverá a preguntar."),
            ("¿Una puntuación alta significa que son duplicados?", "Las puntuaciones indican similitud visual, no la probabilidad de que sean duplicados exactos. Revísalos lado a lado antes de eliminar."),
            ("¿Hay versión para Windows o Linux?", "No. Targie es una app nativa de macOS 14 o posterior y no hay planes para otras plataformas."),
        ],
        "changelog": "Novedades",
        "changelog_title": "Novedades de Targie — qué hay de nuevo en cada versión",
        "changelog_desc": "Notas de cada versión de Targie, la app gratuita de macOS que encuentra fotos y vídeos similares y duplicados.",
        "changelog_intro": "Qué hay de nuevo en cada versión de Targie.",
        "all_releases": "Ver todas las versiones en GitHub",
        "home": "Inicio",
        "footer": "Targie es software libre con licencia GNU GPL v3.0. © 2026 Lirui Yu.",
        "language": "Idioma",
        "not_found": "Página no encontrada",
        "not_found_back": "Volver al inicio",
    },
    "fr": {
        "title": "Targie — Trouvez les photos et vidéos similaires ou en double sur votre Mac",
        "desc": "Targie est une app macOS gratuite et open source qui trouve les vidéos et images similaires ou en double dans plusieurs dossiers grâce au hachage perceptuel et à Apple Vision. Comparez-les côte à côte, puis déplacez les doublons vers la corbeille.",
        "h1": "Trouvez les photos et vidéos similaires ou en double sur votre Mac",
        "sub": "Targie analyse vos dossiers à la recherche de vidéos et d’images quasi identiques — y compris les copies réencodées, redimensionnées ou recompressées — pour que vous les examiniez côte à côte et récupériez de l’espace en toute sécurité.",
        "download": "Télécharger pour macOS",
        "github": "Voir sur GitHub",
        "req": "Gratuit et open source · macOS 14 ou version ultérieure · Apple Silicon et Intel",
        "latest": "Dernière version",
        "nav": ["Fonctions", "Captures", "Installation", "FAQ", "Nouveautés"],
        "sections": ["Fonctions", "Captures d’écran", "Téléchargement et installation", "Questions fréquentes"],
        "features": [
            ("Vidéos et images en une seule analyse", "Compare les formats vidéo courants ainsi que JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF et BMP dans tous les dossiers ajoutés, de manière récursive."),
            ("Trouve plus que des copies exactes", "Combine SHA-256, empreintes perceptuelles, métadonnées et caractéristiques Apple Vision, afin de repérer aussi les versions réencodées, redimensionnées ou recompressées."),
            ("Comparez côte à côte", "Les fichiers similaires sont regroupés pour une comparaison côte à côte avec aperçus intégrés. Ouvrez une vidéo dans votre lecteur par défaut ou affichez un fichier dans le Finder."),
            ("Supprimez avec prudence", "Sélectionnez avec les cases ou en faisant glisser, puis choisissez explicitement la corbeille ou la suppression définitive, qui demande toujours une seconde confirmation."),
            ("Mode Browse", "Un tableau triable et filtrable de tous les fichiers de vos dossiers, avec filtres de résolution, recherche (⌘F) et sélection par lot."),
            ("Privé et natif", "Fonctionne entièrement sur votre Mac et n’envoie jamais vos fichiers. App macOS native pour Apple Silicon et Intel, disponible en sept langues."),
        ],
        "shots": [
            ("Déposez des dossiers pour commencer", "Écran d’accueil de Targie"),
            ("Comparez des images similaires côte à côte", "Images similaires comparées côte à côte dans Targie"),
            ("Repérez les vidéos quasi identiques", "Vidéos similaires regroupées dans Targie"),
            ("Parcourez tous les fichiers dans un tableau triable", "Mode Browse de Targie avec tableau de fichiers triable et aperçu"),
        ],
        "install": [
            "Téléchargez le dernier zip de Targie depuis la page Releases et décompressez-le.",
            "Faites glisser Targie.app dans votre dossier Applications.",
            "L’app est signée ad hoc, macOS bloque donc le premier lancement. Faites un clic droit (ou Contrôle-clic) sur Targie, choisissez Ouvrir, puis cliquez sur Ouvrir. Vous pouvez aussi aller dans Réglages Système → Confidentialité et sécurité et cliquer sur Ouvrir quand même. Une seule fois suffit.",
        ],
        "faq": [
            ("Targie est-il gratuit ?", "Oui. Targie est gratuit et open source sous licence GPL-3.0."),
            ("Targie envoie-t-il mes fichiers ?", "Non. L’analyse et la comparaison se font entièrement sur votre Mac ; vos fichiers n’en sortent pas."),
            ("Pourquoi macOS bloque-t-il Targie la première fois ?", "Targie est signé ad hoc et n’est pas notarisé. Faites un clic droit et choisissez Ouvrir une seule fois ; macOS ne redemandera plus."),
            ("Un score élevé signifie-t-il un doublon ?", "Les scores indiquent une similarité visuelle, et non la probabilité d’un doublon exact. Vérifiez côte à côte avant de supprimer."),
            ("Existe-t-il une version Windows ou Linux ?", "Non. Targie est une app native macOS 14 ou ultérieur et aucune autre plateforme n’est prévue."),
        ],
        "changelog": "Nouveautés",
        "changelog_title": "Nouveautés de Targie — ce qui change à chaque version",
        "changelog_desc": "Notes de chaque version de Targie, l’app macOS gratuite qui trouve les photos et vidéos similaires ou en double.",
        "changelog_intro": "Les nouveautés de chaque version de Targie.",
        "all_releases": "Voir toutes les versions sur GitHub",
        "home": "Accueil",
        "footer": "Targie est un logiciel libre sous licence GNU GPL v3.0. © 2026 Lirui Yu.",
        "language": "Langue",
        "not_found": "Page introuvable",
        "not_found_back": "Retour à l’accueil",
    },
    "ja": {
        "title": "Targie — Mac で類似・重複した写真と動画を見つける",
        "desc": "Targie は、知覚ハッシュと Apple Vision を使って複数のフォルダから類似・重複した動画や画像を見つける、無料でオープンソースの macOS アプリです。並べて確認してから、不要なファイルを安全にゴミ箱へ移動できます。",
        "h1": "Mac で類似・重複した写真と動画を見つける",
        "sub": "Targie はフォルダをスキャンし、再エンコードや縮小、再圧縮されたコピーも含め、ほぼ同じ動画や画像を見つけます。並べて確認し、安心して容量を空けられます。",
        "download": "macOS 版をダウンロード",
        "github": "GitHub で見る",
        "req": "無料・オープンソース · macOS 14 以降 · Apple Silicon と Intel に対応",
        "latest": "最新バージョン",
        "nav": ["機能", "スクリーンショット", "インストール", "よくある質問", "更新履歴"],
        "sections": ["機能", "スクリーンショット", "ダウンロードとインストール", "よくある質問"],
        "features": [
            ("動画と画像を一度にスキャン", "追加した複数のフォルダを再帰的に調べ、一般的な動画形式と JPEG、PNG、HEIC、HEIF、WebP、TIFF、GIF、BMP の画像を比較します。"),
            ("完全一致だけではありません", "SHA-256、知覚フィンガープリント、メタデータ、Apple Vision の特徴を組み合わせ、再エンコード・縮小・再圧縮されたものも検出します。"),
            ("並べて確認", "類似ファイルをグループにまとめ、アプリ内プレビューで並べて比較できます。動画は既定のプレーヤーで開け、ファイルは Finder で表示できます。"),
            ("慎重に削除", "チェックボックスやドラッグで選択し、ゴミ箱に移動するか完全に削除するかを明示的に選びます。完全削除は必ずもう一度確認します。"),
            ("Browse モード", "フォルダ内のすべてのファイルを、並べ替え・絞り込みできる表で閲覧できます。解像度フィルタ、検索（⌘F）、一括選択に対応しています。"),
            ("プライベートでネイティブ", "すべて Mac 上で動作し、ファイルをアップロードすることはありません。Apple Silicon と Intel に対応したネイティブ macOS アプリで、7 言語に対応しています。"),
        ],
        "shots": [
            ("フォルダをドロップして開始", "Targie のウェルカム画面"),
            ("類似画像を並べて比較", "Targie で並べて比較された類似画像"),
            ("ほぼ重複した動画を発見", "Targie でグループ表示された類似動画"),
            ("並べ替え可能な表ですべてのファイルを閲覧", "並べ替え可能なファイル表とプレビューを備えた Targie の Browse モード"),
        ],
        "install": [
            "Releases ページから最新の Targie の zip をダウンロードして展開します。",
            "Targie.app を「アプリケーション」フォルダにドラッグします。",
            "アプリはアドホック署名のため、初回起動時に macOS がブロックします。Targie を右クリック（または Control キーを押しながらクリック）して「開く」を選び、もう一度「開く」をクリックします。または「システム設定 → プライバシーとセキュリティ」で「このまま開く」をクリックします。操作は一度だけです。",
        ],
        "faq": [
            ("Targie は無料ですか？", "はい。Targie は無料で、GPL-3.0 のオープンソースです。"),
            ("Targie はファイルをアップロードしますか？", "いいえ。スキャンと比較はすべて Mac 上で行われ、ファイルが Mac の外に出ることはありません。"),
            ("なぜ初回起動時に macOS がブロックするのですか？", "Targie はアドホック署名で、公証されていません。右クリックして「開く」を一度選べば、以後は確認されません。"),
            ("類似度が高ければ重複ファイルですか？", "スコアは見た目の類似度を示すもので、完全な重複である確率ではありません。削除前に並べて確認してください。"),
            ("Windows や Linux 版はありますか？", "ありません。Targie は macOS 14 以降向けのネイティブアプリで、他のプラットフォームの予定はありません。"),
        ],
        "changelog": "更新履歴",
        "changelog_title": "Targie 更新履歴 — 各バージョンの新機能",
        "changelog_desc": "Targie の各バージョンのリリースノート。Targie は類似・重複した写真や動画を見つける無料の macOS アプリです。",
        "changelog_intro": "Targie の各バージョンの新機能です。",
        "all_releases": "GitHub ですべてのバージョンを見る",
        "home": "ホーム",
        "footer": "Targie は GNU GPL v3.0 でライセンスされたフリーソフトウェアです。© 2026 Lirui Yu。",
        "language": "言語",
        "not_found": "ページが見つかりません",
        "not_found_back": "ホームに戻る",
    },
    "ko": {
        "title": "Targie — Mac에서 비슷하거나 중복된 사진과 동영상 찾기",
        "desc": "Targie는 지각 해시와 Apple Vision으로 여러 폴더에서 비슷하거나 중복된 동영상과 이미지를 찾아 주는 무료 오픈 소스 macOS 앱입니다. 나란히 비교한 뒤 불필요한 파일을 안전하게 휴지통으로 옮길 수 있습니다.",
        "h1": "Mac에서 비슷하거나 중복된 사진과 동영상 찾기",
        "sub": "Targie는 폴더를 스캔해 다시 인코딩하거나 크기를 줄이거나 다시 압축한 사본까지 거의 같은 동영상과 이미지를 찾아 줍니다. 나란히 비교해 보고 안심하고 저장 공간을 확보하세요.",
        "download": "macOS용 다운로드",
        "github": "GitHub에서 보기",
        "req": "무료 오픈 소스 · macOS 14 이상 · Apple Silicon 및 Intel 지원",
        "latest": "최신 버전",
        "nav": ["기능", "스크린샷", "설치", "자주 묻는 질문", "변경 내역"],
        "sections": ["기능", "스크린샷", "다운로드 및 설치", "자주 묻는 질문"],
        "features": [
            ("동영상과 이미지를 한 번에 스캔", "추가한 여러 폴더를 재귀적으로 살펴 일반적인 동영상 형식과 JPEG, PNG, HEIC, HEIF, WebP, TIFF, GIF, BMP 이미지를 비교합니다."),
            ("완전히 같은 파일만 찾지 않습니다", "SHA-256, 지각 지문, 메타데이터, Apple Vision 특징을 함께 사용해 다시 인코딩하거나 크기를 줄이거나 다시 압축한 버전도 찾아냅니다."),
            ("나란히 비교", "비슷한 파일을 그룹으로 묶어 앱 내 미리 보기와 함께 나란히 비교합니다. 동영상은 기본 플레이어로 열고, 파일은 Finder에서 표시할 수 있습니다."),
            ("신중한 삭제", "체크박스나 드래그로 선택한 뒤 휴지통으로 이동할지 영구 삭제할지 직접 선택합니다. 영구 삭제는 항상 한 번 더 확인합니다."),
            ("Browse 모드", "폴더의 모든 파일을 정렬과 필터가 가능한 표로 볼 수 있습니다. 해상도 필터, 검색(⌘F), 일괄 선택을 지원합니다."),
            ("프라이빗하고 네이티브", "모든 작업이 Mac에서만 이루어지며 파일을 업로드하지 않습니다. Apple Silicon과 Intel을 지원하는 네이티브 macOS 앱이며 7개 언어를 지원합니다."),
        ],
        "shots": [
            ("폴더를 끌어다 놓아 시작", "Targie 시작 화면"),
            ("비슷한 이미지를 나란히 비교", "Targie에서 나란히 비교한 비슷한 이미지"),
            ("거의 중복된 동영상 찾기", "Targie에서 그룹으로 표시된 비슷한 동영상"),
            ("정렬 가능한 표로 모든 파일 보기", "정렬 가능한 파일 표와 미리 보기를 갖춘 Targie Browse 모드"),
        ],
        "install": [
            "Releases 페이지에서 최신 Targie zip 파일을 내려받아 압축을 풉니다.",
            "Targie.app을 '응용 프로그램' 폴더로 드래그합니다.",
            "앱은 임시(ad hoc) 서명이므로 처음 실행할 때 macOS가 차단합니다. Targie를 마우스 오른쪽 버튼(또는 Control 키를 누른 채 클릭)으로 눌러 '열기'를 선택한 다음 다시 '열기'를 클릭하세요. 또는 '시스템 설정 → 개인정보 보호 및 보안'에서 '그래도 열기'를 클릭해도 됩니다. 한 번만 하면 됩니다.",
        ],
        "faq": [
            ("Targie는 무료인가요?", "네. Targie는 무료이며 GPL-3.0 오픈 소스입니다."),
            ("Targie가 파일을 업로드하나요?", "아니요. 스캔과 비교는 모두 Mac에서 이루어지며 파일이 Mac 밖으로 나가지 않습니다."),
            ("처음 실행할 때 macOS가 왜 차단하나요?", "Targie는 임시 서명이며 공증되지 않았습니다. 마우스 오른쪽 버튼으로 '열기'를 한 번 선택하면 이후에는 다시 묻지 않습니다."),
            ("유사도가 높으면 반드시 중복 파일인가요?", "점수는 시각적 유사도를 나타내며 완전한 중복일 확률이 아닙니다. 삭제하기 전에 나란히 비교해 확인하세요."),
            ("Windows나 Linux 버전이 있나요?", "없습니다. Targie는 macOS 14 이상용 네이티브 앱이며 다른 플랫폼 계획은 없습니다."),
        ],
        "changelog": "변경 내역",
        "changelog_title": "Targie 변경 내역 — 버전별 새로운 기능",
        "changelog_desc": "Targie 각 버전의 릴리스 노트입니다. Targie는 비슷하거나 중복된 사진과 동영상을 찾는 무료 macOS 앱입니다.",
        "changelog_intro": "Targie 각 버전의 새로운 기능입니다.",
        "all_releases": "GitHub에서 모든 버전 보기",
        "home": "홈",
        "footer": "Targie는 GNU GPL v3.0으로 배포되는 자유 소프트웨어입니다. © 2026 Lirui Yu.",
        "language": "언어",
        "not_found": "페이지를 찾을 수 없습니다",
        "not_found_back": "홈으로 돌아가기",
    },
}

SCREENSHOTS = ["opening", "screenshot1", "screenshot2", "screenshot3"]


# --------------------------------------------------------------------------
# Release notes


@dataclass
class Release:
    version: str                      # "5.2.0"
    title: str                        # "Targie 5.2"
    date: str | None                  # "2026-10-12"
    sections: dict[str, str]          # md heading -> markdown body

    @property
    def key(self) -> tuple[int, ...]:
        return tuple(int(p) for p in re.findall(r"\d+", self.version))


def tag_date(version: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%cs", f"refs/tags/v{version}"],
            cwd=ROOT, capture_output=True, text=True, check=True,
        ).stdout.strip()
        return out or None
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def load_releases() -> list[Release]:
    releases: list[Release] = []
    for path in sorted((ROOT / "releases").glob("v*.md")):
        match = re.fullmatch(r"v(\d+\.\d+\.\d+)\.md", path.name)
        if not match:
            continue
        text = path.read_text(encoding="utf-8")
        title_match = re.search(r"^#\s+(.+)$", text, re.M)
        parts = re.split(r"^##\s+(.+)$", text, flags=re.M)
        sections = {parts[i].strip(): parts[i + 1].strip() for i in range(1, len(parts) - 1, 2)}
        releases.append(Release(
            version=match.group(1),
            title=title_match.group(1).strip() if title_match else f"Targie {match.group(1)}",
            date=tag_date(match.group(1)),
            sections=sections,
        ))
    return sorted(releases, key=lambda r: r.key, reverse=True)


def inline_md(text: str) -> str:
    """Escapes text, then turns `code`, **bold** and [links](url) into HTML."""
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(
        r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
        lambda m: f'<a href="{html.escape(m.group(2), quote=True)}">{m.group(1)}</a>',
        out,
    )
    return out


def render_md(body: str) -> str:
    """Renders the small markdown subset used by release notes."""
    parts: list[str] = []
    bullets: list[str] = []
    paragraph: list[str] = []

    def flush_paragraph() -> None:
        if paragraph:
            parts.append(f"<p>{inline_md(' '.join(paragraph))}</p>")
            paragraph.clear()

    def flush_bullets() -> None:
        if bullets:
            parts.append("<ul>" + "".join(f"<li>{inline_md(b)}</li>" for b in bullets) + "</ul>")
            bullets.clear()

    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            flush_paragraph()
            flush_bullets()
        elif line.startswith("- "):
            flush_paragraph()
            bullets.append(line[2:].strip())
        else:
            flush_bullets()
            paragraph.append(line)
    flush_paragraph()
    flush_bullets()
    return "\n".join(parts)


# --------------------------------------------------------------------------
# Pages


def esc(text: str) -> str:
    return html.escape(text, quote=True)


class Site:
    def __init__(self, base_url: str, out: Path, releases: list[Release]):
        self.base_url = base_url if base_url.endswith("/") else base_url + "/"
        self.out = out
        self.releases = releases
        self.latest = releases[0] if releases else None

    # -- urls ----------------------------------------------------------------
    def page_path(self, lang: Lang, page: str) -> str:
        """Site-relative path of a page, e.g. 'zh/changelog/'."""
        parts = [p for p in (lang.folder, "changelog" if page == "changelog" else "") if p]
        return "/".join(parts) + ("/" if parts else "")

    def abs_url(self, lang: Lang, page: str) -> str:
        return self.base_url + self.page_path(lang, page)

    @staticmethod
    def depth(path: str) -> int:
        return len([p for p in path.split("/") if p])

    def rel(self, from_path: str, to_path: str) -> str:
        """Relative link between two site paths (directories end with '/')."""
        prefix = "../" * self.depth(from_path)
        return (prefix + to_path) or "./"

    @property
    def download_url(self) -> str:
        if not self.latest:
            return f"{GITHUB_URL}/releases/latest"
        v = self.latest.version
        return f"{GITHUB_URL}/releases/download/v{v}/Targie-v{v}-macos-universal.zip"

    # -- shared chrome -------------------------------------------------------
    def head(self, lang: Lang, page: str, title: str, desc: str, extra_ld: list[dict]) -> str:
        path = self.page_path(lang, page)
        root = "../" * self.depth(path)
        canonical = self.abs_url(lang, page)
        alternates = "".join(
            f'<link rel="alternate" hreflang="{l.html_lang}" href="{self.abs_url(l, page)}">\n'
            for l in LANGS
        )
        alternates += f'<link rel="alternate" hreflang="x-default" href="{self.abs_url(LANGS[0], page)}">\n'
        og_alt = "".join(
            f'<meta property="og:locale:alternate" content="{l.og_locale}">\n'
            for l in LANGS if l.code != lang.code
        )
        image = self.base_url + "img/og.jpg"
        ld = "".join(
            f'<script type="application/ld+json">{json.dumps(d, ensure_ascii=False, separators=(",", ":"))}</script>\n'
            for d in extra_ld
        )
        return f"""<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<link rel="canonical" href="{canonical}">
{alternates}<meta name="theme-color" content="#fbf7f0" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#171310" media="(prefers-color-scheme: dark)">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Targie">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:url" content="{canonical}">
<meta property="og:image" content="{image}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:locale" content="{lang.og_locale}">
{og_alt}<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{esc(title)}">
<meta name="twitter:description" content="{esc(desc)}">
<meta name="twitter:image" content="{image}">
<link rel="icon" type="image/png" href="{root}favicon.png">
<link rel="apple-touch-icon" href="{root}apple-touch-icon.png">
<link rel="stylesheet" href="{root}style.css">
{ld}</head>"""

    def header(self, lang: Lang, page: str) -> str:
        s = STR[lang.code]
        path = self.page_path(lang, page)
        home = self.rel(path, self.page_path(lang, "home"))
        changelog = self.rel(path, self.page_path(lang, "changelog"))
        anchors = ["features", "screenshots", "install", "faq"]
        links = "".join(
            f'<a href="{home}#{a}">{esc(label)}</a>'
            for a, label in zip(anchors, s["nav"][:4])
        )
        current_page = ' aria-current="page"' if page == "changelog" else ""
        links += f'<a href="{changelog}"{current_page}>{esc(s["nav"][4])}</a>'
        menu = ""
        for l in LANGS:
            current = ' aria-current="true"' if l.code == lang.code else ""
            href = self.rel(path, self.page_path(l, page))
            menu += (
                f'<li><a href="{href}" hreflang="{l.html_lang}" lang="{l.html_lang}"{current}>'
                f"{esc(l.name)}</a></li>"
            )
        root = "../" * self.depth(path)
        return f"""<header class="site-header">
<div class="wrap bar">
<a class="brand" href="{home}"><img src="{root}img/icon.png" alt="" width="32" height="32"><span>Targie</span></a>
<nav class="nav" aria-label="Main">{links}</nav>
<div class="bar-end">
<a class="gh" href="{GITHUB_URL}" rel="noopener">GitHub</a>
<details class="lang">
<summary aria-label="{esc(s['language'])}"><span aria-hidden="true">🌐</span> {esc(lang.name)}</summary>
<ul>{menu}</ul>
</details>
</div>
</div>
</header>"""

    def footer(self, lang: Lang) -> str:
        s = STR[lang.code]
        return f"""<footer class="site-footer">
<div class="wrap">
<p>{esc(s['footer'])}</p>
<p class="links"><a href="{GITHUB_URL}">GitHub</a> · <a href="{GITHUB_URL}/releases">Releases</a> · <a href="{GITHUB_URL}/issues">Issues</a> · <a href="{GITHUB_URL}/blob/main/LICENSE">GPL-3.0</a></p>
</div>
</footer>"""

    # -- pages ---------------------------------------------------------------
    def home(self, lang: Lang) -> str:
        s = STR[lang.code]
        path = self.page_path(lang, "home")
        root = "../" * self.depth(path)
        changelog = self.rel(path, self.page_path(lang, "changelog"))
        version = self.latest.version if self.latest else ""

        features = "".join(
            f'<li class="card"><h3>{esc(t)}</h3><p>{esc(d)}</p></li>' for t, d in s["features"]
        )
        shots = "".join(
            f'<figure><img src="{root}img/{name}.webp" alt="{esc(alt)}" width="1600" height="{1089 if name == "opening" else 1040}" loading="lazy" decoding="async">'
            f"<figcaption>{esc(cap)}</figcaption></figure>"
            for name, (cap, alt) in zip(SCREENSHOTS, s["shots"])
        )
        steps = "".join(f"<li>{esc(t)}</li>" for t in s["install"])
        faqs = "".join(
            f"<details><summary>{esc(q)}</summary><p>{esc(a)}</p></details>" for q, a in s["faq"]
        )

        software = {
            "@context": "https://schema.org",
            "@type": "SoftwareApplication",
            "name": "Targie",
            "description": s["desc"],
            "applicationCategory": "UtilitiesApplication",
            "operatingSystem": "macOS 14 or later",
            "softwareVersion": version,
            "downloadUrl": self.download_url,
            "installUrl": f"{GITHUB_URL}/releases/latest",
            "license": "https://www.gnu.org/licenses/gpl-3.0.html",
            "image": self.base_url + "img/og.jpg",
            "screenshot": [f"{self.base_url}img/{n}.webp" for n in SCREENSHOTS],
            "inLanguage": [l.html_lang for l in LANGS],
            "isAccessibleForFree": True,
            "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
            "author": {"@type": "Person", "name": "Lirui Yu"},
            "url": self.abs_url(lang, "home"),
        }
        faq_ld = {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "mainEntity": [
                {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}}
                for q, a in s["faq"]
            ],
        }

        version_badge = f' <span class="ver">v{esc(version)}</span>' if version else ""
        latest_line = (
            f'<p class="latest">{esc(s["latest"])}: <a href="{changelog}">v{esc(version)}</a></p>'
            if version else ""
        )
        return f"""<!doctype html>
<html lang="{lang.html_lang}">
{self.head(lang, "home", s["title"], s["desc"], [software, faq_ld])}
<body>
{self.header(lang, "home")}
<main>
<section class="hero">
<div class="wrap">
<img class="hero-icon" src="{root}img/icon.png" alt="Targie" width="96" height="96">
<h1>{esc(s['h1'])}</h1>
<p class="lead">{esc(s['sub'])}</p>
<p class="cta">
<a class="btn primary" href="{esc(self.download_url)}">{esc(s['download'])}{version_badge}</a>
<a class="btn" href="{GITHUB_URL}" rel="noopener">{esc(s['github'])}</a>
</p>
<p class="req">{esc(s['req'])}</p>
{latest_line}
<img class="hero-shot" src="{root}img/screenshot1.webp" alt="{esc(s['shots'][1][1])}" width="1600" height="1040" fetchpriority="high">
</div>
</section>

<section id="features" class="section">
<div class="wrap">
<h2>{esc(s['sections'][0])}</h2>
<ul class="grid">{features}</ul>
</div>
</section>

<section id="screenshots" class="section alt">
<div class="wrap">
<h2>{esc(s['sections'][1])}</h2>
<div class="shots">{shots}</div>
</div>
</section>

<section id="install" class="section">
<div class="wrap narrow">
<h2>{esc(s['sections'][2])}</h2>
<ol class="steps">{steps}</ol>
<p class="cta">
<a class="btn primary" href="{esc(self.download_url)}">{esc(s['download'])}</a>
<a class="btn" href="{GITHUB_URL}/releases">{esc(s['all_releases'])}</a>
</p>
</div>
</section>

<section id="faq" class="section alt">
<div class="wrap narrow">
<h2>{esc(s['sections'][3])}</h2>
<div class="faq">{faqs}</div>
</div>
</section>
</main>
{self.footer(lang)}
</body>
</html>
"""

    def changelog(self, lang: Lang) -> str:
        s = STR[lang.code]
        path = self.page_path(lang, "changelog")
        home = self.rel(path, self.page_path(lang, "home"))
        entries = []
        for rel in self.releases:
            body = rel.sections.get(lang.md_heading) or rel.sections.get("English", "")
            date = f' · <time datetime="{rel.date}">{rel.date}</time>' if rel.date else ""
            entries.append(
                f'<article class="release" id="v{esc(rel.version)}">'
                f"<header><h2>{esc(rel.title)}</h2>"
                f'<p class="meta"><a href="{GITHUB_URL}/releases/tag/v{esc(rel.version)}">v{esc(rel.version)}</a>'
                f"{date}</p></header>"
                f"{render_md(body)}</article>"
            )
        return f"""<!doctype html>
<html lang="{lang.html_lang}">
{self.head(lang, "changelog", s["changelog_title"], s["changelog_desc"], [])}
<body>
{self.header(lang, "changelog")}
<main>
<section class="section">
<div class="wrap narrow">
<nav class="crumbs" aria-label="Breadcrumb"><a href="{home}">{esc(s['home'])}</a> / <span>{esc(s['changelog'])}</span></nav>
<h1>{esc(s['changelog'])}</h1>
<p class="lead">{esc(s['changelog_intro'])}</p>
{''.join(entries)}
<p class="cta"><a class="btn" href="{GITHUB_URL}/releases">{esc(s['all_releases'])}</a></p>
</div>
</section>
</main>
{self.footer(lang)}
</body>
</html>
"""

    def not_found(self) -> str:
        s = STR["en"]
        home = self.base_url
        return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>{esc(s['not_found'])} — Targie</title>
<link rel="icon" type="image/png" href="{self.base_url}favicon.png">
<link rel="stylesheet" href="{self.base_url}style.css">
</head>
<body>
<main class="section"><div class="wrap narrow notfound">
<img src="{self.base_url}img/icon.png" alt="" width="72" height="72">
<h1>{esc(s['not_found'])}</h1>
<p><a class="btn primary" href="{home}">{esc(s['not_found_back'])}</a></p>
</div></main>
</body>
</html>
"""

    def sitemap(self) -> str:
        urls = []
        for page in ("home", "changelog"):
            for lang in LANGS:
                alts = "".join(
                    f'<xhtml:link rel="alternate" hreflang="{l.html_lang}" href="{self.abs_url(l, page)}"/>'
                    for l in LANGS
                )
                alts += f'<xhtml:link rel="alternate" hreflang="x-default" href="{self.abs_url(LANGS[0], page)}"/>'
                lastmod = f"<lastmod>{self.latest.date}</lastmod>" if self.latest and self.latest.date else ""
                urls.append(f"<url><loc>{self.abs_url(lang, page)}</loc>{lastmod}{alts}</url>")
        return (
            '<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
            'xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' + "\n".join(urls) + "\n</urlset>\n"
        )

    # -- build ---------------------------------------------------------------
    def write(self, rel_path: str, content: str) -> None:
        target = self.out / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def build(self) -> None:
        if self.out.exists():
            shutil.rmtree(self.out)
        shutil.copytree(ROOT / "site" / "static", self.out)
        for lang in LANGS:
            self.write(self.page_path(lang, "home") + "index.html", self.home(lang))
            self.write(self.page_path(lang, "changelog") + "index.html", self.changelog(lang))
        self.write("404.html", self.not_found())
        self.write("sitemap.xml", self.sitemap())
        self.write("robots.txt", f"User-agent: *\nAllow: /\n\nSitemap: {self.base_url}sitemap.xml\n")
        self.write(".nojekyll", "")


def check_links(out: Path) -> list[str]:
    """Returns broken relative links/assets found in the generated pages."""
    problems: list[str] = []
    for page in out.rglob("*.html"):
        if page.name == "404.html":
            continue
        text = page.read_text(encoding="utf-8")
        for attr in re.findall(r'(?:href|src)="([^"]+)"', text):
            if re.match(r"(https?:|mailto:|#|data:)", attr):
                continue
            target = attr.split("#")[0]
            if not target:
                continue
            resolved = (page.parent / target).resolve()
            if resolved.is_dir():
                resolved = resolved / "index.html"
            if not resolved.exists():
                problems.append(f"{page.relative_to(out)}: {attr}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="_site", help="output directory (default: _site)")
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL, help="public URL the site is served from")
    args = parser.parse_args()

    releases = load_releases()
    if not releases:
        print("error: no releases/v*.md files found", file=sys.stderr)
        return 1
    missing = [
        f"{r.version}: {l.md_heading}"
        for r in releases for l in LANGS if l.md_heading not in r.sections
    ]
    if missing:
        print("warning: release notes missing a language (falling back to English):", ", ".join(missing), file=sys.stderr)

    site = Site(args.base_url, (ROOT / args.out).resolve(), releases)
    site.build()
    problems = check_links(site.out)
    if problems:
        print("error: broken links:", *problems, sep="\n  ", file=sys.stderr)
        return 1
    pages = len(LANGS) * 2
    print(f"Built {pages} pages for {len(releases)} releases into {site.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
