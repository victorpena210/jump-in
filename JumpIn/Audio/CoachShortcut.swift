import Carbon

/// Carbon hot keys work while the meeting app is frontmost without keyboard monitoring.
final class CoachShortcut {
    private var handler: EventHandlerRef?
    private var askKey: EventHotKeyRef?
    private var cancelKey: EventHotKeyRef?
    private let action: @MainActor (Bool) -> Void
    private(set) var registered = false

    init(action: @escaping @MainActor (Bool) -> Void) {
        self.action = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, numericCast(MemoryLayout<EventHotKeyID>.size), nil, &identifier)
            guard result == noErr else { return result }
            let shortcut = Unmanaged<CoachShortcut>.fromOpaque(context).takeUnretainedValue()
            let callback = shortcut.action
            let cancel = identifier.id == 2
            Task { @MainActor in callback(cancel) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return }
        let modifiers = UInt32(controlKey | optionKey)
        let ask = RegisterEventHotKey(UInt32(kVK_Space), modifiers, EventHotKeyID(signature: 0x4A554D50, id: 1),
                                      GetApplicationEventTarget(), 0, &askKey)
        let cancel = RegisterEventHotKey(UInt32(kVK_Escape), modifiers, EventHotKeyID(signature: 0x4A554D50, id: 2),
                                         GetApplicationEventTarget(), 0, &cancelKey)
        registered = ask == noErr && cancel == noErr
    }
    deinit {
        if let askKey { UnregisterEventHotKey(askKey) }
        if let cancelKey { UnregisterEventHotKey(cancelKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
