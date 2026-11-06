import AppKit

@MainActor
enum MarkdownWrap {
    static func toggle(in textView: NSTextView, marker: String) {
        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let markerLen = (marker as NSString).length

        if selectedRange.length == 0 {
            let combined = marker + marker
            guard textView.shouldChangeText(in: selectedRange, replacementString: combined) else { return }
            textView.textStorage?.replaceCharacters(in: selectedRange, with: combined)
            textView.didChangeText()
            let newCursor = selectedRange.location + markerLen
            textView.setSelectedRange(NSRange(location: newCursor, length: 0))
            return
        }

        let selectedText = nsString.substring(with: selectedRange)
        let totalLen = (selectedText as NSString).length

        if totalLen >= 2 * markerLen,
           selectedText.hasPrefix(marker),
           selectedText.hasSuffix(marker) {
            let inner = (selectedText as NSString).substring(with: NSRange(
                location: markerLen,
                length: totalLen - 2 * markerLen
            ))
            guard textView.shouldChangeText(in: selectedRange, replacementString: inner) else { return }
            textView.textStorage?.replaceCharacters(in: selectedRange, with: inner)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(
                location: selectedRange.location,
                length: (inner as NSString).length
            ))
            return
        }

        let wrapped = marker + selectedText + marker
        guard textView.shouldChangeText(in: selectedRange, replacementString: wrapped) else { return }
        textView.textStorage?.replaceCharacters(in: selectedRange, with: wrapped)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(
            location: selectedRange.location + markerLen,
            length: (selectedText as NSString).length
        ))
    }
}
