//
//  Ada_Penyu_DesktopApp.swift
//  Ada_Penyu_Desktop
//
//  Created by Gung  on 24/08/26.
//

import SwiftUI
import AppKit

@main
struct Ada_Penyu_DesktopApp: App {
    init() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: AdaLayout.minimumWindowSize.width,
                    minHeight: AdaLayout.minimumWindowSize.height
                )
                .preferredColorScheme(.light)
                .ignoresSafeArea(.container, edges: .top)
                .background(WindowConfigurator())
        }
        .defaultSize(
            width: AdaLayout.defaultWindowSize.width,
            height: AdaLayout.defaultWindowSize.height
        )
        .windowStyle(.hiddenTitleBar)
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }
}
