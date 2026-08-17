import AppKit
import Darwin

enum CloudAvailability: Hashable {
    case local
    case onlineOnly
    case downloading
    case downloaded

    var title: String {
        switch self {
        case .local: return ""
        case .onlineOnly: return L("雲端")
        case .downloading: return L("下載中")
        case .downloaded: return L("已下載")
        }
    }
}

struct FileItem: Hashable {
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let fileSize: Int64?
    let modifiedDate: Date?
    let kind: String
    var cloudAvailability: CloudAvailability = .local
    // load() 會一次過計好顯示名稱，避免排序同顯示時重複呼叫
    // FileManager.displayName(atPath:)，呢個係純粹嘅內部快取。
    var storedName: String?

    var name: String {
        storedName ?? FileManager.default.displayName(atPath: url.path)
    }

    /// 檔案系統上嘅真實檔名（改名、比較、同步都要用呢個，唔好用 displayName）。
    var fileSystemName: String {
        url.lastPathComponent
    }

    var shouldOpenAsFolder: Bool {
        isDirectory && !isPackage
    }

    static func loadItem(at url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        // loadItem 係讀一個已知路徑，唔應該因為隱藏就當佢唔存在。
        // 隱藏過濾只應發生喺目錄列表。
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        return FileItem(
            url: url,
            isDirectory: values.isDirectory == true,
            isPackage: values.isPackage == true,
            fileSize: values.fileSize.map(Int64.init),
            modifiedDate: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? (values.isDirectory == true ? L("資料夾") : L("檔案")),
            cloudAvailability: cloudAvailability(from: values),
            storedName: FileManager.default.displayName(atPath: url.path)
        )
    }

    static func load(
        from directory: URL,
        fileManager: FileManager = .default,
        showHidden: Bool = false
    ) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: showHidden ? [] : [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard showHidden || values.isHidden != true else { return nil }
                return FileItem(
                    url: url,
                    isDirectory: values.isDirectory == true,
                    isPackage: values.isPackage == true,
                    fileSize: values.fileSize.map(Int64.init),
                    modifiedDate: values.contentModificationDate,
                    kind: values.localizedTypeDescription ?? (values.isDirectory == true ? L("資料夾") : L("檔案")),
                    cloudAvailability: cloudAvailability(from: values),
                    storedName: fileManager.displayName(atPath: url.path)
                )
            } catch {
                return nil
            }
        }
        .sorted {
            if $0.shouldOpenAsFolder != $1.shouldOpenAsFolder {
                return $0.shouldOpenAsFolder && !$1.shouldOpenAsFolder
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func cloudAvailability(from values: URLResourceValues) -> CloudAvailability {
        guard values.isUbiquitousItem == true else { return .local }
        switch values.ubiquitousItemDownloadingStatus {
        case .current?, .downloaded?:
            return .downloaded
        case .notDownloaded?:
            return .onlineOnly
        default:
            return .downloading
        }
    }
}

enum FileSortOption: Int, CaseIterable {
    case name
    case size
    case modified
    case kind

    var title: String {
        switch self {
        case .name: return L("名稱")
        case .size: return L("大小")
        case .modified: return L("日期")
        case .kind: return L("種類")
        }
    }
}

enum FileDisplayArrangement {
    static func items(
        from source: [FileItem],
        matching searchText: String,
        sortedBy sortOption: FileSortOption,
        ascending: Bool,
        sourceIsPresortedByNameAscending: Bool = false
    ) -> [FileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? source
            : source.filter { $0.name.localizedCaseInsensitiveContains(query) }

        // FileItem.load() already sorts by folder-first + name ascending,
        // and filter() preserves that order, so the default arrangement can
        // skip a second, identical sort pass.
        if sourceIsPresortedByNameAscending, sortOption == .name, ascending {
            return filtered
        }

        return filtered.sorted { left, right in
            if left.shouldOpenAsFolder != right.shouldOpenAsFolder {
                return left.shouldOpenAsFolder
            }

            let comparison: ComparisonResult
            switch sortOption {
            case .name:
                comparison = left.name.localizedStandardCompare(right.name)
            case .size:
                comparison = compare(left.fileSize ?? 0, right.fileSize ?? 0)
            case .modified:
                comparison = compare(
                    left.modifiedDate ?? .distantPast,
                    right.modifiedDate ?? .distantPast
                )
            case .kind:
                comparison = left.kind.localizedStandardCompare(right.kind)
            }

            if comparison == .orderedSame {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}

struct SidebarLocation: Hashable {
    let title: String
    let url: URL
    let symbolName: String
    var isFavorite = false
    var favoriteID: UUID?
    var isExternalVolume = false
    var isCloudStorage = false
    var isFileProviderBacked = false
    var cloudProviderBundleIdentifier: String?
}

struct MountedVolumeDescriptor: Hashable {
    let url: URL
    let localizedName: String?
    let isInternal: Bool?
    let isRemovable: Bool?
    let isEjectable: Bool?
    let isBrowsable: Bool?

    var shouldAppearAsExternalVolume: Bool {
        guard isBrowsable != false else { return false }
        if isInternal == false || isRemovable == true || isEjectable == true {
            return true
        }
        if isInternal == true {
            return false
        }
        return url.standardizedFileURL.path.hasPrefix("/Volumes/")
    }
}

struct FavoriteEntry: Codable, Hashable, Identifiable {
    let id: UUID
    var path: String
    var title: String
    var group: String

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

final class FavoriteStore {
    static let shared = FavoriteStore()

    private let defaultsKey = "FinderV2FavoriteFolders"
    private let entriesKey = "FinderV2FavoriteEntriesV2"

    var urls: [URL] {
        entries.map(\.url)
    }

    /// 已儲存嘅完整收藏清單（包括而家未掛載嘅路徑）。
    /// 顯示時先用 `entries` 過濾；改動必須寫返呢份完整清單，否則拔走硬碟後再改收藏會永久刪走舊項。
    var storedEntries: [FavoriteEntry] {
        if let data = UserDefaults.standard.data(forKey: entriesKey),
           let decoded = try? JSONDecoder().decode([FavoriteEntry].self, from: data) {
            return decoded
        }
        let migrated = (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            .map { path in
                FavoriteEntry(
                    id: UUID(),
                    path: URL(fileURLWithPath: path).standardizedFileURL.path,
                    title: FileManager.default.displayName(atPath: path),
                    group: L("收藏")
                )
            }
        save(migrated)
        return migrated
    }

    var entries: [FavoriteEntry] {
        storedEntries.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        var saved = storedEntries
        guard !saved.contains(where: { $0.path == standardized.path }) else { return }
        saved.append(
            FavoriteEntry(
                id: UUID(),
                path: standardized.path,
                title: FileManager.default.displayName(atPath: standardized.path),
                group: L("收藏")
            )
        )
        save(saved)
    }

    func remove(_ url: URL) {
        let path = url.standardizedFileURL.path
        save(storedEntries.filter { $0.path != path })
    }

    func update(id: UUID, title: String, group: String) {
        var saved = storedEntries
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].title = title
        saved[index].group = group
        save(saved)
    }

    func move(id: UUID, to destinationIndex: Int) {
        var visible = entries
        guard let sourceIndex = visible.firstIndex(where: { $0.id == id }) else { return }
        let entry = visible.remove(at: sourceIndex)
        visible.insert(entry, at: min(max(0, destinationIndex), visible.count))

        // 未掛載嘅收藏留喺原本位置，只重排而家睇到嘅項。
        var remainingVisible = visible
        var merged: [FavoriteEntry] = []
        for stored in storedEntries {
            if FileManager.default.fileExists(atPath: stored.path) {
                if !remainingVisible.isEmpty {
                    merged.append(remainingVisible.removeFirst())
                }
            } else {
                merged.append(stored)
            }
        }
        merged.append(contentsOf: remainingVisible)
        save(merged)
    }

    private func save(_ entries: [FavoriteEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
        UserDefaults.standard.set(entries.map(\.path), forKey: defaultsKey)
        SidebarLocationProvider.invalidateCachedLocations()
    }
}

enum HiddenCloudLocationStore {
    static let defaultsKey = "FinderV2HiddenCloudLocations"

    static var hiddenPaths: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    static var hasHiddenLocations: Bool {
        !hiddenPaths.isEmpty
    }

    static func isHidden(_ url: URL) -> Bool {
        hiddenPaths.contains(url.standardizedFileURL.path)
    }

    static func hide(_ url: URL) {
        var paths = hiddenPaths
        paths.insert(url.standardizedFileURL.path)
        UserDefaults.standard.set(Array(paths).sorted(), forKey: defaultsKey)
        SidebarLocationProvider.invalidateCachedLocations()
    }

    static func unhideAll() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        SidebarLocationProvider.invalidateCachedLocations()
    }
}

private enum CloudStorageMetadata {
    private static let fileProviderDomainAttribute = "com.apple.file-provider-domain-id"

    static func isFileProviderBacked(at url: URL) -> Bool {
        url.path.withCString { path in
            fileProviderDomainAttribute.withCString { name in
                Darwin.getxattr(path, name, nil, 0, 0, 0) > 0
            }
        }
    }
}

enum SidebarLocationProvider {
    private static let volumeResourceKeys: Set<URLResourceKey> = [
        .volumeIsInternalKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsBrowsableKey,
        .volumeLocalizedNameKey
    ]

    // 側邊欄掃描（收藏、雲端資料夾、外置硬碟）成本唔低，而且喺每次
    // 目錄 reload 都會被呼叫。只有收藏、隱藏設定或硬碟有變時先需要重掃，
    // 所以結果喺度快取，相關改動會透過 invalidateCachedLocations() 失效。
    private static var cachedLocations: [SidebarLocation]?

    static func invalidateCachedLocations() {
        cachedLocations = nil
    }

    static func locations(
        fileManager: FileManager = .default,
        mountedVolumes: [MountedVolumeDescriptor]? = nil
    ) -> [SidebarLocation] {
        if mountedVolumes == nil, let cachedLocations {
            return cachedLocations
        }

        let result = buildLocations(
            fileManager: fileManager,
            mountedVolumes: mountedVolumes
        )
        if mountedVolumes == nil {
            cachedLocations = result
        }
        return result
    }

    private static func buildLocations(
        fileManager: FileManager,
        mountedVolumes: [MountedVolumeDescriptor]?
    ) -> [SidebarLocation] {
        let home = fileManager.homeDirectoryForCurrentUser
        var locations: [SidebarLocation] = [
            SidebarLocation(title: L("主目錄"), url: home, symbolName: "house"),
            SidebarLocation(title: L("桌面"), url: home.appendingPathComponent("Desktop"), symbolName: "menubar.dock.rectangle"),
            SidebarLocation(title: L("文件"), url: home.appendingPathComponent("Documents"), symbolName: "doc"),
            SidebarLocation(title: L("下載項目"), url: home.appendingPathComponent("Downloads"), symbolName: "arrow.down.circle")
        ]

        let fixedPaths = Set(locations.map { $0.url.standardizedFileURL.path })
        for favorite in FavoriteStore.shared.entries where !fixedPaths.contains(favorite.path) {
            locations.append(
                SidebarLocation(
                    title: favorite.group.isEmpty
                        ? favorite.title
                        : "\(favorite.group) · \(favorite.title)",
                    url: favorite.url,
                    symbolName: "star.fill",
                    isFavorite: true,
                    favoriteID: favorite.id
                )
            )
        }

        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fileManager.fileExists(atPath: iCloud.path) {
            locations.append(SidebarLocation(title: L("iCloud 雲碟"), url: iCloud, symbolName: "icloud"))
        }

        let cloudStorage = home.appendingPathComponent("Library/CloudStorage")
        if let cloudURLs = try? fileManager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for cloudURL in cloudURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let standardizedURL = cloudURL.standardizedFileURL
                guard !HiddenCloudLocationStore.isHidden(standardizedURL) else { continue }

                let name = cloudURL.lastPathComponent
                    .replacingOccurrences(of: "GoogleDrive-", with: "Google Drive – ")
                let isFileProviderBacked = CloudStorageMetadata.isFileProviderBacked(at: standardizedURL)
                let title = isFileProviderBacked ? name : "\(name)" + L("（舊資料夾）")
                let providerBundleIdentifier = cloudURL.lastPathComponent.hasPrefix("GoogleDrive-")
                    ? "com.google.drivefs"
                    : nil
                locations.append(
                    SidebarLocation(
                        title: title,
                        url: standardizedURL,
                        symbolName: "externaldrive.badge.icloud",
                        isCloudStorage: true,
                        isFileProviderBacked: isFileProviderBacked,
                        cloudProviderBundleIdentifier: providerBundleIdentifier
                    )
                )
            }
        }

        let externalVolumes = (mountedVolumes ?? discoverMountedVolumes(fileManager: fileManager))
            .filter(\.shouldAppearAsExternalVolume)
            .sorted {
                let left = $0.localizedName ?? $0.url.lastPathComponent
                let right = $1.localizedName ?? $1.url.lastPathComponent
                return left.localizedStandardCompare(right) == .orderedAscending
            }

        for volume in externalVolumes {
            locations.append(
                SidebarLocation(
                    title: volume.localizedName ?? fileManager.displayName(atPath: volume.url.path),
                    url: volume.url,
                    symbolName: "externaldrive",
                    isExternalVolume: true
                )
            )
        }

        return locations.filter { fileManager.fileExists(atPath: $0.url.path) }
    }

    private static func discoverMountedVolumes(
        fileManager: FileManager
    ) -> [MountedVolumeDescriptor] {
        let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(volumeResourceKeys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.map { url in
            let values = try? url.resourceValues(forKeys: volumeResourceKeys)
            return MountedVolumeDescriptor(
                url: url.standardizedFileURL,
                localizedName: values?.volumeLocalizedName,
                isInternal: values?.volumeIsInternal,
                isRemovable: values?.volumeIsRemovable,
                isEjectable: values?.volumeIsEjectable,
                isBrowsable: values?.volumeIsBrowsable
            )
        }
    }
}

enum FileFormatting {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private static let dateFormatterLock = NSLock()
    private static var cachedDateFormatter = makeDateFormatter()

    static var dateFormatter: DateFormatter {
        dateFormatterLock.lock()
        defer { dateFormatterLock.unlock() }
        return cachedDateFormatter
    }

    static func applyCurrentLocale() {
        dateFormatterLock.lock()
        cachedDateFormatter = makeDateFormatter()
        dateFormatterLock.unlock()
    }

    static func size(for item: FileItem) -> String {
        guard !item.isDirectory, let size = item.fileSize else { return "—" }
        return byteFormatter.string(fromByteCount: size)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Localization.locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }
}

extension Notification.Name {
    static let finderV2FileSystemChanged = Notification.Name("FinderV2FileSystemChanged")
    static let finderV2OperationStatusChanged = Notification.Name("FinderV2OperationStatusChanged")
    static let finderV2LanguageChanged = Notification.Name("FinderV2LanguageChanged")
}
