import Foundation
import ServiceManagement

public enum HotKeyPreset: String, CaseIterable, Codable {
    case shiftCmdC = "shift_cmd_c"
    case optCmdC = "opt_cmd_c"
    case shiftCmdV = "shift_cmd_v"
    case optCmdV = "opt_cmd_v"
    case disabled = "disabled"

    public var displayTitle: String {
        switch self {
        case .shiftCmdC: return "⇧⌘C (Maccy Varsayılanı)"
        case .optCmdC: return "⌥⌘C"
        case .shiftCmdV: return "⇧⌘V"
        case .optCmdV: return "⌥⌘V"
        case .disabled: return "Kapalı"
        }
    }

    public var shortBadge: String {
        switch self {
        case .shiftCmdC: return "⇧⌘C"
        case .optCmdC: return "⌥⌘C"
        case .shiftCmdV: return "⇧⌘V"
        case .optCmdV: return "⌥⌘V"
        case .disabled: return ""
        }
    }
}

public enum StatusBarIconPreset: String, CaseIterable, Codable {
    case paperclip = "paperclip"
    case clipboard = "doc.on.clipboard"
    case listClipboard = "list.clipboard"
    case scissors = "scissors"

    public var displayTitle: String {
        switch self {
        case .paperclip: return "Ataç"
        case .clipboard: return "Pano"
        case .listClipboard: return "Liste"
        case .scissors: return "Makas"
        }
    }
}

public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private let keyPrefix = "com.atac.settings."

    public var onChange: (() -> Void)?

    // Cached values in RAM so timer polling never queries UserDefaults
    public private(set) var maxHistoryCount: Int
    public private(set) var pollIntervalMs: Int
    public private(set) var isPaused: Bool
    public private(set) var autoPasteOnSelect: Bool
    public private(set) var openFilesOnSelect: Bool
    public private(set) var captureImages: Bool
    public private(set) var ignoreConcealed: Bool
    public private(set) var hotKeyPreset: HotKeyPreset
    public private(set) var statusBarIcon: StatusBarIconPreset

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedMax = defaults.integer(forKey: keyPrefix + "maxHistoryCount")
        self.maxHistoryCount = storedMax > 0 ? storedMax : 150

        let storedPoll = defaults.integer(forKey: keyPrefix + "pollIntervalMs")
        self.pollIntervalMs = storedPoll >= 200 ? storedPoll : 600

        self.isPaused = defaults.bool(forKey: keyPrefix + "isPaused")

        if defaults.object(forKey: keyPrefix + "autoPasteOnSelect") != nil {
            self.autoPasteOnSelect = defaults.bool(forKey: keyPrefix + "autoPasteOnSelect")
        } else {
            self.autoPasteOnSelect = false
        }

        if defaults.object(forKey: keyPrefix + "openFilesOnSelect") != nil {
            self.openFilesOnSelect = defaults.bool(forKey: keyPrefix + "openFilesOnSelect")
        } else {
            self.openFilesOnSelect = true
        }

        if defaults.object(forKey: keyPrefix + "captureImages") != nil {
            self.captureImages = defaults.bool(forKey: keyPrefix + "captureImages")
        } else {
            self.captureImages = true
        }

        if defaults.object(forKey: keyPrefix + "ignoreConcealed") != nil {
            self.ignoreConcealed = defaults.bool(forKey: keyPrefix + "ignoreConcealed")
        } else {
            self.ignoreConcealed = true
        }

        if let rawHotKey = defaults.string(forKey: keyPrefix + "hotKeyPreset"),
           let preset = HotKeyPreset(rawValue: rawHotKey) {
            self.hotKeyPreset = preset
        } else {
            self.hotKeyPreset = .shiftCmdC
        }

        if let rawIcon = defaults.string(forKey: keyPrefix + "statusBarIcon"),
           let icon = StatusBarIconPreset(rawValue: rawIcon) {
            self.statusBarIcon = icon
        } else {
            self.statusBarIcon = .paperclip
        }
    }

    public func setMaxHistoryCount(_ value: Int) {
        let clamped = max(10, min(1000, value))
        guard maxHistoryCount != clamped else { return }
        maxHistoryCount = clamped
        defaults.set(clamped, forKey: keyPrefix + "maxHistoryCount")
        onChange?()
    }

    public func setPollIntervalMs(_ value: Int) {
        let clamped = max(250, min(3000, value))
        guard pollIntervalMs != clamped else { return }
        pollIntervalMs = clamped
        defaults.set(clamped, forKey: keyPrefix + "pollIntervalMs")
        onChange?()
    }

    public func setPaused(_ value: Bool) {
        guard isPaused != value else { return }
        isPaused = value
        defaults.set(value, forKey: keyPrefix + "isPaused")
        onChange?()
    }

    public func setAutoPasteOnSelect(_ value: Bool) {
        guard autoPasteOnSelect != value else { return }
        autoPasteOnSelect = value
        defaults.set(value, forKey: keyPrefix + "autoPasteOnSelect")
        onChange?()
    }

    public func setOpenFilesOnSelect(_ value: Bool) {
        guard openFilesOnSelect != value else { return }
        openFilesOnSelect = value
        defaults.set(value, forKey: keyPrefix + "openFilesOnSelect")
        onChange?()
    }

    public func setCaptureImages(_ value: Bool) {
        guard captureImages != value else { return }
        captureImages = value
        defaults.set(value, forKey: keyPrefix + "captureImages")
        onChange?()
    }

    public func setIgnoreConcealed(_ value: Bool) {
        guard ignoreConcealed != value else { return }
        ignoreConcealed = value
        defaults.set(value, forKey: keyPrefix + "ignoreConcealed")
        onChange?()
    }

    public func setHotKeyPreset(_ value: HotKeyPreset) {
        guard hotKeyPreset != value else { return }
        hotKeyPreset = value
        defaults.set(value.rawValue, forKey: keyPrefix + "hotKeyPreset")
        onChange?()
    }

    public func setStatusBarIcon(_ value: StatusBarIconPreset) {
        guard statusBarIcon != value else { return }
        statusBarIcon = value
        defaults.set(value.rawValue, forKey: keyPrefix + "statusBarIcon")
        onChange?()
    }

    public var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            onChange?()
            return true
        } catch {
            return false
        }
    }
}
