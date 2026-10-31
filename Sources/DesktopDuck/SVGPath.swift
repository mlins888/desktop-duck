import SwiftUI

/// Minimal parser for the absolute M/L/C/Z path data that Figma exports,
/// so the duck parts in `art/` can be drawn (and animated) as SwiftUI shapes.
struct SVGPath: Shape {
    let d: String

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tokens = SVGPath.tokenize(d)
        var i = 0
        var command: Character = "M"

        func number() -> CGFloat {
            defer { i += 1 }
            return CGFloat(Double(tokens[i]) ?? 0)
        }
        func point() -> CGPoint { CGPoint(x: number(), y: number()) }

        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                command = c
                i += 1
            }
            switch command {
            case "M":
                path.move(to: point())
                command = "L" // implicit lineto after the first moveto pair
            case "L":
                path.addLine(to: point())
            case "C":
                let c1 = point(), c2 = point(), end = point()
                path.addCurve(to: end, control1: c1, control2: c2)
            case "Z", "z":
                path.closeSubpath()
            default:
                i += 1
            }
        }
        return path
    }

    private static func tokenize(_ d: String) -> [String] {
        let regex = try! Regex(#"[MLCZmlcz]|-?\d*\.?\d+(?:e-?\d+)?"#)
        return d.matches(of: regex).map { String(d[$0.range]) }
    }
}
