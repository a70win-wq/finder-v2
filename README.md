# Finder v2.0

<p align="center">
  <img src="Resources/AppIcon-1024.png" width="160" alt="Finder v2.0 icon">
</p>

<p align="center">
  <strong>🌐 Language:</strong> <a href="#en">English</a> · <a href="#zh">中文（粵語）</a>
</p>

---

<a name="en"></a>
## English

A free, open-source, native macOS multi-pane file manager. Open two, three, or four folders at once in a single window and drag-and-drop files directly between them.

> Finder v2.0 is an independent, open-source project. It is not a replacement for Apple Finder and is not affiliated with Apple Inc.

### Download & Install

1. Download the latest `Finder-v2.0-macOS.dmg` from the [Releases](../../releases/latest) page.
2. Open the DMG.
3. Drag **Finder v2.0** into your `Applications` folder.
4. On first launch, right-click the app and choose **Open** if macOS shows a security warning.

Requires macOS 14 Sonoma or later. Supports both Apple Silicon and Intel Macs.

> Since this free version is not notarized with an Apple Developer ID, macOS may show a security prompt the first time you open it.

### Features

- **Multi-pane layouts** — side-by-side, top-and-bottom, three-pane, and four-pane arrangements.
- **Independent panes** — each pane can open local folders, iCloud, Google Drive, or external drives on its own.
- **Drag-and-drop** — drag to move files by default; hold `Option` while dragging to copy.
- **Multiple view modes** — list, icons, column view, and gallery, with thumbnails and live updates.
- **Full file operations** — create folders, rename, move to Trash, ZIP compress and extract.
- **Safe name conflicts** — choose Cancel, Replace, or Keep Both when names clash.
- **Undo** — `Command-Z` undoes moves, renames, and folder creation.
- **Search & organize** — search, sort, favorites, show hidden files, and compare or sync the left and right panes.
- **Remembers your setup** — restores your last layout and the folder of every pane.

### Keyboard Shortcuts

- `Command-Shift-N` — New Folder
- `Command-Delete` — Move to Trash
- `Command-Z` — Undo
- `Space` — Quick Look

The first time you use **Downloads**, **Documents**, iCloud, or Google Drive, click the folder button in the toolbar and choose **Use This Folder**. macOS asks once and remembers it from then on.

### Building from Source

Requires macOS 14 or later and Xcode Command Line Tools.

Build the app:

```sh
./scripts/build-app.sh
```

Build a DMG:

```sh
./scripts/make-dmg.sh
```

Run the tests:

```sh
swift test
```

### Privacy

Finder v2.0 has no accounts, no analytics tracking, and no network server. It never uploads or collects any of your files.

### License

[MIT License](LICENSE)

---

<a name="zh"></a>
## 中文（粵語）

一個免費、開源、原生 macOS 多視窗檔案管理 App。可以在同一個畫面開兩個、三個或四個資料夾，直接拖放檔案。

> Finder v2.0 是獨立開源專案，不會取代 Apple Finder，亦與 Apple Inc. 無關。

### 下載及安裝

1. 到 [Releases](../../releases/latest) 下載最新的 `Finder-v2.0-macOS.dmg`。
2. 打開 DMG。
3. 將 `Finder v2.0` 拖入 `Applications`。
4. 第一次打開時，請右擊 App，再按「開啟」。

需要 macOS 14 Sonoma 或更新版本。支援 Apple Silicon 及 Intel Mac。

由於這個免費版本未使用 Apple Developer ID 公證，第一次打開時 macOS 可能會顯示安全提示。

### 主要功能

- 左右雙開、上下雙開、三開及四開版面。
- 每一格可獨立開啟本機、iCloud、Google Drive 或外置硬碟。
- 正常拖放會搬移；按住 `Option` 拖放會複製。
- 多選、即時更新、縮圖、清單、大圖示、直欄及圖庫顯示。
- 新增資料夾、改名、搬去垃圾桶、ZIP 壓縮及解壓。
- 撞名時可取消、取代或保留兩個。
- `Command-Z` 還原搬檔、改名及新增資料夾。
- 搜尋、排序、收藏、顯示隱藏檔案、左右比較及同步。
- 記住上次版面及每一格的位置。

### 常用快捷鍵

- `Command-Shift-N`：新增資料夾
- `Command-Delete`：搬去垃圾桶
- `Command-Z`：還原
- `Space`：快速預覽

第一次使用「下載」、「文件」、iCloud 或 Google Drive 時，按工具列的資料夾按鈕，再按「使用這個資料夾」。macOS 確認一次後會自動記住。

### 自行建立

需要 macOS 14 或更新版本，以及 Xcode Command Line Tools。

```sh
./scripts/build-app.sh
```

建立 DMG：

```sh
./scripts/make-dmg.sh
```

執行測試：

```sh
swift test
```

### 私隱

Finder v2.0 沒有帳戶、分析追蹤或網絡伺服器，不會上載或收集任何檔案。

### 授權

[MIT License](LICENSE)
