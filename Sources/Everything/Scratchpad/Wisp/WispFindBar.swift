import SwiftUI
import AppKit
import Carbon.HIToolbox

struct FindBar: View {
    let theme: WispTheme
    @Binding var query: String
    let matchCount: Int
    let currentIndex: Int
    let onNext: () -> Void
    let onPrev: () -> Void
    let onClose: () -> Void

    @FocusState private var focused: Bool
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            TextField("Find", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .frame(width: 160)

            Text(countLabel)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(minWidth: 58, alignment: .trailing)

            Divider().frame(height: 16)

            iconButton("chevron.up", help: "Previous (⇧↵)", action: onPrev)
                .disabled(matchCount == 0)
            iconButton("chevron.down", help: "Next (↵)", action: onNext)
                .disabled(matchCount == 0)
            iconButton("xmark", help: "Close (Esc)", action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(barFill)
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.18), radius: 14, y: 4)
        )
        .onAppear {
            startListening()
            DispatchQueue.main.async { focused = true }
        }
        .onDisappear { stopListening() }
    }

    private var countLabel: String {
        if query.isEmpty { return "" }
        if matchCount == 0 { return "none" }
        return "\(currentIndex)/\(matchCount)"
    }

    private var barFill: Color {
        theme == .dark ? Color(white: 0.16) : Color(white: 0.99)
    }

    private var borderColor: Color {
        theme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
    }

    @ViewBuilder
    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .pointerCursor()
        .help(help)
        .accessibilityLabel(help)
    }

    private static func fieldHasFocus() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        return responder.isFieldEditor
    }

    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.fieldHasFocus() else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                onClose()
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if event.modifierFlags.contains(.shift) { onPrev() } else { onNext() }
                return nil
            default:
                return event
            }
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
