import AppKit
import OSLog
import ServiceManagement
import SwiftUI
import WidgetKit

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
private final class WeekPlanDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let frameName = "WeekPlanPanel"
    private let pinnedKey = "WeekPlanPinned"
    private let desktopCardKey = "WeekPlanShowsDesktopCard"
    private let minSize = NSSize(width: 430, height: 320)
    private let desktopLevel = NSWindow.Level(
        rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
    )
    private var panel: NSPanel!
    private var desktopCard: NSPanel!
    private var calendarWindow: NSWindow?
    private lazy var store = PlanStore(planDidChange: Self.publishWidgetSummary)
    private var statusItem: NSStatusItem!
    private var hideItem: NSMenuItem!
    private var pinItem: NSMenuItem!
    private var desktopCardItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private var pinned: Bool {
        get { UserDefaults.standard.bool(forKey: pinnedKey) }
        set { UserDefaults.standard.set(newValue, forKey: pinnedKey) }
    }

    private var desktopCardEnabled: Bool {
        get { UserDefaults.standard.object(forKey: desktopCardKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: desktopCardKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        createEditMenu()
        createPanel()
        createDesktopCard()
        createStatusItem()
        applyDesktopCardVisibility()
        showPanel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func application(
        _ application: NSApplication, continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.userInfo?[WidgetCenter.UserInfoKey.kind] as? String == WidgetSummary.kind else {
            return false
        }
        if panel != nil { showPanel() }
        return true
    }

    private static func publishWidgetSummary(_ plan: Plan) {
        guard WidgetSummary.isConfigured else { return }
        do {
            try plan.widgetSummary(at: .now).write()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSummary.kind)
        } catch {
            Logger(subsystem: WidgetSummary.storageDirectory, category: "Widget")
                .error("Could not update the local widget summary (\((error as NSError).domain, privacy: .public) \((error as NSError).code))")
        }
    }

    private func createPanel() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = NSSize(width: min(558, screen.width - 32), height: min(590, screen.height - 62))
        let frame = NSRect(x: screen.minX + 24, y: screen.maxY - size.height - 44,
                           width: size.width, height: size.height)
        panel = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable],
                        backing: .buffered, defer: false)
        panel.title = "周计划"
        panel.titleVisibility = .hidden
        panel.titlebarSeparatorStyle = .none
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isExcludedFromWindowsMenu = true
        panel.contentMinSize = minSize
        panel.contentView = NSHostingView(rootView: BoardView(store: store) { [weak self] date, choose in
            self?.showCalendar(around: date, choose: choose)
        })
        panel.delegate = self
        panel.setFrameUsingName(frameName)
        panel.setFrameAutosaveName(frameName)
    }

    private func createDesktopCard() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = NSSize(width: 330, height: 272)
        let horizontalOffset = min(386, max(20, screen.width - size.width - 42))
        let frame = NSRect(x: screen.minX + horizontalOffset, y: screen.maxY - size.height - 24,
                           width: size.width, height: size.height)
        desktopCard = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        desktopCard.title = "周计划桌面卡片"
        desktopCard.isOpaque = false
        desktopCard.backgroundColor = .clear
        desktopCard.hasShadow = true
        desktopCard.isMovableByWindowBackground = true
        desktopCard.isReleasedWhenClosed = false
        desktopCard.isExcludedFromWindowsMenu = true
        desktopCard.hidesOnDeactivate = false
        desktopCard.level = desktopLevel
        desktopCard.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        desktopCard.contentView = NSHostingView(rootView: DesktopPlanCard(store: store, open: showPanel))
        desktopCard.setFrameUsingName("WeekPlanDesktopCard")
        desktopCard.setFrameAutosaveName("WeekPlanDesktopCard")
    }

    private func showCalendar(around date: Date, choose: @escaping (Date) -> Void) {
        let window = calendarWindow ?? makeCalendarWindow()
        window.contentView = NSHostingView(rootView: MonthCalendarView(store: store, initialDate: date) { [weak self] day in
            self?.calendarWindow?.orderOut(nil)
            self?.showPanel()
            choose(day)
        })
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeCalendarWindow() -> NSWindow {
        let screen = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let frame = NSRect(x: 0, y: 0, width: min(960, screen.width - 32),
                           height: min(640, screen.height - 50))
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "周计划月历"
        window.contentMinSize = NSSize(width: 740, height: 480)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.center()
        window.setFrameUsingName("WeekPlanCalendar")
        window.setFrameAutosaveName("WeekPlanCalendar")
        calendarWindow = window
        return window
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
        let icon = NSImage(systemSymbolName: "calendar", accessibilityDescription: "周计划")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = "周计划"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(item("显示周计划", action: #selector(showPanel)))
        hideItem = item("隐藏周计划", action: #selector(hidePanel))
        menu.addItem(hideItem)
        pinItem = item("保持置顶", action: #selector(togglePinned))
        menu.addItem(pinItem)
        menu.addItem(.separator())
        desktopCardItem = item("显示桌面卡片", action: #selector(toggleDesktopCard))
        menu.addItem(desktopCardItem)
        loginItem = item("登录时打开", action: #selector(toggleLoginItem))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("退出周计划", action: #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        hideItem.isEnabled = panel.isVisible
        pinItem.state = pinned ? .on : .off
        desktopCardItem.state = desktopCardEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func windowDidBecomeKey(_ notification: Notification) {
        applyLevel()
    }

    func windowDidResignKey(_ notification: Notification) {
        applyLevel()
    }

    private func applyLevel() {
        panel.level = pinned ? .floating : (desktopCardEnabled || panel.isKeyWindow ? .normal : desktopLevel)
    }

    private func applyDesktopCardVisibility() {
        if desktopCardEnabled {
            panel.collectionBehavior = [.moveToActiveSpace, .ignoresCycle]
            desktopCard.orderFrontRegardless()
        } else {
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            desktopCard.orderOut(nil)
        }
        applyLevel()
    }

    @objc private func showPanel() {
        panel.level = pinned ? .floating : .normal
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func hidePanel() {
        panel.orderOut(nil)
    }

    @objc private func togglePinned() {
        pinned.toggle()
        if pinned { showPanel() }
        applyLevel()
    }

    @objc private func toggleDesktopCard() {
        desktopCardEnabled.toggle()
        applyDesktopCardVisibility()
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
