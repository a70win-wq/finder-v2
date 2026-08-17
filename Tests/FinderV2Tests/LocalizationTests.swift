import Foundation
import Testing
@testable import FinderV2

// 呢幾個測試共用同一個 UserDefaults key，要順序執行避免互相搶。
@Suite("Finder v2.0 語言設定", .serialized)
struct LocalizationTests {
    private func restoreLanguagePreference() {
        let previous = UserDefaults.standard.object(forKey: Localization.languagePreferenceKey)
        if let previous {
            UserDefaults.standard.set(previous, forKey: Localization.languagePreferenceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Localization.languagePreferenceKey)
        }
        SidebarLocationProvider.invalidateCachedLocations()
        FileFormatting.applyCurrentLocale()
    }

    @Test("粵語模式下所有文字原樣顯示")
    func zhHantShowsSourceText() {
        defer { restoreLanguagePreference() }
        Localization.preferredLanguage = "zh-Hant"

        #expect(Localization.supportedLanguages.contains("zh-Hant"))
        #expect(Localization.supportedLanguages.contains("en"))
        #expect(L("新增資料夾") == "新增資料夾")
        #expect(L("搬去垃圾桶") == "搬去垃圾桶")
    }

    @Test("英文模式會用翻譯")
    func englishUsesTranslations() {
        defer { restoreLanguagePreference() }
        Localization.preferredLanguage = "en"

        #expect(Localization.preferredLanguage == "en")
        #expect(L("新增資料夾") == "New Folder")
        #expect(L("搬去垃圾桶") == "Move to Trash")
        #expect(L("開啟") == "Open")
        #expect(String(format: L("%ld 個項目"), 3) == "3 items")
        #expect(String(format: L("拷貝「%@」"), "Report") == "Copy “Report”")
    }

    @Test("唔受支援嘅語言會自動用返預設語言")
    func unsupportedLanguageFallsBackToDefault() {
        defer { restoreLanguagePreference() }
        UserDefaults.standard.set("fr", forKey: Localization.languagePreferenceKey)

        #expect(Localization.preferredLanguage == Localization.defaultLanguage)
        #expect(L("新增資料夾") == "新增資料夾")
    }

    @Test("英文翻譯會保留格式佔位符")
    func englishFormatStringsKeepSpecifiers() {
        func specifiers(in text: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: "%(?:ld|@|d|f)")
            let range = NSRange(text.startIndex..., in: text)
            return pattern.matches(in: text, range: range).map {
                String(text[Range($0.range, in: text)!])
            }
        }

        for (key, value) in Localization.enTranslations {
            #expect(
                specifiers(in: key) == specifiers(in: value),
                "格式唔一致：\(key) → \(value)"
            )
        }
    }

    @Test("跟系統語言可以清走手動設定")
    func followSystemClearsSavedPreference() {
        defer { restoreLanguagePreference() }
        Localization.preferredLanguage = "en"
        #expect(!Localization.followsSystemLanguage)
        Localization.followSystemLanguage()
        #expect(Localization.followsSystemLanguage)
    }
}
