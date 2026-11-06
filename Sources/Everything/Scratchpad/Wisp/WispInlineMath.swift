import Foundation

@MainActor
enum InlineMath {
    static func answer(forLine line: String) -> String? {
        guard let body = expressionText(line) else { return nil }
        let ns = body as NSString
        var starts = [0]
        for i in 0..<ns.length where i > 0 && isSpace(ns.character(at: i - 1)) && !isSpace(ns.character(at: i)) {
            starts.append(i)
        }
        for start in starts {
            if start > 0, containsNumber(ns.substring(to: start)) { break }
            if let answer = evaluate(ns.substring(from: start)) { return answer }
        }
        return nil
    }

    static func containsNumber(_ text: String) -> Bool {
        tokenize(text, lenient: true)?.contains { if case .number = $0 { return true } else { return false } } ?? false
    }

    private static let marker = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s+|#{1,6}\s+)?"#
    )

    static func expressionText(_ line: String) -> String? {
        var text = line
        while let last = text.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
            text.unicodeScalars.removeLast()
        }
        guard text.hasSuffix("=") else { return nil }
        text.removeLast()
        if let before = text.last, "=!<>".contains(before) { return nil }
        let ns = text as NSString
        let stripped = marker.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(from: NSMaxRange($0.range)) } ?? text
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func evaluate(_ expression: String) -> String? {
        if expression.range(of: #"\b\d{4}-\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil {
            return nil
        }
        guard let tokens = tokenize(expression) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseStatement(), parser.isAtEnd, parser.didOperate else { return nil }
        return format(value)
    }

    // MARK: Values

    enum Value {
        case number(Double)
        case percent(Double)
        case quantity(Double, Dimension)
        case money(Double, Currency)

        var scalar: Double? {
            switch self {
            case .number(let n): return n
            case .percent(let p): return p / 100
            case .quantity, .money: return nil
            }
        }
    }

    struct Currency {
        let symbol: Character
        let suffix: Bool
        let spaced: Bool
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case symbol(Character)
        case word(String)
        case currency(Character, spaced: Bool)
    }

    private static let keywords: Set<String> = ["in", "to", "as", "of", "x"]

    private static let multipliers: [String: Double] = ["k": 1_000, "K": 1_000, "M": 1_000_000]

    static func tokenize(_ text: String, lenient: Bool = false) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(text)
        let n = chars.count
        func isDigit(_ i: Int) -> Bool { i < n && chars[i].isASCII && chars[i].isNumber }
        func isThousandsComma(_ i: Int) -> Bool {
            chars[i] == "," && isDigit(i + 1) && isDigit(i + 2) && isDigit(i + 3) && !isDigit(i + 4)
        }
        func isLetter(_ i: Int) -> Bool { i < n && (chars[i].isLetter || chars[i] == "°") }
        func readLetters() -> String {
            var word = ""
            while isLetter(i) { word.append(chars[i]); i += 1 }
            return word
        }
        func skipWord() {
            while i < n, chars[i].isLetter || chars[i].isNumber || chars[i] == "." { i += 1 }
        }
        var i = 0
        while i < n {
            let c = chars[i]
            if c == " " || c == "\t" {
                i += 1
            } else if isDigit(i) || (c == "." && isDigit(i + 1)) {
                var digits = ""
                while i < n {
                    if isDigit(i) || chars[i] == "." {
                        digits.append(chars[i])
                        i += 1
                    } else if isThousandsComma(i) {
                        i += 1
                    } else {
                        break
                    }
                }
                guard var value = Double(digits) else { return nil }
                if isLetter(i) {
                    let glued = readLetters()
                    let lower = glued.lowercased()
                    if let factor = multipliers[glued], !isDigit(i) {
                        value *= factor
                        tokens.append(.number(value))
                    } else if Units.unit(named: lower) != nil || lower == "x" {
                        tokens.append(.number(value))
                        tokens.append(.word(lower))
                    } else {
                        skipWord()
                    }
                    continue
                }
                tokens.append(.number(value))
            } else if c.isCurrencySymbol {
                let spaced = i > 0 && (chars[i - 1] == " " || chars[i - 1] == "\t")
                tokens.append(.currency(c, spaced: spaced))
                i += 1
            } else if "+-*/^()%×÷−".contains(c) {
                let normalised: Character = c == "×" ? "*" : c == "÷" ? "/" : c == "−" ? "-" : c
                tokens.append(.symbol(normalised))
                i += 1
            } else if isLetter(i) {
                let word = readLetters()
                if isDigit(i) {
                    skipWord()
                    continue
                }
                let lower = word.lowercased()
                if keywords.contains(lower) || Units.unit(named: lower) != nil {
                    tokens.append(.word(lower))
                }
            } else if lenient {
                i += 1
            } else {
                return nil
            }
        }
        return tokens
    }

    // MARK: Parser

    @MainActor
    struct Parser {
        let tokens: [Token]
        var index = 0
        var didOperate = false

        init(tokens: [Token]) { self.tokens = tokens }

        var isAtEnd: Bool { index >= tokens.count }
        private var peek: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func take(_ symbol: Character) -> Bool {
            if peek == .symbol(symbol) { index += 1; return true }
            return false
        }

        private mutating func takeWord(_ words: Set<String>) -> Bool {
            if case .word(let w)? = peek, words.contains(w) { index += 1; return true }
            return false
        }

        mutating func parseStatement() -> Value? {
            guard var value = parseSum() else { return nil }
            if takeWord(["in", "to", "as"]) {
                guard case .word(let name)? = peek, let target = Units.unit(named: name) else { return nil }
                index += 1
                guard case .quantity(let amount, let unit) = value,
                      let converted = Units.convert(amount, from: unit, to: target) else { return nil }
                value = .quantity(converted, target)
                didOperate = true
            }
            return value
        }

        private mutating func parseSum() -> Value? {
            guard var left = parseProduct() else { return nil }
            while true {
                let sign: Double
                if take("+") { sign = 1 } else if take("-") { sign = -1 } else { return left }
                guard let right = parseProduct() else { return nil }
                didOperate = true
                guard let combined = Self.add(left, right, sign: sign) else { return nil }
                left = combined
            }
        }

        private mutating func parseProduct() -> Value? {
            guard var left = parseUnary() else { return nil }
            while true {
                let dividing: Bool
                if take("*") || takeWord(["x"]) { dividing = false } else if take("/") { dividing = true } else { return left }
                guard let right = parseUnary() else { return nil }
                didOperate = true
                guard let combined = Self.multiply(left, right, dividing: dividing) else { return nil }
                left = combined
            }
        }

        private mutating func parseUnary() -> Value? {
            if take("-") {
                guard let value = parseUnary() else { return nil }
                switch value {
                case .number(let n): return .number(-n)
                case .percent(let p): return .percent(-p)
                case .quantity(let q, let u): return .quantity(-q, u)
                case .money(let m, let c): return .money(-m, c)
                }
            }
            if take("+") { return parseUnary() }
            return parsePower()
        }

        private mutating func parsePower() -> Value? {
            guard let base = parsePostfix() else { return nil }
            guard take("^") else { return base }
            guard let exponent = parseUnary(), let b = base.scalar, let e = exponent.scalar else { return nil }
            didOperate = true
            return .number(pow(b, e))
        }

        private mutating func parsePostfix() -> Value? {
            guard let primary = parsePrimary() else { return nil }
            if take("%") {
                guard let p = primary.scalar else { return nil }
                if takeWord(["of"]) {
                    guard let whole = parseUnary() else { return nil }
                    didOperate = true
                    return Self.multiply(.number(p / 100), whole, dividing: false)
                }
                return .percent(p)
            }
            if case .number(let n) = primary, case .word(let name)? = peek, let unit = Units.unit(named: name) {
                index += 1
                var total = n
                while index + 1 < tokens.count,
                      case .number(let more) = tokens[index],
                      case .word(let nextName) = tokens[index + 1],
                      let nextUnit = Units.unit(named: nextName),
                      let converted = Units.convert(more, from: nextUnit, to: unit) {
                    total += converted
                    index += 2
                    didOperate = true
                }
                return .quantity(total, unit)
            }
            if case .number(let n) = primary, case .currency(let symbol, let spaced)? = peek {
                index += 1
                return .money(n, Currency(symbol: symbol, suffix: true, spaced: spaced))
            }
            return primary
        }

        private mutating func parsePrimary() -> Value? {
            if case .currency(let symbol, _)? = peek {
                index += 1
                guard case .number(let n)? = peek else { return nil }
                index += 1
                return .money(n, Currency(symbol: symbol, suffix: false, spaced: false))
            }
            if case .number(let n)? = peek {
                index += 1
                return .number(n)
            }
            if take("(") {
                guard let inner = parseSum(), take(")") else { return nil }
                return inner
            }
            return nil
        }

        static func add(_ a: Value, _ b: Value, sign: Double) -> Value? {
            switch (a, b) {
            case (.money(let x, let c), .money(let y, let d)):
                return c.symbol == d.symbol ? .money(x + sign * y, c) : nil
            case (.money(let x, let c), .percent(let p)):
                return .money(x * (1 + sign * p / 100), c)
            case (.money(let x, let c), .number(let y)):
                return .money(x + sign * y, c)
            case (.number(let x), .money(let y, let c)):
                return .money(x + sign * y, c)
            case (.money, _), (_, .money):
                return nil
            case (.quantity(let x, let u), .quantity(let y, let v)):
                guard let y2 = Units.convert(y, from: v, to: u) else { return nil }
                return .quantity(x + sign * y2, u)
            case (.number(let x), .percent(let p)):
                return .number(x * (1 + sign * p / 100))
            case (.quantity(let x, let u), .percent(let p)):
                return .quantity(x * (1 + sign * p / 100), u)
            case (.percent(let p), .percent(let q)):
                return .percent(p + sign * q)
            case (.percent, .number), (.percent, .quantity):
                return nil
            default:
                guard let x = a.scalar, let y = b.scalar else { return nil }
                return .number(x + sign * y)
            }
        }

        static func multiply(_ a: Value, _ b: Value, dividing: Bool) -> Value? {
            switch (a, b) {
            case (.money(let x, let c), .money(let y, let d)):
                guard dividing, c.symbol == d.symbol, y != 0 else { return nil }
                return .number(x / y)
            case (.money(let x, let c), _):
                guard let y = b.scalar else { return nil }
                if dividing { return y == 0 ? nil : .money(x / y, c) }
                return .money(x * y, c)
            case (_, .money(let y, let c)):
                guard !dividing, let x = a.scalar else { return nil }
                return .money(x * y, c)
            case (.quantity(let x, let u), _):
                guard let y = b.scalar ?? Self.sameUnitRatio(b, u) else { return nil }
                if case .quantity = b {
                    return dividing && y != 0 ? .number(x / y) : nil
                }
                if dividing { return y == 0 ? nil : .quantity(x / y, u) }
                return .quantity(x * y, u)
            case (_, .quantity(let y, let u)):
                guard !dividing, let x = a.scalar else { return nil }
                return .quantity(x * y, u)
            default:
                guard let x = a.scalar, let y = b.scalar else { return nil }
                if dividing { return y == 0 ? nil : .number(x / y) }
                return .number(x * y)
            }
        }

        private static func sameUnitRatio(_ value: Value, _ unit: Dimension) -> Double? {
            guard case .quantity(let y, let v) = value else { return nil }
            return Units.convert(y, from: v, to: unit)
        }
    }

    // MARK: Output

    static func format(_ value: Value) -> String? {
        switch value {
        case .number(let n):
            return formatNumber(n, maxFraction: 6)
        case .percent(let p):
            return formatNumber(p, maxFraction: 4).map { $0 + "%" }
        case .quantity(let q, let unit):
            let digits = abs(q) < 1 ? 4 : 2
            return formatNumber(q, maxFraction: digits).map { "\($0) \(Units.symbol(for: unit))" }
        case .money(let m, let currency):
            return formatMoney(m, currency)
        }
    }

    static func formatMoney(_ m: Double, _ currency: Currency) -> String? {
        guard m.isFinite else { return nil }
        let cents = (m * 100).rounded()
        let whole = cents.truncatingRemainder(dividingBy: 100) == 0
        let key = whole ? -10 : -12
        let formatter = formatters[key] ?? {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            f.minimumFractionDigits = whole ? 0 : 2
            f.maximumFractionDigits = whole ? 0 : 2
            formatters[key] = f
            return f
        }()
        guard let digits = formatter.string(from: NSNumber(value: abs(cents) / 100)) else { return nil }
        let sign = cents < 0 ? "-" : ""
        let symbol = String(currency.symbol)
        return currency.suffix
            ? sign + digits + (currency.spaced ? " " : "") + symbol
            : sign + symbol + digits
    }

    static func formatNumber(_ n: Double, maxFraction: Int) -> String? {
        guard n.isFinite else { return nil }
        let tiny = n != 0 && abs(n) < 0.5 * pow(10, -Double(maxFraction))
        let huge = abs(n) >= 1e15
        let key = tiny ? -1 : huge ? -2 : maxFraction
        let formatter = formatters[key] ?? {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            if tiny || huge {
                f.usesSignificantDigits = true
                f.maximumSignificantDigits = tiny ? 4 : 15
            } else {
                f.minimumFractionDigits = 0
                f.maximumFractionDigits = maxFraction
            }
            formatters[key] = f
            return f
        }()
        let text = formatter.string(from: NSNumber(value: n))
        return text == "-0" ? "0" : text
    }

    private static var formatters: [Int: NumberFormatter] = [:]

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
}

@MainActor
enum Units {
    private static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    private static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))

    private static let table: [(names: [String], unit: Dimension, symbol: String)] = [
        (["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers, "km"),
        (["m", "meter", "meters", "metre", "metres"], UnitLength.meters, "m"),
        (["cm", "centimeter", "centimeters", "centimetre", "centimetres"], UnitLength.centimeters, "cm"),
        (["mm", "millimeter", "millimeters", "millimetre", "millimetres"], UnitLength.millimeters, "mm"),
        (["mi", "mile", "miles"], UnitLength.miles, "mi"),
        (["ft", "foot", "feet"], UnitLength.feet, "ft"),
        (["in", "inch", "inches"], UnitLength.inches, "in"),
        (["yd", "yard", "yards"], UnitLength.yards, "yd"),
        (["kg", "kilogram", "kilograms", "kilo", "kilos"], UnitMass.kilograms, "kg"),
        (["g", "gram", "grams"], UnitMass.grams, "g"),
        (["lb", "lbs", "pound", "pounds"], UnitMass.pounds, "lb"),
        (["oz", "ounce", "ounces"], UnitMass.ounces, "oz"),
        (["c", "°c", "celsius"], UnitTemperature.celsius, "°C"),
        (["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit, "°F"),
        (["kelvin"], UnitTemperature.kelvin, "K"),
        (["ms", "millisecond", "milliseconds"], UnitDuration.milliseconds, "ms"),
        (["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds, "s"),
        (["min", "mins", "minute", "minutes"], UnitDuration.minutes, "min"),
        (["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours, "h"),
        (["d", "day", "days"], day, "d"),
        (["wk", "week", "weeks"], week, "wk"),
        (["b", "byte", "bytes"], UnitInformationStorage.bytes, "B"),
        (["kb"], UnitInformationStorage.kilobytes, "KB"),
        (["mb"], UnitInformationStorage.megabytes, "MB"),
        (["gb"], UnitInformationStorage.gigabytes, "GB"),
        (["tb"], UnitInformationStorage.terabytes, "TB"),
        (["kib"], UnitInformationStorage.kibibytes, "KiB"),
        (["mib"], UnitInformationStorage.mebibytes, "MiB"),
        (["gib"], UnitInformationStorage.gibibytes, "GiB"),
    ]

    private static let byName: [String: Dimension] = {
        var map: [String: Dimension] = [:]
        for entry in table { for name in entry.names { map[name] = entry.unit } }
        return map
    }()

    static func unit(named name: String) -> Dimension? { byName[name.lowercased()] }

    static func symbol(for unit: Dimension) -> String {
        table.first { $0.unit == unit }?.symbol ?? unit.symbol
    }

    static func convert(_ value: Double, from: Dimension, to: Dimension) -> Double? {
        guard type(of: from).baseUnit() == type(of: to).baseUnit() else { return nil }
        return Measurement(value: value, unit: from).converted(to: to).value
    }
}
