import SwiftUI
import Foundation

extension Notification.Name {
    static let statsDidUpdate = Notification.Name("statsDidUpdate")
}

@main
struct GovorunApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Пустая сцена — всё управление через AppDelegate и NSStatusItem
        Settings { EmptyView() }
    }
}
