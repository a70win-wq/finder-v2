import Foundation

/// App 語言設定。
///
/// 介面文字嘅 key 就係粵語原文。揀咗其他語言先查翻譯表；冇翻譯就顯示原文。
enum Localization {
    static let supportedLanguages = ["zh-Hant", "en"]
    static let defaultLanguage = "zh-Hant"
    static let languagePreferenceKey = "FinderV2PreferredLanguage"

    static var preferredLanguage: String {
        get {
            if let saved = UserDefaults.standard.string(forKey: languagePreferenceKey),
               supportedLanguages.contains(saved) {
                return saved
            }
            return systemLanguage
        }
        set {
            if supportedLanguages.contains(newValue) {
                UserDefaults.standard.set(newValue, forKey: languagePreferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languagePreferenceKey)
            }
            applyCurrentLanguage()
        }
    }

    static var followsSystemLanguage: Bool {
        UserDefaults.standard.string(forKey: languagePreferenceKey) == nil
    }

    static var systemLanguage: String {
        let preferred = Locale.preferredLanguages.first ?? defaultLanguage
        if preferred.hasPrefix("zh") { return "zh-Hant" }
        if preferred.hasPrefix("en") { return "en" }
        return defaultLanguage
    }

    static var locale: Locale {
        switch preferredLanguage {
        case "en":
            return Locale(identifier: "en_US")
        default:
            return Locale(identifier: "zh_Hant_HK")
        }
    }

    static func nativeName(for language: String) -> String {
        switch language {
        case "zh-Hant": return "粵語"
        case "en": return "English"
        default: return language
        }
    }

    static func followSystemLanguage() {
        UserDefaults.standard.removeObject(forKey: languagePreferenceKey)
        applyCurrentLanguage()
    }

    static func applyCurrentLanguage() {
        FileFormatting.applyCurrentLocale()
        SidebarLocationProvider.invalidateCachedLocations()
        NotificationCenter.default.post(name: .finderV2LanguageChanged, object: nil)
    }

    static func tr(_ key: String) -> String {
        switch preferredLanguage {
        case "en":
            return enTranslations[key] ?? key
        default:
            return key
        }
    }

    static let enTranslations: [String: String] = [
        " 的替身": " alias",
        "%@ %ld 個項目": "%@ %ld Items",
        "%@/秒": "%@/s",
        "%ld 個項目": "%ld items",
        "1 → 2": "1 → 2",
        "2 → 1": "2 → 1",
        "\n另外有 %ld 個項目未能完成。": "\n%ld more items could not be completed.",
        "iCloud 雲碟": "iCloud Drive",
        "「%@」仲用緊呢個資料夾。請先關閉佢，再搬一次。": "“%@” is still using this folder. Close it, then try again.",
        "「%@」已經存在，你想點做？": "“%@” already exists. What do you want to do?",
        "三開：上一下二": "3 Panes: 1 Top, 2 Bottom",
        "三開：上二下一": "3 Panes: 2 Top, 1 Bottom",
        "三開：左一右二": "3 Panes: 1 Left, 2 Right",
        "三開：左二右一": "3 Panes: 2 Left, 1 Right",
        "上一層": "Enclosing Folder",
        "上下雙開": "Top and Bottom",
        "下載中": "Downloading",
        "下載唔到": "Couldn’t Download",
        "下載項目": "Downloads",
        "丟到垃圾桶": "Move to Trash",
        "主目錄": "Home",
        "之後全部用呢個選擇": "Apply to All",
        "使用呢個資料夾": "Use This Folder",
        "保留兩個": "Keep Both",
        "修改日期": "Date Modified",
        "做唔到呢個操作": "Couldn’t Complete This Action",
        "儲存": "Save",
        "儲存空間唔夠，請先清理磁碟。": "There isn’t enough free space. Free up some disk space and try again.",
        "全選": "Select All",
        "兩邊一樣": "Identical on both sides",
        "兩邊係同一個資料夾": "Both Sides Are the Same Folder",
        "兩邊版本唔同": "Different versions",
        "其他…": "Other…",
        "冇合適應用程式": "No Compatible Applications",
        "冇檔案可以貼上": "Nothing to Paste",
        "冇檔案需要同步。": "Nothing needs to be synced.",
        "分享…": "Share…",
        "分組，例如：工作": "Group, e.g. Work",
        "前進": "Forward",
        "加入收藏": "Add to Favorites",
        "包含項目的新資料夾": "Folder with Items",
        "原本位置而家已有同名檔案，所以未能還原。": "A file with the same name is already in the original location, so this couldn’t be undone.",
        "取代": "Replace",
        "取代成（只限搵字及取代）": "Replace with (Find and Replace only)",
        "取得資料": "Get Info",
        "取消": "Cancel",
        "取消工作": "Cancel Job",
        "取消收藏": "Remove from Favorites",
        "只在呢邊": "Only on this side",
        "可以改顯示名稱及分組：": "You can change the display name and group:",
        "可能仲有檔案用緊。請關閉相關檔案，再試一次。": "A file may still be in use. Close it, then try again.",
        "同步 %@？": "Sync %@?",
        "同步右邊到左邊": "Sync Right to Left",
        "同步完成；可以再按「比較左右」查看最新結果": "Sync finished. Compare again to see the latest result.",
        "同步左邊到右邊": "Sync Left to Right",
        "同步第 1 格到第 2 格": "Sync pane 1 to pane 2",
        "同步第 2 格到第 1 格": "Sync pane 2 to pane 1",
        "名稱": "Name",
        "名稱前面加字": "Add Text Before Name",
        "名稱唔可以係空白，亦唔可以有「/」。": "The name can’t be empty or contain “/”.",
        "名稱唔可以用": "That Name Can’t Be Used",
        "名稱後面加字": "Add Text After Name",
        "向上移": "Move Up",
        "向下移": "Move Down",
        "呢個位置冇權限。你可以喺 Mac 設定俾 Finder v2.0 存取檔案。": "Finder v2.0 doesn’t have permission for this location. Allow access in System Settings.",
        "呢個資料夾可能已經搬走或刪除。": "This folder may have been moved or deleted.",
        "唔可以搬入去": "Can’t Move Here",
        "唔關住": "Don’t Close",
        "唔需要同步。": "There’s nothing to sync.",
        "四開：上下四列": "4 Panes: Rows",
        "四開：四格": "4 Panes: Grid",
        "四開：左右四欄": "4 Panes: Columns",
        "圖庫": "Gallery",
        "在 Apple Finder 顯示": "Reveal in Apple Finder",
        "壓縮 %ld 個項目": "Compress %ld Items",
        "壓縮": "Compress",
        "壓縮唔到": "Couldn’t Compress",
        "壓縮工具發生錯誤。": "The compression tool reported an error.",
        "壓縮成 ZIP": "Compress as ZIP",
        "壓縮檔": "Archive",
        "大圖示": "Icons",
        "大小": "Size",
        "套用": "Apply",
        "完整路徑": "Full Path",
        "工作": "Job",
        "工作清單": "Jobs",
        "工具": "Tools",
        "左右雙開": "Side by Side",
        "已下載": "Downloaded",
        "已有同名項目": "An Item Already Has That Name",
        "已經一樣": "Already the Same",
        "已經在本機": "Already on This Mac",
        "已經有同名檔案": "A File Already Has That Name",
        "常用位置": "Favorites",
        "從側邊欄中移除": "Remove from Sidebar",
        "快速查看 %ld 個項目": "Quick Look %ld Items",
        "快速查看": "Quick Look",
        "所選檔案唔需要另外下載。": "The selected files don’t need to be downloaded.",
        "打開檔案的應用程式": "Open With",
        "批量改名": "Rename Multiple Items",
        "批量改名…": "Rename Multiple Items…",
        "拷貝 %ld 個項目": "Copy %ld Items",
        "拷貝": "Copy",
        "拷貝「%@」": "Copy “%@”",
        "按 Command-C 複製完整路徑；Return 開啟；Escape 返回": "Press Command-C to copy the full path. Return opens it. Escape cancels.",
        "排列方式": "Sort By",
        "揀兩個或以上檔案，先可以批量改名。": "Select two or more items to rename them together.",
        "揀方法，再輸入文字：": "Choose a method, then enter text:",
        "搜尋呢邊": "Search this pane",
        "搬去垃圾桶": "Move to Trash",
        "搬檔工作清單": "Transfer Jobs",
        "搬移 %ld 個項目": "Move %ld Items",
        "搬移": "Move",
        "搬移後嘅檔案已經搵唔到，所以未能還原。請先檢查新位置。": "The moved file can no longer be found, so this couldn’t be undone. Check the new location first.",
        "搬移未完全完成": "The Move Didn’t Finish Completely",
        "搬移未完成，新位置搵唔到檔案。請檢查原本位置同新位置。": "The move didn’t finish, and the file isn’t in the new location. Check both places.",
        "搬移項目": "Move Item",
        "搵到 %ld / %ld 個": "Found %ld / %ld",
        "搵唔到 Google Drive": "Google Drive Wasn’t Found",
        "搵唔到資料夾": "Folder Not Found",
        "搵字及取代": "Find and Replace",
        "操作已取消。": "The operation was cancelled.",
        "收藏": "Favorites",
        "收藏目前資料夾": "Add Current Folder to Favorites",
        "改名": "Rename",
        "改名稱及分組…": "Rename and Group…",
        "改唔到名": "Couldn’t Rename",
        "放大": "Zoom",
        "文件": "Documents",
        "新位置已有檔案，但舊位置仲有內容。為免刪錯，舊資料夾已保留，請檢查兩邊。": "The file is in the new location, but the old folder still has content. It was kept so nothing is deleted. Check both sides.",
        "新名稱有重複": "The New Names Clash",
        "新增": "Create",
        "新增包含所選 %ld 個項目的資料夾": "New Folder with %ld Items",
        "新增包含項目的資料夾": "New Folder with Selection",
        "新增唔到資料夾": "Couldn’t Create the Folder",
        "新增資料夾": "New Folder",
        "新舊檔案都有安全保留，但未能自動放回原位。請打開垃圾桶及目標資料夾檢查。": "Both the old and new files were kept, but they couldn’t be put back automatically. Check Trash and the destination folder.",
        "日期": "Date",
        "暫停": "Pause",
        "更改收藏": "Edit Favorite",
        "會複製 %ld 個較新或右邊未有嘅項目。\n同名舊版本會放入垃圾桶後取代。\n\n%@": "This will copy %ld newer items or items that aren’t on the other side.\nOlder items with the same name will be moved to Trash, then replaced.\n\n%@",
        "有 ZIP 解唔到": "Some ZIP Files Couldn’t Be Extracted",
        "有副本整唔到": "Some Duplicates Couldn’t Be Created",
        "有替身整唔到": "Some Aliases Couldn’t Be Created",
        "有標籤加唔到": "Some Tags Couldn’t Be Applied",
        "有項目搬唔到": "Some Items Couldn’t Be Moved",
        "有項目改唔到名": "Some Items Couldn’t Be Renamed",
        "未命名資料夾": "Untitled Folder",
        "未揀 ZIP": "No ZIP File Selected",
        "未揀檔案": "No Items Selected",
        "未有文字": "No Text Entered",
        "未能記住呢個資料夾": "Couldn’t Remember This Folder",
        "未能還原": "Couldn’t Undo",
        "未能顯示": "Couldn’t Show This Folder",
        "桌面": "Desktop",
        "標籤": "Tags",
        "標籤操作失敗": "The tag operation failed",
        "檔案": "File",
        "檔案仲處理緊": "Files Are Still Being Processed",
        "檔案已安全保留": "The Files Were Kept Safely",
        "檔案已搬到新位置，但有程式仲用緊舊資料夾，並喺舊位置重新整咗檔案。請先關閉相關程式，再檢查舊資料夾。": "The files were moved, but another app is still using the old folder and recreated files there. Close that app, then check the old folder.",
        "檔案已經唔喺原本位置，請按重新整理。": "The file is no longer in its original location. Click Refresh.",
        "次序": "Order",
        "正在停止…": "Stopping…",
        "正在處理檔案…": "Working with files…",
        "每次只可以幫一個檔案或資料夾改名。": "Rename one file or folder at a time.",
        "比較 1／2": "Compare 1 / 2",
        "比較完成": "Comparison Finished",
        "比較左右": "Compare Left and Right",
        "比較第 1 格同第 2 格": "Compare pane 1 and pane 2",
        "清單": "List",
        "清走已完成": "Clear Finished",
        "清除標籤": "Remove Tags",
        "清除顏色": "Clear Colors",
        "為免刪錯，舊資料已保留，但未能放回原名。請重新整理後檢查新舊兩邊。": "The original files were kept so nothing is deleted, but they couldn’t be restored to the old name. Refresh, then check both sides.",
        "為免刪錯，舊資料已安全保留為「%@」。請檢查新舊兩邊。": "The original files were kept as “%@” so nothing is deleted. Check both sides.",
        "狀態": "Status",
        "狀態：已連結": "Status: Connected",
        "狀態：舊資料夾／未連結": "Status: Previous Folder / Not Connected",
        "由大至細": "Descending",
        "由細至大": "Ascending",
        "略過": "Skip",
        "目標位置已有同名檔案。": "An item with the same name already exists in the destination.",
        "直欄": "Columns",
        "知道": "OK",
        "確認改 %ld 個名稱？": "Rename %ld items?",
        "移除收藏": "Remove Favorite",
        "種類": "Kind",
        "種類：%@\n大小：%@\n修改日期：%@\n位置：%@": "Kind: %@\nSize: %@\nDate Modified: %@\nWhere: %@",
        "種類：資料夾\n大小：%@\n修改日期：%@\n位置：%@": "Kind: Folder\nSize: %@\nDate Modified: %@\nWhere: %@",
        "立即下載雲端檔案": "Download Now",
        "第 1 格 → 第 2 格": "Pane 1 → Pane 2",
        "第 1 格獨有：%ld 個\n第 2 格獨有：%ld 個\n版本唔同：%ld 個\n完全一樣：%ld 個": "Only in pane 1: %ld\nOnly in pane 2: %ld\nDifferent: %ld\nIdentical: %ld",
        "第 2 格 → 第 1 格": "Pane 2 → Pane 1",
        "第一次使用呢個位置，需要你確認一次。": "The first time you use this location, macOS needs you to confirm access.",
        "等完成先關閉，避免檔案搬到一半。": "Wait until this finishes so files aren’t left half-moved.",
        "約 %ld 秒": "About %ld sec",
        "網站預覽程式": "a local web preview process",
        "編輯": "Edit",
        "縮到最小": "Minimize",
        "繼續": "Resume",
        "繼續等": "Keep Waiting",
        "而家退出唔到": "Can’t Eject Now",
        "舊資料夾再次出現": "The Old Folder Came Back",
        "藍色：只在一邊 · 橙色：版本唔同 · 灰色：一樣": "Blue: only on one side · Orange: different · Gray: identical",
        "處理緊 %ld/%ld": "Working %ld/%ld",
        "製作 %ld 個副本": "Duplicate %ld Items",
        "製作 %ld 個替身": "Make %ld Aliases",
        "製作副本": "Duplicate",
        "製作替身": "Make Alias",
        "複製 %ld 個項目": "Copy %ld Items",
        "複製": "Copy",
        "複製路徑": "Copy Path",
        "複製項目": "Copy Item",
        "要加嘅字／要搵嘅字／新名稱": "Text to add / find / new name",
        "視窗": "Window",
        "解壓 ZIP": "Extract ZIP",
        "請先揀一個或多個 ZIP 檔案。": "Select one or more ZIP files first.",
        "請先揀要壓縮嘅檔案。": "Select the files you want to compress.",
        "請先揀要搬去垃圾桶嘅項目。": "Select the items you want to move to Trash.",
        "請先複製一個或多個檔案。": "Copy one or more files first.",
        "請先開啟或重新安裝 Google Drive，再管理帳戶連結。": "Open or reinstall Google Drive, then manage the account connection.",
        "請按資料夾按鈕允許存取": "Click the folder button to allow access",
        "請揀一個項目": "Select One Item",
        "請揀多個項目": "Select Multiple Items",
        "請改一改設定，再試一次。": "Change the settings, then try again.",
        "請改一改設定，避免撞名。": "Change the settings to avoid name clashes.",
        "請用另一個名稱。": "Choose a different name.",
        "請輸入一條存在嘅資料夾路徑。": "Enter the path of a folder that exists.",
        "請輸入要加、要搵或新名稱。": "Enter the text to add, find, or use as the new name.",
        "貼上": "Paste",
        "貼上項目": "Paste Items",
        "資料夾": "Folder",
        "資料夾使用中": "Folder In Use",
        "資料夾入面已有檔案，為免刪錯，所以未能還原。": "The folder already has files in it, so this wasn’t undone.",
        "資料夾唔可以搬入自己入面。": "A folder can’t be moved into itself.",
        "載入中…": "Loading…",
        "輸入 ZIP 名稱：": "Enter a name for the ZIP file:",
        "輸入新名稱：": "Enter a new name:",
        "輸入資料夾名稱：": "Enter a folder name:",
        "返回": "Back",
        "退出 %@": "Eject %@",
        "退出硬碟": "Eject Disk",
        "選擇應用程式": "Choose Application",
        "選擇要顯示嘅資料夾": "Choose the Folder to Show",
        "選擇資料夾": "Choose Folder",
        "選擇雙開、三開或四開版面": "Choose a 2-, 3-, or 4-pane layout",
        "還原": "Undo",
        "重做": "Redo",
        "重新命名 %ld 個項目…": "Rename %ld Items…",
        "重新命名…": "Rename…",
        "重新整理": "Refresh",
        "開唔到呢個資料夾": "Can’t Open This Folder",
        "開唔到檔案": "Can’t Open the File",
        "開啟 %ld 個項目": "Open %ld Items",
        "開啟 Google Drive 管理…": "Open Google Drive Management…",
        "開啟": "Open",
        "開始同步": "Start Sync",
        "關於 Finder v2.0": "About Finder v2.0",
        "隱藏隱藏檔案": "Hide Hidden Files",
        "離開 Finder v2.0": "Quit Finder v2.0",
        "雲端": "Cloud",
        "順序編號": "Number Sequentially",
        "預覽及改名": "Preview and Rename",
        "顯示名稱": "Display Name",
        "顯示已隱藏雲端位置": "Show Hidden Cloud Locations",
        "顯示方式": "View",
        "顯示選項": "View Options",
        "顯示選項…": "Show View Options…",
        "顯示隱藏檔案": "Show Hidden Files",
        "（舊資料夾）": " (Previous Folder)",
        "等候中": "Waiting",
        "處理中": "Working",
        "已暫停": "Paused",
        "已完成": "Completed",
        "已取消": "Cancelled",
        "失敗": "Failed",
        "紅色": "Red",
        "橙色": "Orange",
        "黃色": "Yellow",
        "綠色": "Green",
        "藍色": "Blue",
        "紫色": "Purple",
        "灰色": "Gray",
        "語言": "Language",
        "跟隨系統": "Follow System"
    ]
}

func L(_ key: String) -> String {
    Localization.tr(key)
}
