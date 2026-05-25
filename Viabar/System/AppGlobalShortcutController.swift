import Carbon
import Foundation

enum AppShortcutCommand: UInt32 {
    case toggleMainPanel = 1
    case openSearch = 2
}

enum AppGlobalShortcutError: Error {
    case duplicateCombination
    case unsupportedCombination(String)
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
}

@MainActor
final class AppGlobalShortcutController {
    var onCommand: ((AppShortcutCommand) -> Void)?

    private let signature = OSType(0x5642_4152) // VBAR
    private var eventHandler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private var activeConfiguration: AppShortcutConfiguration?

    deinit {
        registrations.forEach { UnregisterEventHotKey($0) }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func reconfigure(_ configuration: AppShortcutConfiguration) throws {
        guard configuration.isValid else {
            throw AppGlobalShortcutError.duplicateCombination
        }
        guard configuration != activeConfiguration else { return }
        try installEventHandlerIfNeeded()

        let previousConfiguration = activeConfiguration
        unregisterActiveShortcuts()

        do {
            registrations = try registrations(for: configuration)
            activeConfiguration = configuration
        } catch {
            if let previousConfiguration {
                registrations = (try? registrations(for: previousConfiguration)) ?? []
                activeConfiguration = registrations.isEmpty ? nil : previousConfiguration
            }
            throw error
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr,
                      let command = AppShortcutCommand(rawValue: hotKeyID.id)
                else { return OSStatus(eventNotHandledErr) }

                let controller = Unmanaged<AppGlobalShortcutController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    controller.onCommand?(command)
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandler
        )
        guard status == noErr, eventHandler != nil else {
            throw AppGlobalShortcutError.handlerInstallationFailed(status)
        }
    }

    private func registrations(for configuration: AppShortcutConfiguration) throws -> [EventHotKeyRef] {
        var newRegistrations: [EventHotKeyRef] = []

        do {
            newRegistrations.append(
                try register(configuration.toggleMainPanel, command: .toggleMainPanel)
            )
            newRegistrations.append(
                try register(configuration.openSearch, command: .openSearch)
            )
            return newRegistrations
        } catch {
            newRegistrations.forEach { UnregisterEventHotKey($0) }
            throw error
        }
    }

    private func register(_ storedValue: String, command: AppShortcutCommand) throws -> EventHotKeyRef {
        guard let shortcut = CarbonShortcut(storedValue: storedValue) else {
            throw AppGlobalShortcutError.unsupportedCombination(storedValue)
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: command.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw AppGlobalShortcutError.registrationFailed(status)
        }
        return hotKeyRef
    }

    private func unregisterActiveShortcuts() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations = []
        activeConfiguration = nil
    }
}

private struct CarbonShortcut {
    let keyCode: UInt32
    let modifierFlags: UInt32

    init?(storedValue: String) {
        let components = storedValue.split(separator: "+").map(String.init)
        guard let keyName = components.last,
              let keyCode = Self.keyCodes[keyName.uppercased()]
        else { return nil }

        let flags = components.dropLast().reduce(UInt32(0)) { result, modifier in
            switch modifier {
            case "Control": result | UInt32(controlKey)
            case "Option": result | UInt32(optionKey)
            case "Shift": result | UInt32(shiftKey)
            case "Command": result | UInt32(cmdKey)
            default: result
            }
        }
        guard flags != 0 else { return nil }
        self.keyCode = keyCode
        self.modifierFlags = flags
    }

    private static let keyCodes: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9), "SPACE": UInt32(kVK_Space),
        "RETURN": UInt32(kVK_Return), "TAB": UInt32(kVK_Tab),
        "DELETE": UInt32(kVK_Delete), "UP": UInt32(kVK_UpArrow),
        "DOWN": UInt32(kVK_DownArrow), "LEFT": UInt32(kVK_LeftArrow),
        "RIGHT": UInt32(kVK_RightArrow),
    ]
}
