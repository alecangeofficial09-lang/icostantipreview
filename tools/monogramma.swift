import CoreText
import CoreGraphics
import Foundation

// Estrae i contorni delle lettere del monogramma come tracciati SVG.
// Serve perche' Snell Roundhand esiste solo su macOS: convertite in path, le
// lettere mantengono la modulazione del tratto (pieni e filetti del corsivo
// inglese) su qualunque browser, senza dipendere da un font installato.
//
// Uso: swift monogramma.swift [nomeFont] [dimensione]

let nomeFont = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "SnellRoundhand-Black"
let dim = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 100.0

let font = CTFontCreateWithName(nomeFont as CFString, dim, nil)
let nomeVero = CTFontCopyPostScriptName(font) as String
print("// font richiesto: \(nomeFont) — ottenuto: \(nomeVero)")

func tracciato(_ carattere: Character) -> (String, CGRect)? {
    var uni = Array(String(carattere).utf16)
    var glifi = [CGGlyph](repeating: 0, count: uni.count)
    guard CTFontGetGlyphsForCharacters(font, &uni, &glifi, uni.count) else { return nil }
    guard let path = CTFontCreatePathForGlyph(font, glifi[0], nil) else { return nil }

    var d = ""
    // CoreText ha l'asse Y verso l'alto, SVG verso il basso: si specchia qui.
    func p(_ pt: CGPoint) -> String {
        String(format: "%.2f %.2f", pt.x, -pt.y)
    }
    path.applyWithBlock { elemento in
        let e = elemento.pointee
        switch e.type {
        case .moveToPoint:         d += "M\(p(e.points[0]))"
        case .addLineToPoint:      d += "L\(p(e.points[0]))"
        case .addQuadCurveToPoint: d += "Q\(p(e.points[0])) \(p(e.points[1]))"
        case .addCurveToPoint:     d += "C\(p(e.points[0])) \(p(e.points[1])) \(p(e.points[2]))"
        case .closeSubpath:        d += "Z"
        @unknown default: break
        }
    }
    let b = path.boundingBox
    // il riquadro va specchiato come i punti
    let riquadro = CGRect(x: b.minX, y: -b.maxY, width: b.width, height: b.height)
    return (d, riquadro)
}

for c in ["I", "C"] {
    guard let (d, r) = tracciato(Character(c)) else { print("// \(c): fallito"); continue }
    print("// \(c) riquadro x=\(String(format: "%.1f", r.minX)) y=\(String(format: "%.1f", r.minY)) w=\(String(format: "%.1f", r.width)) h=\(String(format: "%.1f", r.height))")
    print("\(c)=\(d)")
    print("")
}
