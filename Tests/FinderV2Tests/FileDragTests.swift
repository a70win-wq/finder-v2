import AppKit
import Foundation
import Testing
@testable import FinderV2

@Suite("Finder v2.0 拖拉")
struct FileDragTests {
    private func item(_ name: String, isDirectory: Bool = false) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/FinderV2Drag/\(name)"),
            isDirectory: isDirectory,
            isPackage: false,
            fileSize: isDirectory ? nil : 1,
            modifiedDate: Date(timeIntervalSince1970: 100),
            kind: isDirectory ? "資料夾" : "檔案"
        )
    }

    @Test("放入資料夾先會入去嗰個資料夾，否則用而家呢格")
    func dropDestinationUsesFolderOnlyWhenDroppingOntoIt() {
        let folder = item("相簿", isDirectory: true)
        let file = item("相片.jpg")
        let current = URL(fileURLWithPath: "/tmp/FinderV2Drag", isDirectory: true)
        let items = [folder, file]

        #expect(
            FileDragSupport.dropDestination(
                items: items,
                row: 0,
                dropOntoItem: true,
                currentDirectory: current
            ) == folder.url
        )
        #expect(
            FileDragSupport.dropDestination(
                items: items,
                row: 0,
                dropOntoItem: false,
                currentDirectory: current
            ) == current
        )
        #expect(
            FileDragSupport.dropDestination(
                items: items,
                row: 1,
                dropOntoItem: true,
                currentDirectory: current
            ) == current
        )
        #expect(
            FileDragSupport.dropDestination(
                items: items,
                row: -1,
                dropOntoItem: true,
                currentDirectory: current
            ) == current
        )
    }

    @Test("拖一行如果已經喺多選入面，會一齊拖晒")
    func draggingUsesWholeSelectionWhenClickedRowIsSelected() {
        let items = [item("A.txt"), item("B.txt"), item("C.txt")]
        let selected = IndexSet([0, 2])
        let rows = FileDragSupport.draggingRows(from: IndexSet(integer: 2), selected: selected)
        #expect(FileDragSupport.draggingURLs(from: items, rows: rows).map(\.lastPathComponent) == ["A.txt", "C.txt"])

        let onlyClicked = FileDragSupport.draggingRows(from: IndexSet(integer: 1), selected: selected)
        #expect(FileDragSupport.draggingURLs(from: items, rows: onlyClicked).map(\.lastPathComponent) == ["B.txt"])
    }

    @Test("剪貼板可以寫入及讀返檔案路徑")
    func pasteboardRoundTripWritesFileURLs() {
        let urls = [
            URL(fileURLWithPath: "/tmp/FinderV2Drag/A.txt"),
            URL(fileURLWithPath: "/tmp/FinderV2Drag/B.txt")
        ]
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        #expect(FileDragSupport.writeFileURLs(urls, to: pasteboard))
        #expect(
            Set(FileDragSupport.fileURLs(from: pasteboard).map(\.standardizedFileURL.path))
                == Set(urls.map(\.standardizedFileURL.path))
        )
    }

    @Test("舊式檔名清單都可以讀到")
    func pasteboardReadsLegacyFilenames() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setPropertyList(
            ["/tmp/FinderV2Drag/舊檔.txt"],
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        )

        #expect(
            FileDragSupport.fileURLs(from: pasteboard).map(\.lastPathComponent) == ["舊檔.txt"]
        )
    }

    @Test("直欄瀏覽器有拖出同放入支援")
    @MainActor
    func columnBrowserSupportsDraggingSourceAndDestination() {
        let controller = FileTableViewController()
        _ = controller.view
        controller.setViewMode(.columns)
        controller.reload(
            items: [item("報告.txt"), item("資料", isDirectory: true)],
            currentDirectory: URL(fileURLWithPath: "/tmp/FinderV2Drag", isDirectory: true)
        )

        #expect(controller.browserSupportsDraggingSourceForTesting)
        #expect(controller.browserAcceptsFileURLDropsForTesting)
    }
}
