# Finder v2.0 1.1.12

## English

### Performance Optimizations

This release makes Finder v2.0 feel faster and smoother, especially when working with large folders.

- **Smarter sidebar caching.** The sidebar (main folders, favorites, cloud storage, external drives) is now cached. Previously it rescanned mounted volumes, cloud locations, and favorites on *every* folder reload; now it only rescans when something actually changes — you add a favorite, hide a cloud location, or plug in / eject a drive. Switching between folders no longer triggers repeated full sidebar scans.
- **Faster sorting of large folders.** Each file's display name is now computed once when a folder is loaded, instead of being looked up from the filesystem over and over during sorting. Folders with thousands of files sort noticeably faster.
- **Better thumbnail handling.** Icon-size and gallery-size thumbnails are now cached separately by their dimensions, so the gallery no longer picks up a small icon thumbnail and stretches it into a blurry preview. The cache is also capped (in both count and memory), so it can't grow without bound.
- **Less flicker and redrawing.** When a folder is reloaded but its contents are unchanged (for example, a minor filesystem attribute event), the view is no longer rebuilt from scratch. The list, icons, gallery, and column view keep their scroll position and selection, with no unnecessary redraws.
- **One less sort pass.** The default name ordering now reuses the sort already performed while loading, skipping a duplicate pass over the whole list.

Quality:

- All **52 tests pass**, including 4 new tests added specifically to guard each optimization above.
- Supports **Apple Silicon and Intel Macs**.

Requires macOS 14 Sonoma or later.

## 中文（粵語）

### 整體效能優化

呢個版本令 Finder v2.0 行得更快更順，尤其係開大型資料夾嘅時候。

- **側邊欄加入快取。** 以前每次切換資料夾，側邊欄（主目錄、收藏、雲端、外置硬碟）都會由頭重新掃描一次掛載嘅硬碟、雲端位置同收藏；而家只會喺真係有嘢變嗰陣先重掃——例如你加咗收藏、隱藏咗雲端位置、或者插咗／拔走咗硬碟。切換資料夾唔會再重複掃描。
- **大型資料夾排序更快。** 每個檔案嘅顯示名稱而家喺載入資料夾嗰陣一次過計好，唔會喺排序期間重複向檔案系統查詢。成千上萬個檔案嘅資料夾排序明顯快咗。
- **縮圖處理更好。** 大圖示尺寸同圖庫尺寸嘅縮圖而家按尺寸分開快取，圖庫唔會再攞到細縮圖嚟放大到矇查查。快取亦設咗上限（數量同記憶體），唔會無限制咁增長。
- **減少閃爍同重畫。** 當資料夾重新載入但內容冇變（例如系統輕微掂咗檔案屬性），而家唔會由頭重建成個畫面。清單、大圖示、圖庫同直欄都會保留捲動位置同選取，唔會無謂咁重畫。
- **少排一次序。** 預設嘅名稱排序而家重用載入時已經做咗嘅排序，唔會對成個列表再排多一次。

品質：

- 全部 **52 個測試通過**，包括 4 個新加入、專登保護以上每項優化嘅測試。
- 支援 **Apple Silicon 及 Intel Mac**。

需要 macOS 14 Sonoma 或更新版本。

# Finder v2.0 1.1.11

修正左右側邊欄顏色：

- 側邊欄由灰色還原成清爽內容背景，同文件區保持一致。
- 側邊欄列表還原成普通清晰款式，保留選取、右鍵及拖放功能。
- 加入測試，避免之後更新時再次變灰。

# Finder v2.0 1.1.10

修正路徑列點擊範圍：

- 左右兩邊撳路徑列任何位置，包括 folder 名同空白位，都會顯示完整 path。
- 撳空白位會顯示目前 folder；撳指定 folder 會顯示嗰一層 folder。
- 完整 path 會自動全選，可以直接按 Command-C 複製。

# Finder v2.0 1.1.9

修正左右兩邊路徑列：

- 左右任何一格嘅目前 folder 或上一層 folder，撳一下都會顯示該層完整 path。
- 顯示後可以直接按 Command-C 複製；按 Return 先開啟該 folder。
- 上一層 folder 唔會再一撳就跳走，左右兩邊操作完全一致。

# Finder v2.0 1.1.8

整體 UI 整理：

- 工具列按鈕統一成較輕、較整齊嘅 macOS 風格，重新整理掣仍然清楚見到。
- 左邊常用位置、列表及圖庫背景統一，唔再有一格一種顏色。
- 比較結果喺藍色選取列上保持清楚對比，檔名唔會再睇唔清。
- 保留原有四種顯示方式、右鍵選單、拖放及路徑複製功能。

# Finder v2.0 1.1.7

改善直欄模式更新及重新整理：

- 拖檔完成後，已經打開嘅直欄會即時重新讀取，唔使再撳上面再撳下面。
- 工具列加入清楚顯示文字嘅「重新整理」掣。
- 保留原有拖放、排序及四種顯示方式。
# Finder v2.0 1.1.6

改善直欄模式文字顯示：

- 直欄選取列嘅文字改為垂直置中。
- 保留原生藍色選取效果，但唔再出現文字貼頂嘅感覺。
- 直欄檔名會用單行顯示，太長會自動截短。

+# Finder v2.0 1.1.5

修正直欄模式拖放：

- 右邊切換到「直欄」後，可以由另一格拖檔案入去。
- 拖到資料夾會放入該資料夾；拖到空白位置會放入該欄目前資料夾。
- 保留原有清單、大圖示及圖庫模式嘅拖放功能。

# Finder v2.0 1.1.4

改善路徑列操作：

- 撳目前所在嘅 breadcrumb 會轉成完整路徑欄。
- 完整路徑會自動揀中，可以直接按 Command-C 複製。
- 按 Return 會開啟輸入嘅資料夾，按 Escape 返回 breadcrumb。
- 上層路徑仍然可以照常撳入去。
# Finder v2.0 1.1.3

改善 Google Drive 側邊欄管理：

- 自動分辨現行 File Provider 連結同疑似舊資料夾，舊資料夾會標示「舊資料夾／未連結」。
- Google Drive 右鍵新增「開啟 Google Drive 管理…」及「從側邊欄中移除」。
- 從側邊欄移除只會改 Finder v2.0 顯示設定，唔會刪除雲端資料。
- 側邊欄空白位置可以顯示返已隱藏嘅雲端位置。
- 新增 Google Drive 右鍵及可還原隱藏設定測試。

# Finder v2.0 1.1.2

改善右鍵操作及路徑列操作：

- 側邊欄嘅主目錄、雲端位置、收藏及外置硬碟，右鍵會顯示開啟、拷貝、複製路徑、在 Apple Finder 顯示及取得資料等選項。
- 右鍵側邊欄項目會先揀中該項目，但唔會偷偷打開資料夾。
- 上面路徑列每一格都可以右鍵，拷貝嗰一格資料夾，或者只複製嗰一格嘅完整路徑。
- 保留原有檔案列表右鍵、四種顯示方式、雲端下載及收藏功能。
- 新增右鍵選單及路徑列測試。

# Finder v2.0 1.1.1

修正搬移整個資料夾時，舊位置有機會再次出現同名資料夾：

- 搬移操作會配合 macOS、Google Drive、iCloud 及其他檔案服務。
- 搬完會確認新位置完整存在，而且舊位置已經消失。
- 如果檔案服務只留下空資料夾，App 會自動清走空殼。
- 如果另一個程式仍然使用舊資料夾並重新建立隱藏檔，App 會保留檔案及清楚提醒，絕不亂刪。
- 加入整個資料夾、巢狀檔案、隱藏檔及來源空殼測試。

原有排序、外置硬碟即時更新、平均分格及完整右鍵選單功能全部保留。

- 支援 Apple Silicon 及 Intel Mac。

需要 macOS 14 Sonoma 或更新版本。
