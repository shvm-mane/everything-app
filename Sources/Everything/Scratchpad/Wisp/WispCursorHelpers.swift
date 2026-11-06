import SwiftUI
import AppKit

extension View {
    func pointerCursor() -> some View {
        self
            .onContinuousHover { phase in
                if case .active = phase {
                    NSCursor.pointingHand.set()
                }
            }
            .onHover { hovering in
                if !hovering {
                    NSCursor.arrow.set()
                }
            }
    }

    func arrowCursor() -> some View {
        self.onContinuousHover { phase in
            if case .active = phase {
                NSCursor.arrow.set()
            }
        }
    }
}
