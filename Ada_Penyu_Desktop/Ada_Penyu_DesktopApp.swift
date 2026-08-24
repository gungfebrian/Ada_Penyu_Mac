//
//  Ada_Penyu_DesktopApp.swift
//  Ada_Penyu_Desktop
//
//  Created by Gung  on 24/08/26.
//

import SwiftUI

@main
struct Ada_Penyu_DesktopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: AdaLayout.minimumWindowSize.width,
                    minHeight: AdaLayout.minimumWindowSize.height
                )
        }
        .defaultSize(
            width: AdaLayout.defaultWindowSize.width,
            height: AdaLayout.defaultWindowSize.height
        )
    }
}
