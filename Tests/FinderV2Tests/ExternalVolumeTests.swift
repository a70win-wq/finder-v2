import AppKit
import Testing
@testable import FinderV2

@Suite("Finder v2.0 外置硬碟")
struct ExternalVolumeTests {
    @Test("只顯示可瀏覽的外置或可退出硬碟")
    func externalVolumeDetectionUsesVolumeProperties() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FinderV2VolumeTests-\(UUID().uuidString)", isDirectory: true)
        let external = root.appendingPathComponent("USB", isDirectory: true)
        let internalVolume = root.appendingPathComponent("Internal", isDirectory: true)
        let hidden = root.appendingPathComponent("Hidden", isDirectory: true)
        try fileManager.createDirectory(at: external, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: internalVolume, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: hidden, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let locations = SidebarLocationProvider.locations(
            fileManager: fileManager,
            mountedVolumes: [
                MountedVolumeDescriptor(
                    url: external,
                    localizedName: "Macintosh HD",
                    isInternal: false,
                    isRemovable: true,
                    isEjectable: true,
                    isBrowsable: true
                ),
                MountedVolumeDescriptor(
                    url: internalVolume,
                    localizedName: "內置硬碟",
                    isInternal: true,
                    isRemovable: false,
                    isEjectable: false,
                    isBrowsable: true
                ),
                MountedVolumeDescriptor(
                    url: hidden,
                    localizedName: "隱藏硬碟",
                    isInternal: false,
                    isRemovable: true,
                    isEjectable: true,
                    isBrowsable: false
                )
            ]
        )

        let externalLocations = locations.filter(\.isExternalVolume)
        #expect(externalLocations.map(\.title) == ["Macintosh HD"])
        #expect(externalLocations.first?.url.standardizedFileURL == external.standardizedFileURL)
    }

    @MainActor
    @Test("插入、拔走或改名硬碟會即時更新側欄")
    func workspaceVolumeNotificationsReloadSidebar() {
        let notificationCenter = NotificationCenter()
        var reloadCount = 0
        let controller = SidebarViewController(
            locationProvider: {
                reloadCount += 1
                return []
            },
            workspaceNotificationCenter: notificationCenter
        )

        _ = controller.view
        #expect(reloadCount == 1)

        notificationCenter.post(name: NSWorkspace.didMountNotification, object: nil)
        #expect(reloadCount == 2)

        notificationCenter.post(name: NSWorkspace.didUnmountNotification, object: nil)
        #expect(reloadCount == 3)

        notificationCenter.post(name: NSWorkspace.didRenameVolumeNotification, object: nil)
        #expect(reloadCount == 4)
    }
}
