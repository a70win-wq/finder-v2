import AppKit
import Testing
@testable import FinderV2

@Suite("Finder v2.0 多格版面")
@MainActor
struct LayoutGeometryTests {
    private let testSize = NSSize(width: 1_800, height: 1_000)
    private let tolerance: CGFloat = 1

    @Test("每個雙開、三開及四開版面都平均分配")
    func everyLayoutStartsEvenlyDivided() {
        let controller = makeController()

        for layout in PaneLayout.allCases {
            controller.applyLayout(layout)
            settleLayout(controller)

            let splitViews = mainSplitViews(in: controller.view)
            #expect(!splitViews.isEmpty, "版面 \(layout.title) 應該最少有一條分隔線")

            for splitView in splitViews {
                let sizes = paneThicknesses(in: splitView)
                guard let smallest = sizes.min(), let largest = sizes.max() else {
                    Issue.record("版面 \(layout.title) 有空白分隔群組")
                    continue
                }
                #expect(
                    largest - smallest <= tolerance,
                    "版面 \(layout.title) 每格相差唔應該超過 1 點；方向：\(splitView.isVertical ? "左右" : "上下")；大小：\(sizes)"
                )
            }
        }
    }

    @Test("四格版面上下分隔線會對齊")
    func fourGridDividersAreAligned() {
        let controller = makeController(layout: .fourGrid)
        let splitViews = mainSplitViews(in: controller.view)
        let columnSplits = splitViews.filter {
            $0.isVertical && $0.arrangedSubviews.count == 2
        }
        let rowSplit = splitViews.first {
            !$0.isVertical && $0.arrangedSubviews.count == 2
        }

        #expect(columnSplits.count == 2)
        #expect(rowSplit != nil)

        guard columnSplits.count == 2, let rowSplit else { return }
        let firstDivider = columnSplits[0].arrangedSubviews[0].frame.maxX
        let secondDivider = columnSplits[1].arrangedSubviews[0].frame.maxX
        #expect(abs(firstDivider - secondDivider) <= tolerance)

        let rowHeights = paneThicknesses(in: rowSplit)
        #expect(abs(rowHeights[0] - rowHeights[1]) <= tolerance)
    }

    @Test("平均分配完成後仍然可以自由拉闊")
    func userResizePersistsAfterInitialEqualization() {
        let controller = makeController(layout: .sideBySide)
        let splitView = controller.mainSplitView!
        let equalWidth = paneThicknesses(in: splitView)[0]
        let requestedPosition: CGFloat = 560

        splitView.onWillResize?()
        splitView.setPosition(requestedPosition, ofDividerAt: 0)
        splitView.onDidResize?()
        settleLayout(controller)
        let resizedWidth = paneThicknesses(in: splitView)[0]

        controller.view.needsLayout = true
        settleLayout(controller)
        let widthAfterAnotherLayoutPass = paneThicknesses(in: splitView)[0]

        #expect(abs(resizedWidth - requestedPosition) <= tolerance)
        #expect(abs(widthAfterAnotherLayoutPass - resizedWidth) <= tolerance)
        #expect(abs(resizedWidth - equalWidth) > 100)
    }

    @Test("切換版面後再次進入會重新平均分配")
    func returningToLayoutResetsToEvenSplit() {
        let controller = makeController(layout: .sideBySide)
        controller.mainSplitView.onWillResize?()
        controller.mainSplitView.setPosition(560, ofDividerAt: 0)
        controller.mainSplitView.onDidResize?()
        settleLayout(controller)

        controller.applyLayout(.stacked)
        settleLayout(controller)
        controller.applyLayout(.sideBySide)
        settleLayout(controller)

        let widths = paneThicknesses(in: controller.mainSplitView)
        #expect(abs(widths[0] - widths[1]) <= tolerance)
    }

    @Test("三格版面拉動分隔線後仍然可以自由調闊")
    func nestedLayoutUnlocksWhenUserStartsDragging() {
        let controller = makeController(layout: .threeLeft)
        let splitView = controller.mainSplitView!
        let requestedPosition: CGFloat = 620

        splitView.onWillResize?()
        splitView.setPosition(requestedPosition, ofDividerAt: 0)
        splitView.onDidResize?()
        settleLayout(controller)

        let resizedWidth = paneThicknesses(in: splitView)[0]
        #expect(abs(resizedWidth - requestedPosition) <= tolerance)
    }

    private func makeController(layout: PaneLayout = .sideBySide) -> MainViewController {
        let controller = MainViewController()
        controller.view.frame = NSRect(origin: .zero, size: testSize)
        controller.applyLayout(layout)
        settleLayout(controller)
        return controller
    }

    private func settleLayout(_ controller: MainViewController) {
        for _ in 0..<3 {
            controller.view.needsLayout = true
            controller.view.layoutSubtreeIfNeeded()
        }
    }

    private func mainSplitViews(in view: NSView) -> [MainSplitView] {
        var splitViews: [MainSplitView] = []
        if let splitView = view as? MainSplitView {
            splitViews.append(splitView)
        }
        for subview in view.subviews {
            splitViews.append(contentsOf: mainSplitViews(in: subview))
        }
        return splitViews
    }

    private func paneThicknesses(in splitView: NSSplitView) -> [CGFloat] {
        splitView.arrangedSubviews.map {
            splitView.isVertical ? $0.frame.width : $0.frame.height
        }
    }
}
