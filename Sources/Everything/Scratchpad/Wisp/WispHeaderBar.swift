import SwiftUI

struct HeaderBar: View {
    let headings: [Heading]
    let onJump: (Heading) -> Void

    var body: some View {
        if headings.isEmpty {
            // Nothing to show — keep the slot empty so the panel just looks
            // like before the headings feature existed.
            EmptyView()
        } else {
            // Everything: centred while they fit, scrolling once they do not;
            // the words sit 4 pt lower in the same strip.
            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(headings.enumerated()), id: \.element.id) { index, heading in
                            if index > 0 {
                                Text("·")
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 10)
                            }
                            QuietButton(action: { onJump(heading) }, help: "Jump to “\(heading.name)”") {
                                Text(heading.name)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .leading)
                }
            }
            // Everything: a slim strip, the words left-aligned with equal air above and below.
            .frame(height: 16)
            .padding(.vertical, 3)
            .font(.system(size: 10, weight: .regular))
            .foregroundStyle(.tertiary)
        }
    }
}
