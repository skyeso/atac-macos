import Carbon
import Foundation
import AtacCore

public final class HotKeyManager {
    public static let shared = HotKeyManager()

    public var onTrigger: (() -> Void)?

    private var eventHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {
        installHandlerIfNeeded()
    }

    deinit {
        unregister()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ -> OSStatus in
            guard let eventRef = eventRef else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            if status == noErr && hotKeyID.signature == OSType(0x41544143) {
                DispatchQueue.main.async {
                    HotKeyManager.shared.onTrigger?()
                }
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            nil,
            &eventHandlerRef
        )
    }

    public func apply(preset: HotKeyPreset) {
        unregister()

        let keyCode: UInt32
        let modifiers: UInt32

        switch preset {
        case .shiftCmdC:
            keyCode = UInt32(kVK_ANSI_C)
            modifiers = UInt32(cmdKey | shiftKey)
        case .optCmdC:
            keyCode = UInt32(kVK_ANSI_C)
            modifiers = UInt32(cmdKey | optionKey)
        case .shiftCmdV:
            keyCode = UInt32(kVK_ANSI_V)
            modifiers = UInt32(cmdKey | shiftKey)
        case .optCmdV:
            keyCode = UInt32(kVK_ANSI_V)
            modifiers = UInt32(cmdKey | optionKey)
        case .disabled:
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x41544143), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )
    }

    public func unregister() {
        if let ref = eventHotKeyRef {
            UnregisterEventHotKey(ref)
            eventHotKeyRef = nil
        }
    }
}
