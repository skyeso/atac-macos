import AppKit
import AtacCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showPanelNotification = Notification.Name("com.eso.atac.showPanel")

    private var statusItem: NSStatusItem!
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var panelController: HistoryPanelController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupEditMainMenu()

        store = HistoryStore()
        monitor = ClipboardMonitor(store: store, settings: .shared)
        panelController = HistoryPanelController(store: store, monitor: monitor)

        SettingsMenuHandler.shared.store = store
        SettingsMenuHandler.shared.monitor = monitor
        SettingsMenuHandler.shared.onRequestClearConfirmation = { [weak self] includePinned in
            self?.confirmAndClear(includePinned: includePinned)
        }

        setupStatusBarItem()
        setupCallbacks()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleExternalOpenRequest),
            name: Self.showPanelNotification,
            object: nil
        )

        HotKeyManager.shared.apply(preset: AppSettings.shared.hotKeyPreset)
        ensureLoginItemRegisteredFromApplications()
        monitor.start()
    }

    private func ensureLoginItemRegisteredFromApplications() {
        // Only auto-register in Login Items when running from /Applications/Ataç.app
        // so macOS System Settings -> Login Items always displays the native Ataç app icon.
        guard Bundle.main.bundlePath == "/Applications/Ataç.app" else { return }
        let initKey = "com.eso.atac.loginItemInitialized"
        if UserDefaults.standard.object(forKey: initKey) == nil {
            UserDefaults.standard.set(true, forKey: initKey)
            _ = AppSettings.shared.setLaunchAtLogin(true)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Launching Ataç from Spotlight or /Applications while already running opens the clipboard popup
        panelController?.open(anchorButton: statusItem?.button)
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        monitor?.stop()
        HotKeyManager.shared.unregister()
        store?.flushToDiskSynchronously()
    }

    @objc private func handleExternalOpenRequest() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.panelController?.open(anchorButton: self.statusItem?.button)
        }
    }

    private func setupEditMainMenu() {
        // Enables Cmd+A / Cmd+V / Cmd+X / Cmd+Z in the search field and Cmd+Q when active
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Ataç'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Düzen")
        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Yinele", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(statusBarClicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        updateStatusBarAppearance()
    }

    private func updateStatusBarAppearance() {
        guard let button = statusItem?.button else { return }
        let settings = AppSettings.shared
        let symbolName = settings.statusBarIcon.rawValue

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Ataç Pano Geçmişi") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let configured = img.withSymbolConfiguration(config) ?? img
            configured.isTemplate = true
            button.image = configured
        } else {
            button.title = "📎"
        }

        button.appearsDisabled = settings.isPaused
        let shortcutHint = settings.hotKeyPreset.shortBadge
        if settings.isPaused {
            button.toolTip = "Ataç — Kopyalama Takibi Duraklatıldı"
        } else if !shortcutHint.isEmpty {
            button.toolTip = "Ataç — Kopyalama Geçmişi (\(shortcutHint))"
        } else {
            button.toolTip = "Ataç — Kopyalama Geçmişi"
        }
    }

    private func setupCallbacks() {
        store.onItemsChanged = { [weak self] in
            self?.panelController.refreshIfVisible()
        }

        AppSettings.shared.onChange = { [weak self] in
            guard let self = self else { return }
            self.monitor.reconfigure()
            HotKeyManager.shared.apply(preset: AppSettings.shared.hotKeyPreset)
            self.updateStatusBarAppearance()
            self.panelController.refreshIfVisible()
        }

        HotKeyManager.shared.onTrigger = { [weak self] in
            guard let self = self else { return }
            self.panelController.toggleFromHotKey(anchorButton: self.statusItem.button)
        }

        panelController.onVisibilityChanged = { [weak self] visible in
            self?.statusItem?.button?.highlight(visible)
        }
    }

    @objc private func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            panelController.toggleFromStatusBar(anchorButton: sender)
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            if panelController.isVisible {
                panelController.close(restoreFocus: false)
            }
            let quickMenu = SettingsMenuHandler.shared.buildMenu(includeQuickHeader: true)
            statusItem.menu = quickMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            panelController.toggleFromStatusBar(anchorButton: sender)
        }
    }

    private func confirmAndClear(includePinned: Bool) {
        store.clear(includingPinned: includePinned)
        panelController.refreshIfVisible()
    }
}
