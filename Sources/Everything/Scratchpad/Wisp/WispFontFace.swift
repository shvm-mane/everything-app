import AppKit

enum FontFace: String, CaseIterable {
    case charter
    case iowanOldStyle
    case hoeflerText
    case palatino
    case optima
    case avenirNext
    case sanFrancisco
    case verdana
    case newYork
    case sfMono

    var displayName: String {
        switch self {
        case .charter:        return "Charter"
        case .iowanOldStyle:  return "Iowan Old Style"
        case .hoeflerText:    return "Hoefler Text"
        case .palatino:       return "Palatino"
        case .optima:         return "Optima"
        case .avenirNext:     return "Avenir Next"
        case .sanFrancisco:   return "San Francisco"
        case .verdana:        return "Verdana"
        case .newYork:        return "New York"
        case .sfMono:         return "SF Mono"
        }
    }

    func font(size: CGFloat) -> NSFont? {
        if self == .sanFrancisco { return NSFont.systemFont(ofSize: size) }
        if self == .sfMono { return NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
        if self == .newYork {
            return NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif)
                .flatMap { NSFont(descriptor: $0, size: size) }
        }
        return NSFont(name: familyName, size: size)
    }

    var familyName: String { displayName }
}
