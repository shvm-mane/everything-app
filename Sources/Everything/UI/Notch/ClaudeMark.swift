// SPDX-License-Identifier: GPL-3.0-or-later
// Claude's mark, drawn from its 100×100 symbol, for the island's Claude button.

import AppKit
import SwiftUI

struct ClaudeMark: Shape {
    /// Claude's orange, hsl(14.8, 63.1%, 59.6%).
    static let tint = Color(red: 0.851, green: 0.467, blue: 0.341)

    /// Absolute commands in a 100×100 box: m x,y · l x,y · c x1,y1,x2,y2,x,y · Z.
    private static let commands = "m,19.6,66.5 l,39.3,55.5 l,39.6,54.5 l,39.3,54 l,38.3,54 l,35,53.8 l,23.8,53.5 l,14,53 l,4.5,52.5 l,2.1,52 l,0,49 l,0.2,47.5 l,2.2,46.2 l,5.1,46.4 l,11.4,46.9 l,20.9,47.5 l,27.8,47.9 l,38,49.1 l,39.6,49.1 l,39.8,48.4 l,39.3,48 l,38.9,47.6 l,29,41 l,18.4,34 l,12.8,29.9 l,9.8,27.9 l,8.3,25.9 l,7.7,21.7 l,10.4,18.7 l,14.1,19 l,15,19.2 l,18.7,22.1 l,26.7,28.2 l,37,36 l,38.5,37.2 l,39.1,36.8 l,39.2,36.5 l,38.5,35.4 l,33,25 l,27,14.6 l,24.3,10.3 l,23.6,7.7 c,23.3,6.7,23.2,5.7,23.2,4.7 l,26.2,0.5 l,28,0 l,32.2,0.6 l,33.8,2 l,36.4,8 l,40.5,17.3 l,47,29.9 l,49,33.7 l,50,37.1 l,50.3,38.1 l,51,38.1 l,51,37.6 l,51.5,30.4 l,52.5,21.7 l,53.5,10.5 l,53.8,7.3 l,55.4,3.5 l,58.4,1.5 l,61,2.6 l,63,5.5 l,62.7,7.3 l,61.6,15 l,59,27.1 l,57.5,35.3 l,58.4,35.3 l,59.4,34.2 l,63.5,28.8 l,70.4,20.2 l,73.4,16.7 l,77,13 l,79.3,11.2 l,83.6,11.2 l,86.7,15.9 l,85.3,20.8 l,80.9,26.4 l,77.2,31.1 l,71.9,38.2 l,68.7,43.9 l,69,44.3 l,69.7,44.3 l,81.7,41.7 l,88.1,40.6 l,95.7,39.3 l,99.2,40.9 l,99.6,42.5 l,98.2,45.9 l,90,47.9 l,80.4,49.9 l,66.1,53.2 l,65.9,53.3 l,66.1,53.6 l,72.5,54.2 l,75.3,54.4 l,82.1,54.4 l,94.7,55.4 l,98,57.4 l,99.9,60.1 l,99.6,62.1 l,94.5,64.7 l,87.7,63.1 l,71.7,59.3 l,66.3,58 l,65.5,58 l,65.5,58.4 l,70.1,62.9 l,78.4,70.4 l,89,80.1 l,89.5,82.5 l,88.2,84.5 l,86.8,84.3 l,77.6,77.3 l,74,74.3 l,66,67.5 l,65.5,67.5 l,65.5,68.2 l,67.3,70.9 l,77.1,85.6 l,77.6,90.1 l,76.9,91.5 l,74.3,92.5 l,71.6,91.9 l,65.8,83.9 l,59.8,74.9 l,55.1,66.7 l,54.6,67.1 l,51.7,97.3 l,50.4,98.8 l,47.4,100 l,44.9,98 l,43.5,95 l,44.9,88.8 l,46.5,80.8 l,47.8,74.4 l,49,66.5 l,49.7,63.9 l,49.7,63.7 l,49,63.7 l,43,72 l,34,84.3 l,26.8,91.9 l,25.1,92.6 l,22.1,91.1 l,22.4,88.3 l,24,86 l,34,73.2 l,40,65.3 l,44,60.7 l,43.9,60.2 l,43.6,60.2 l,17.2,77.4 l,12.5,78 l,10.5,76 l,10.7,73 l,11.7,72 l,19.7,66.5 Z"

    private static let unitPath: Path = {
        var path = Path()
        for token in commands.split(separator: " ") {
            if token == "Z" { path.closeSubpath(); continue }
            let values = token.dropFirst(2).split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) / 100 }
            switch token.first {
            case "m": path.move(to: CGPoint(x: values[0], y: values[1]))
            case "l": path.addLine(to: CGPoint(x: values[0], y: values[1]))
            case "c": path.addCurve(to: CGPoint(x: values[4], y: values[5]),
                                    control1: CGPoint(x: values[0], y: values[1]),
                                    control2: CGPoint(x: values[2], y: values[3]))
            default: break
            }
        }
        return path
    }()

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        return Self.unitPath.applying(CGAffineTransform(scaleX: side, y: side)
            .concatenating(CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)))
    }

    /// A template image, so a sidebar tints it exactly as it tints SF Symbols
    /// (accent while the window is key, grey behind other windows).
    static func templateImage(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(ClaudeMark().path(in: rect).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}
