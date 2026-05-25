import AppKit
import SwiftUI

struct ShortcutRecorderField: View {
    let accessibilityTitle: LocalizedStringKey
    let value: String
    @Binding var isRecording: Bool
    let onRecord: (String) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(
                    isRecording ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.7),
                    lineWidth: isRecording ? 1.5 : 1
                )

            if isRecording {
                Text("请按键...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
            } else {
                Text(ShortcutKeyCombination.displayString(for: value))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 7)
            }
        }
        .frame(width: 88, height: 22)
        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .background {
            ShortcutRecorderBridge(isRecording: $isRecording, onRecord: onRecord)
        }
        .onTapGesture {
            isRecording = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(
            isRecording
                ? Text("正在录制快捷键")
                : Text(ShortcutKeyCombination.displayString(for: value))
        )
        .accessibilityAddTraits(.isButton)
    }
}

private struct ShortcutRecorderBridge: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecord: (String) -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView()
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.isRecording = isRecording
        view.onRecord = { storedValue in
            onRecord(storedValue)
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }

        if isRecording, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }

    final class RecorderView: NSView {
        var isRecording = false
        var onRecord: ((String) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            if event.keyCode == 53 {
                onCancel?()
                return
            }

            guard let combination = event.shortcutCombination else { return }
            onRecord?(combination.storedValue)
        }
    }
}

private extension NSEvent {
    var shortcutCombination: ShortcutKeyCombination? {
        let modifiers: [ShortcutKeyCombination.Modifier] = [
            modifierFlags.contains(.control) ? .control : nil,
            modifierFlags.contains(.option) ? .option : nil,
            modifierFlags.contains(.shift) ? .shift : nil,
            modifierFlags.contains(.command) ? .command : nil,
        ].compactMap { $0 }

        let key: ShortcutKeyCombination.Key?
        switch keyCode {
        case 36, 76:
            key = .return
        case 48:
            key = .tab
        case 49:
            key = .space
        case 51, 117:
            key = .delete
        case 123:
            key = .left
        case 124:
            key = .right
        case 125:
            key = .down
        case 126:
            key = .up
        case 53:
            key = .escape
        default:
            key = charactersIgnoringModifiers.flatMap {
                $0.count == 1 ? .character($0) : nil
            }
        }

        guard let key else { return nil }
        return ShortcutKeyCombination(modifiers: modifiers, key: key)
    }
}
