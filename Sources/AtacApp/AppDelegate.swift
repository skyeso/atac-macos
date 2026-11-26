import AppKit
import AtacCore

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var panelController: HistoryPanelController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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

        HotKeyManager.shared.apply(preset: AppSettings.shared.hotKeyPreset)
        monitor.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        HotKeyManager.shared.unregister()
        store?.flushToDiskSynchronously()
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
