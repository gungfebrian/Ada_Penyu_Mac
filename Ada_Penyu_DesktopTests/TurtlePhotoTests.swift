import AppKit
import SwiftUI
import XCTest
@testable import Ada_Penyu_Desktop

@MainActor
final class TurtlePhotoTests: XCTestCase {
    func testPhotoTriesOtherIdentitySideWhenFirstIsUnavailable() async throws {
        let loaded = expectation(description: "Other identity side requested")
        var requested: [String?] = []
        let view = TurtlePhoto(paths: ["/left", "/right"], size: 30)
            .environment(\.turtlePhotoLoader, { path in
                requested.append(path)
                if path == "/left" { return nil }
                loaded.fulfill()
                return NSImage(size: NSSize(width: 10, height: 10))
            })
        let window = display(view)
        defer { window.orderOut(nil) }
        await fulfillment(of: [loaded], timeout: 3)
        XCTAssertEqual(requested, ["/left", "/right"])
    }

    private func display(_ view: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        window.orderFrontRegardless()
        return window
    }

    func testIndividualRowRequestsItsIdentityPhoto() async throws {
        let loaded = expectation(description: "Row requests identity photo")
        let turtle = TestTurtleRepository.turtle
        let view = IndividualsView(turtles: [turtle], total: 1, searchText: .constant(""), selectedCondition: .constant(nil), favoriteIDs: [], onToggleFavorite: { _ in }, onSelect: { _ in })
            .environment(\.turtlePhotoLoader, { path in
                XCTAssertEqual(path, turtle.leftPhotoURL)
                loaded.fulfill()
                return NSImage(size: NSSize(width: 10, height: 10))
            })
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        await fulfillment(of: [loaded], timeout: 3)
    }
}
