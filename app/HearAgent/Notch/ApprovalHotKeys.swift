import Carbon.HIToolbox
import Foundation

/// ⌘Y, ⇧⌘Y and ⌘N as system-wide hotkeys, so a waiting approval can be answered
/// from any app. Registered only while the notch is open with a request waiting;
/// the rest of the time those keys belong to the frontmost app.
final class ApprovalHotKeys: @unchecked Sendable {
    enum Key: UInt32 {
        case allow = 1, alwaysAllow, deny
    }

    /// Called on the main thread.
    var onPress: ((Key) -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4841_4774 // "HAGt"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == ApprovalHotKeys.signature, let key = Key(rawValue: id.id) else {
                return OSStatus(eventNotHandledErr)
            }
            let me = Unmanaged<ApprovalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { me.onPress?(key) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    var isRegistered: Bool { !refs.isEmpty }

    func register() {
        guard refs.isEmpty else { return }
        let keys: [(Key, Int, Int)] = [
            (.allow, kVK_ANSI_Y, cmdKey),
            (.alwaysAllow, kVK_ANSI_Y, cmdKey | shiftKey),
            (.deny, kVK_ANSI_N, cmdKey),
        ]
        for (key, code, modifiers) in keys {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: key.rawValue)
            if RegisterEventHotKey(UInt32(code), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
}
