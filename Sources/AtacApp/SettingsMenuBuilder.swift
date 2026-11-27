import AppKit
import AtacCore

final class SettingsMenuHandler: NSObject {
    static let shared = SettingsMenuHandler()

    var store: HistoryStore?
    var monitor: ClipboardMonitor?
    var onRequestClearConfirmation: ((Bool) -> Void)?

    func buildMenu(includeQuickHeader: Bool) -> NSMenu {
        let menu = NSMenu(title: "Ataç Ayarları")
        let settings = AppSettings.shared

        if includeQuickHeader {
            let count = store?.items.count ?? 0
            let header = NSMenuItem(title: "Ataç — \(count) kayıtlı öğe", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        // Pause toggle
        let pauseItem = NSMenuItem(
            title: "Kopyalama Takibini Duraklat",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        pauseItem.state = settings.isPaused ? .on : .off
        menu.addItem(pauseItem)

        // Open files directly on click toggle
        let openFilesItem = NSMenuItem(
            title: "Dosyalara Tıklayınca Doğrudan Aç",
            action: #selector(toggleOpenFilesOnSelect),
            keyEquivalent: ""
        )
        openFilesItem.target = self
        openFilesItem.state = settings.openFilesOnSelect ? .on : .off
        menu.addItem(openFilesItem)

        // Auto-paste toggle
        let autoPasteItem = NSMenuItem(
            title: "Seçilince Otomatik Yapıştır (⌘V)",
            action: #selector(toggleAutoPaste),
            keyEquivalent: ""
        )
        autoPasteItem.target = self
        autoPasteItem.state = settings.autoPasteOnSelect ? .on : .off
        menu.addItem(autoPasteItem)

        // Capture images toggle
        let imagesItem = NSMenuItem(
            title: "Görselleri Kaydet (Diskte Sıkıştırılmış)",
            action: #selector(toggleCaptureImages),
            keyEquivalent: ""
        )
        imagesItem.target = self
        imagesItem.state = settings.captureImages ? .on : .off
        menu.addItem(imagesItem)

        // Ignore password managers toggle
        let privacyItem = NSMenuItem(
            title: "Şifre Yöneticilerini Yoksay (Gizli Kopyalar)",
            action: #selector(toggleIgnoreConcealed),
            keyEquivalent: ""
        )
        privacyItem.target = self
        privacyItem.state = settings.ignoreConcealed ? .on : .off
        menu.addItem(privacyItem)

        menu.addItem(.separator())

        // Max history count submenu
        let limitSubmenu = NSMenu(title: "Geçmiş Limiti")
        for count in [50, 100, 150, 300, 500] {
            let item = NSMenuItem(title: "\(count) Öğe", action: #selector(selectMaxCount(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            item.state = (settings.maxHistoryCount == count) ? .on : .off
            limitSubmenu.addItem(item)
        }
        let limitRoot = NSMenuItem(title: "Maksimum Geçmiş (\(settings.maxHistoryCount))", action: nil, keyEquivalent: "")
        limitRoot.submenu = limitSubmenu
        menu.addItem(limitRoot)

        // Power / polling mode submenu
        let pollSubmenu = NSMenu(title: "Güç ve Kontrol Sıklığı")
        let pollInfo = NSMenuItem(title: "Yeni kopyaları ne sıklıkla kontrol edeceğini belirler", action: nil, keyEquivalent: "")
        pollInfo.isEnabled = false
        pollSubmenu.addItem(pollInfo)
        pollSubmenu.addItem(.separator())

        let pollOptions: [(Int, String)] = [
            (300, "Hızlı — Anında Yakala (0.3 sn)"),
            (600, "Dengeli — Önerilen (0.6 sn)"),
            (1200, "Ultra Pil Tasarrufu (1.2 sn)")
        ]
        for (ms, label) in pollOptions {
            let item = NSMenuItem(title: label, action: #selector(selectPollInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = ms
            item.state = (settings.pollIntervalMs == ms) ? .on : .off
            pollSubmenu.addItem(item)
        }
        let pollRoot = NSMenuItem(title: "Güç Modu", action: nil, keyEquivalent: "")
        pollRoot.submenu = pollSubmenu
        menu.addItem(pollRoot)

        // Global shortcut submenu
        let hotKeySubmenu = NSMenu(title: "Kısayol Tuşu")
        let hotKeyInfo = NSMenuItem(title: "Fareye dokunmadan her yerden Ataç penceresini açar", action: nil, keyEquivalent: "")
        hotKeyInfo.isEnabled = false
        hotKeySubmenu.addItem(hotKeyInfo)
        hotKeySubmenu.addItem(.separator())

        for preset in HotKeyPreset.allCases {
            let item = NSMenuItem(title: preset.displayTitle, action: #selector(selectHotKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (settings.hotKeyPreset == preset) ? .on : .off
            hotKeySubmenu.addItem(item)
        }
        let hotKeyRoot = NSMenuItem(title: "Genel Kısayol (\(settings.hotKeyPreset.shortBadge.isEmpty ? "Kapalı" : settings.hotKeyPreset.shortBadge))", action: nil, keyEquivalent: "")
        hotKeyRoot.submenu = hotKeySubmenu
        menu.addItem(hotKeyRoot)

        // Status bar icon submenu
        let iconSubmenu = NSMenu(title: "Üst Bar İkonu")
        for icon in StatusBarIconPreset.allCases {
            let item = NSMenuItem(title: icon.displayTitle, action: #selector(selectIcon(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = icon.rawValue
            if let img = NSImage(systemSymbolName: icon.rawValue, accessibilityDescription: icon.displayTitle) {
                img.isTemplate = true
                item.image = img
            }
            item.state = (settings.statusBarIcon == icon) ? .on : .off
            iconSubmenu.addItem(item)
        }
        let iconRoot = NSMenuItem(title: "Üst Bar İkonu", action: nil, keyEquivalent: "")
        iconRoot.submenu = iconSubmenu
        menu.addItem(iconRoot)

        // Launch at login
        let loginItem = NSMenuItem(
            title: "Mac Açıldığında Başlat",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = settings.launchAtLoginEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let clearUnpinned = NSMenuItem(
            title: "Sabitlenmeyen Geçmişi Temizle",
            action: #selector(clearUnpinnedHistory),
            keyEquivalent: ""
        )
        clearUnpinned.target = self
        menu.addItem(clearUnpinned)

        let clearAll = NSMenuItem(
            title: "Tüm Geçmişi Sıfırla (Sabitler Dahil)",
            action: #selector(clearAllHistory),
            keyEquivalent: ""
        )
        clearAll.target = self
        menu.addItem(clearAll)

        if includeQuickHeader {
            menu.addItem(.separator())
            let quitItem = NSMenuItem(title: "Ataç'tan Çık", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.target = self
            menu.addItem(quitItem)
        }

        return menu
    }

    @objc private func togglePause() {
        let settings = AppSettings.shared
        settings.setPaused(!settings.isPaused)
    }

    @objc private func toggleOpenFilesOnSelect() {
        let settings = AppSettings.shared
        settings.setOpenFilesOnSelect(!settings.openFilesOnSelect)
    }

    @objc private func toggleAutoPaste() {
        let settings = AppSettings.shared
        let next = !settings.autoPasteOnSelect
        if next && !ClipboardMonitor.isAccessibilityTrusted(prompt: false) {
            _ = ClipboardMonitor.isAccessibilityTrusted(prompt: true)
        }
        settings.setAutoPasteOnSelect(next)
    }

    @objc private func toggleCaptureImages() {
        let settings = AppSettings.shared
        settings.setCaptureImages(!settings.captureImages)
    }

    @objc private func toggleIgnoreConcealed() {
        let settings = AppSettings.shared
        settings.setIgnoreConcealed(!settings.ignoreConcealed)
    }

    @objc private func selectMaxCount(_ sender: NSMenuItem) {
        AppSettings.shared.setMaxHistoryCount(sender.tag)
    }

    @objc private func selectPollInterval(_ sender: NSMenuItem) {
        AppSettings.shared.setPollIntervalMs(sender.tag)
    }

    @objc private func selectHotKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = HotKeyPreset(rawValue: raw) else { return }
        AppSettings.shared.setHotKeyPreset(preset)
    }

    @objc private func selectIcon(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = StatusBarIconPreset(rawValue: raw) else { return }
        AppSettings.shared.setStatusBarIcon(preset)
    }

    @objc private func toggleLaunchAtLogin() {
        let settings = AppSettings.shared
        settings.setLaunchAtLogin(!settings.launchAtLoginEnabled)
    }

    @objc private func clearUnpinnedHistory() {
        onRequestClearConfirmation?(false)
    }

    @objc private func clearAllHistory() {
        onRequestClearConfirmation?(true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
