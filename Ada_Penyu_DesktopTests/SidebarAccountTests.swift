import AppKit
import SwiftUI
import XCTest
@testable import Ada_Penyu_Desktop

final class SidebarAccountTests: XCTestCase {
    func testAccountMenuListsDataSourceAndSignOut() {
        let model = SidebarAccountMenuModel()
        model.dataMode = .demo
        model.onSignOut = {}
        model.onOpenAuthSettings = {}

        let menu = model.makeMenu()
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("Demo mode"))
        XCTAssertTrue(titles.contains("Live API"))
        XCTAssertTrue(titles.contains("Sign Out"))
        XCTAssertEqual(menu.items.first { $0.title == "Demo mode" }?.state, .on)
        XCTAssertEqual(menu.items.first { $0.title == "Live API" }?.state, .off)

        var chosen: DataMode?
        model.onModeChange = { chosen = $0 }
        let live = menu.items.first { $0.title == "Live API" }
        model.chooseMode(live!)
        XCTAssertEqual(chosen, .live)
    }

    @MainActor
    func testAccountRowKeepsTheNameVisible() {
        let host = NSHostingView(rootView: accountSidebar)
        host.frame = NSRect(x: 0, y: 0, width: 253, height: 720)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 253, height: 720),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let account = findViews(named: "SidebarAccountMenuHost", in: host)
        XCTAssertEqual(account.count, 1, viewTree(host))
        XCTAssertGreaterThan(account[0].frame.width, 180, viewTree(host))
        XCTAssertGreaterThan(account[0].frame.height, 40, viewTree(host))

        let label = account[0].accessibilityLabel() ?? ""
        XCTAssertTrue(label.contains("Amina Saleh"), label)
        XCTAssertTrue(label.contains("amina@example.com"), label)
        XCTAssertTrue(label.contains("Demo"), label)

        let local = NSPoint(x: account[0].bounds.midX, y: account[0].bounds.midY)
        let inSuper = account[0].convert(local, to: account[0].superview)
        XCTAssertTrue(account[0].hitTest(inSuper) === account[0])
        XCTAssertTrue(findViews(named: "SwiftUIPopupButton", in: host).isEmpty, viewTree(host))
    }

    @MainActor
    private var accountSidebar: some View {
        SidebarView(
            selection: .constant(.dashboard),
            selectedCondition: .constant(nil),
            favoriteCount: 2,
            selectedSpecies: nil,
            onSelectSpecies: { _ in },
            dataMode: .demo,
            isFallback: false,
            onModeChange: { _ in },
            accountName: "Amina Saleh",
            accountEmail: "amina@example.com",
            accountOrganization: "Sea Turtle Group"
        )
    }
}

private func findViews(named name: String, in view: NSView) -> [NSView] {
    let matches = String(describing: type(of: view)).contains(name) ? [view] : []
    return matches + view.subviews.flatMap { findViews(named: name, in: $0) }
}

private func viewTree(_ view: NSView, indent: Int = 0) -> String {
    let line = String(repeating: " ", count: indent) + "\(type(of: view)) \(Int(view.frame.width))x\(Int(view.frame.height))"
    return ([line] + view.subviews.map { viewTree($0, indent: indent + 2) }).joined(separator: "\n")
}
