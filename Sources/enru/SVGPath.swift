import CoreGraphics
import Foundation

/// Minimal SVG path-data parser: enough of the grammar to consume the `d` attribute
/// of a Figma export (move/line/horizontal/vertical/cubic/close, absolute or relative,
/// with implicit command repetition). Arcs and quadratics are not supported — Figma
/// emits neither for flattened shapes.
enum SVGPath {
    static func cgPath(from data: String) -> CGPath {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var index = data.startIndex

        /// Consumes the operands for one command, leaving any remainder for an
        /// implicit repeat of the same command.
        func take(_ count: Int) -> [CGFloat]? {
            guard numbers.count >= count else { return nil }
            defer { numbers.removeFirst(count) }
            return Array(numbers.prefix(count))
        }

        func flush() {
            let relative = command.isLowercase
            let origin = relative ? current : .zero

            repeat {
                switch command.uppercased().first! {
                case "M":
                    guard let v = take(2) else { return }
                    current = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
                    path.move(to: current)
                    subpathStart = current
                    // Extra coordinate pairs after a moveto are implicit linetos.
                    command = relative ? "l" : "L"
                case "L":
                    guard let v = take(2) else { return }
                    current = CGPoint(x: origin.x + v[0], y: origin.y + v[1])
                    path.addLine(to: current)
                case "H":
                    guard let v = take(1) else { return }
                    current = CGPoint(x: origin.x + v[0], y: current.y)
                    path.addLine(to: current)
                case "V":
                    guard let v = take(1) else { return }
                    current = CGPoint(x: current.x, y: origin.y + v[0])
                    path.addLine(to: current)
                case "C":
                    guard let v = take(6) else { return }
                    path.addCurve(
                        to: CGPoint(x: origin.x + v[4], y: origin.y + v[5]),
                        control1: CGPoint(x: origin.x + v[0], y: origin.y + v[1]),
                        control2: CGPoint(x: origin.x + v[2], y: origin.y + v[3])
                    )
                    current = CGPoint(x: origin.x + v[4], y: origin.y + v[5])
                case "Z":
                    path.closeSubpath()
                    current = subpathStart
                    numbers.removeAll()
                default:
                    numbers.removeAll()
                }
            } while !numbers.isEmpty
        }

        while index < data.endIndex {
            let character = data[index]
            if character.isLetter {
                flush()
                command = character
                index = data.index(after: index)
                if character.uppercased() == "Z" { flush() }
            } else if character.isNumber || character == "-" || character == "+" || character == "." {
                var literal = String(character)
                index = data.index(after: index)
                while index < data.endIndex {
                    let next = data[index]
                    // A sign mid-token starts a new number unless it follows an exponent.
                    if next.isNumber || next == "." {
                        literal.append(next)
                    } else if next == "e" || next == "E" {
                        literal.append(next)
                    } else if (next == "-" || next == "+"), let last = literal.last, last == "e" || last == "E" {
                        literal.append(next)
                    } else {
                        break
                    }
                    index = data.index(after: index)
                }
                if let value = Double(literal) { numbers.append(CGFloat(value)) }
            } else {
                index = data.index(after: index) // whitespace or comma
            }
        }
        flush()

        return path
    }
}
