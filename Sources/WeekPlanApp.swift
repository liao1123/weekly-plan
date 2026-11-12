import AppKit
import ServiceManagement
import SwiftUI

@main
@MainActor
struct WeekPlanApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WeekPlanDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class WeekPlanDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let frameName = "WeekPlanPanel"
    private let pinnedKey = "WeekPlanPinned"
    private let minSize = NSSize(width: 430, height: 320)
    private var mainWindow: NSWindow!
    private lazy var store = PlanStore()
    private var statusItem: NSStatusItem!
    private var hideItem: NSMenuItem!
    private var pinItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var pinned: Bool {
        get { UserDefaults.standard.bool(forKey: pinnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pinnedKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createEditMenu()
        createMainWindow()
        createStatusItem()
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    private func createMainWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = NSSize(width: min(558, screen.width - 32), height: min(590, screen.height - 62))
        let frame = NSRect(x: screen.minX + 24, y: screen.maxY - size.height - 44,
                           width: size.width, height: size.height)
        mainWindow = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        mainWindow.title = "周计划"
        mainWindow.titleVisibility = .hidden
        mainWindow.titlebarSeparatorStyle = .none
        mainWindow.isReleasedWhenClosed = false
        mainWindow.isExcludedFromWindowsMenu = true
        mainWindow.level = pinned ? .floating : .normal
        mainWindow.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
        mainWindow.contentMinSize = minSize
        mainWindow.contentView = NSHostingView(rootView: BoardView(store: store))
        mainWindow.setFrameUsingName(frameName)
        mainWindow.setFrameAutosaveName(frameName)
    }

    private func createEditMenu() {
        let mainMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出周计划", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let icon = NSImage(systemSymbolName: "calendar", accessibilityDescription: "周计划")
        icon?.isTemplate = true
        button.image = icon
        button.toolTip = "周计划（左键打开，右键显示菜单）"
        button.target = self
        button.action = #selector(showMainWindow)

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(item("显示周计划", action: #selector(showMainWindow)))
        hideItem = item("隐藏周计划", action: #selector(hideMainWindow))
        menu.addItem(hideItem)
        pinItem = item("保持置顶", action: #selector(togglePinned))
        menu.addItem(pinItem)
        menu.addItem(.separator())
        loginItem = item("登录时打开", action: #selector(toggleLoginItem))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("退出周计划", action: #selector(quit)))
        button.menu = menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        hideItem.isEnabled = mainWindow.isVisible
        pinItem.state = pinned ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func showMainWindow() {
        guard let mainWindow else { return }
        NSApp.activate()
        mainWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func hideMainWindow() {
        mainWindow.orderOut(nil)
    }

    @objc private func togglePinned() {
        pinned.toggle()
        mainWindow.level = pinned ? .floating : .normal
        if pinned { showMainWindow() }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            default:
                try service.register()
            }
        } catch {
            NSApp.activate()
            let alert = NSAlert(error: error)
            alert.messageText = "无法设置登录时打开"
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
