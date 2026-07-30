import AppKit
import Testing
@testable import FinderV2

@Suite("Finder v2.0 排序整合")
struct SortingIntegrationTests {
    private func sampleItems() -> [FileItem] {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2SortingTests", isDirectory: true)

        return [
            FileItem(
                url: baseURL.appendingPathComponent("Alpha.txt"),
                isDirectory: false,
                isPackage: false,
                fileSize: 30,
                modifiedDate: Date(timeIntervalSince1970: 300),
                kind: "Gamma"
            ),
            FileItem(
                url: baseURL.appendingPathComponent("Bravo.pdf"),
                isDirectory: false,
                isPackage: false,
                fileSize: 10,
                modifiedDate: Date(timeIntervalSince1970: 100),
                kind: "Alpha"
            ),
            FileItem(
                url: baseURL.appendingPathComponent("Charlie.png"),
                isDirectory: false,
                isPackage: false,
                fileSize: 20,
                modifiedDate: Date(timeIntervalSince1970: 200),
                kind: "Beta"
            )
        ]
    }

    private func arrangedNames(
        sortedBy option: FileSortOption,
        ascending: Bool
    ) -> [String] {
        FileDisplayArrangement.items(
            from: sampleItems(),
            matching: "",
            sortedBy: option,
            ascending: ascending
        )
        .map(\.name)
    }

    @Test("名稱可以升序及降序")
    func nameSortsInBothDirections() {
        #expect(
            arrangedNames(sortedBy: .name, ascending: true)
                == ["Alpha.txt", "Bravo.pdf", "Charlie.png"]
        )
        #expect(
            arrangedNames(sortedBy: .name, ascending: false)
                == ["Charlie.png", "Bravo.pdf", "Alpha.txt"]
        )
    }

    @Test("大小可以升序及降序")
    func sizeSortsInBothDirections() {
        #expect(
            arrangedNames(sortedBy: .size, ascending: true)
                == ["Bravo.pdf", "Charlie.png", "Alpha.txt"]
        )
        #expect(
            arrangedNames(sortedBy: .size, ascending: false)
                == ["Alpha.txt", "Charlie.png", "Bravo.pdf"]
        )
    }

    @Test("種類可以升序及降序")
    func kindSortsInBothDirections() {
        #expect(
            arrangedNames(sortedBy: .kind, ascending: true)
                == ["Bravo.pdf", "Charlie.png", "Alpha.txt"]
        )
        #expect(
            arrangedNames(sortedBy: .kind, ascending: false)
                == ["Alpha.txt", "Charlie.png", "Bravo.pdf"]
        )
    }

    @Test("日期可以升序及降序")
    func modifiedDateSortsInBothDirections() {
        #expect(
            arrangedNames(sortedBy: .modified, ascending: true)
                == ["Bravo.pdf", "Charlie.png", "Alpha.txt"]
        )
        #expect(
            arrangedNames(sortedBy: .modified, ascending: false)
                == ["Alpha.txt", "Charlie.png", "Bravo.pdf"]
        )
    }

    @Test("清單表頭會通知排序選擇及方向")
    @MainActor
    func tableHeaderSortNotifiesDelegateAndKeepsDirectionInSync() {
        let controller = FileTableViewController()
        let spy = SortingDelegateSpy()
        controller.delegate = spy
        _ = controller.view

        let expectedColumnKeys: [(FileSortOption, String)] = [
            (.name, "name"),
            (.size, "size"),
            (.kind, "kind"),
            (.modified, "modified")
        ]

        for (option, key) in expectedColumnKeys {
            let column = controller.tableView.tableColumn(
                withIdentifier: NSUserInterfaceItemIdentifier(key)
            )
            #expect(column?.sortDescriptorPrototype?.key == key)

            controller.setDisplayOptions(
                sortOption: option,
                ascending: false,
                showHiddenFiles: false
            )
            #expect(controller.tableView.highlightedTableColumn === column)
            #expect(controller.tableView.sortDescriptors.first?.key == key)
            #expect(controller.tableView.sortDescriptors.first?.ascending == false)
        }

        #expect(spy.sortRequests.isEmpty)

        controller.tableView.sortDescriptors = [
            NSSortDescriptor(key: "modified", ascending: true)
        ]

        #expect(spy.sortRequests.last?.option.rawValue == FileSortOption.modified.rawValue)
        #expect(spy.sortRequests.last?.ascending == true)
        #expect(spy.sortRequests.count == 1)

        controller.tableView.sortDescriptors = [
            NSSortDescriptor(key: "modified", ascending: false)
        ]

        #expect(spy.sortRequests.last?.option.rawValue == FileSortOption.modified.rawValue)
        #expect(spy.sortRequests.last?.ascending == false)
        #expect(spy.sortRequests.count == 2)
    }
}

private final class SortingDelegateSpy: FileTableViewControllerDelegate {
    struct SortRequest {
        let option: FileSortOption
        let ascending: Bool
    }

    var sortRequests: [SortRequest] = []

    func fileTable(
        _ controller: FileTableViewController,
        didRequestSortBy option: FileSortOption,
        ascending: Bool
    ) {
        sortRequests.append(SortRequest(option: option, ascending: ascending))
    }

    func fileTableDidActivate(_ controller: FileTableViewController) {}
    func fileTable(_ controller: FileTableViewController, didOpen item: FileItem) {}
    func fileTable(
        _ controller: FileTableViewController,
        didReceive urls: [URL],
        at destination: URL,
        operation: FileTransferOperation
    ) {}
    func fileTableDidRequestRename(_ controller: FileTableViewController) {}
    func fileTableDidRequestBatchRename(_ controller: FileTableViewController) {}
    func fileTableDidRequestCreateZip(_ controller: FileTableViewController) {}
    func fileTableDidRequestExtractZip(_ controller: FileTableViewController) {}
    func fileTableDidRequestCloudDownload(_ controller: FileTableViewController) {}
    func fileTableDidRequestTrash(_ controller: FileTableViewController) {}
    func fileTableDidRequestPreview(_ controller: FileTableViewController) {}
    func fileTableDidRequestCopy(_ controller: FileTableViewController) {}
    func fileTableDidRequestPaste(_ controller: FileTableViewController) {}
    func fileTableDidRequestDuplicate(_ controller: FileTableViewController) {}
    func fileTableDidRequestInfo(_ controller: FileTableViewController) {}
    func fileTableDidRequestCopyPath(_ controller: FileTableViewController) {}
    func fileTableDidRequestReveal(_ controller: FileTableViewController) {}
    func fileTable(
        _ controller: FileTableViewController,
        didRequestViewMode mode: FileViewMode
    ) {}
    func fileTableDidRequestNewFolder(_ controller: FileTableViewController) {}
    func fileTableDidRequestFolderWithSelection(_ controller: FileTableViewController) {}
    func fileTable(
        _ controller: FileTableViewController,
        didRequestOpenWith applicationURL: URL
    ) {}
    func fileTableDidRequestChooseApplication(_ controller: FileTableViewController) {}
    func fileTableDidRequestAlias(_ controller: FileTableViewController) {}
    func fileTableDidRequestShowViewOptions(_ controller: FileTableViewController) {}
    func fileTableDidRequestToggleHiddenFiles(_ controller: FileTableViewController) {}
    func fileTable(
        _ controller: FileTableViewController,
        didRequestTag tag: FinderTag?
    ) {}
}
