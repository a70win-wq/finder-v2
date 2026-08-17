import AppKit

struct FinderTag: CaseIterable, Hashable {
    let title: String
    let colorNumber: Int
    let color: NSColor

    static let red = FinderTag(title: "紅色", colorNumber: 6, color: .systemRed)
    static let orange = FinderTag(title: "橙色", colorNumber: 7, color: .systemOrange)
    static let yellow = FinderTag(title: "黃色", colorNumber: 5, color: .systemYellow)
    static let green = FinderTag(title: "綠色", colorNumber: 2, color: .systemGreen)
    static let blue = FinderTag(title: "藍色", colorNumber: 4, color: .systemBlue)
    static let purple = FinderTag(title: "紫色", colorNumber: 3, color: .systemPurple)
    static let grey = FinderTag(title: "灰色", colorNumber: 1, color: .systemGray)

    /// 介面顯示用嘅名稱（會跟語言翻譯）；`title` 本身保持穩定，寫入 metadata 用。
    var displayTitle: String {
        L(title)
    }

    static let allCases: [FinderTag] = [
        .red,
        .orange,
        .yellow,
        .green,
        .blue,
        .purple,
        .grey
    ]

    var metadataValue: String {
        "\(title)\n\(colorNumber)"
    }

    var rawValue: Int {
        colorNumber
    }
}

enum FileTagEngine {
    private static let attributeName = "com.apple.metadata:_kMDItemUserTags"

    static func apply(_ tag: FinderTag?, to urls: [URL]) throws {
        for url in urls {
            if let tag {
                try write([tag.metadataValue], to: url)
            } else {
                try remove(from: url)
            }
        }
    }

    private static func write(_ tags: [String], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: tags,
            format: .binary,
            options: 0
        )
        let hexadecimalValue = data.map { String(format: "%02x", $0) }.joined()
        try runXattr(arguments: ["-wx", attributeName, hexadecimalValue, url.path])
    }

    private static func remove(from url: URL) throws {
        do {
            try runXattr(arguments: ["-d", attributeName, url.path])
        } catch let error as NSError
            where error.domain == "FinderV2.FileTagEngine"
                && error.userInfo["stderr"] as? String != nil {
            let stderr = error.userInfo["stderr"] as? String ?? ""
            if stderr.localizedCaseInsensitiveContains("No such xattr") {
                return
            }
            throw error
        }
    }

    private static func runXattr(arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? L("標籤操作失敗")
            throw NSError(
                domain: "FinderV2.FileTagEngine",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: message,
                    "stderr": message
                ]
            )
        }
    }
}
