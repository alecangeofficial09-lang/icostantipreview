import CoreText
import CoreGraphics
import Foundation

// Genera i due file del marchio:
//   public/logo/i-costanti-emblema.svg   solo l'ovale col monogramma (testata)
//   public/logo/i-costanti.svg           il lockup completo (piede, condivisioni)
//
// Tutte le lettere sono convertite in tracciati: Snell Roundhand e Didot
// esistono solo su macOS, e un <text> nell'SVG fuori da qui degraderebbe a un
// corsivo qualunque. Convertite, mantengono i pieni e i filetti del corsivo
// inglese su qualunque browser.
//
// GEOMETRIA DELLA CORNICE — questa e' la parte che va riprodotta esatta:
// un ovale, e quattro archi che congiungono i punti cardinali bombando VERSO
// l'ovale. Formano una losanga a lati concavi e quattro petali. Non sono
// segmenti dritti: quello era l'errore della prima versione.

let bruno = "#4A2C1A"

// Regolabile da riga di comando per tarare la forma contro il marchio vero:
//   swift tools/marchio.swift public/logo 0.744
let kBombatura = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 0.62
// Snell Roundhand regolare: fra i corsivi di sistema e' quello col contrasto
// fra pieni e filetti piu' vicino al monogramma originale. Zapfino e' troppo
// dritto e senza intreccio, Apple Chancery rende la I come un blocco.
let fontMonogramma = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "SnellRoundhand"

// --- Utilita' tipografiche -------------------------------------------------

func percorso(_ testo: String, _ nomeFont: String, _ dim: Double,
              _ spaziatura: Double = 0) -> (d: String, larghezza: Double, riquadro: CGRect) {
    let font = CTFontCreateWithName(nomeFont as CFString, dim, nil)
    var d = ""
    var x = 0.0
    var unione = CGRect.null

    for ch in testo {
        var uni = Array(String(ch).utf16)
        var glifi = [CGGlyph](repeating: 0, count: uni.count)
        guard CTFontGetGlyphsForCharacters(font, &uni, &glifi, uni.count) else { continue }
        var avanzamenti = [CGSize](repeating: .zero, count: 1)
        CTFontGetAdvancesForGlyphs(font, .horizontal, &glifi[0], &avanzamenti, 1)

        if let p = CTFontCreatePathForGlyph(font, glifi[0], nil) {
            let dx = x
            func pt(_ q: CGPoint) -> String { String(format: "%.2f %.2f", q.x + dx, -q.y) }
            p.applyWithBlock { el in
                let e = el.pointee
                switch e.type {
                case .moveToPoint:         d += "M\(pt(e.points[0]))"
                case .addLineToPoint:      d += "L\(pt(e.points[0]))"
                case .addQuadCurveToPoint: d += "Q\(pt(e.points[0])) \(pt(e.points[1]))"
                case .addCurveToPoint:     d += "C\(pt(e.points[0])) \(pt(e.points[1])) \(pt(e.points[2]))"
                case .closeSubpath:        d += "Z"
                @unknown default: break
                }
            }
            let b = p.boundingBox
            if !b.isNull && !b.isEmpty {
                unione = unione.union(CGRect(x: b.minX + dx, y: -b.maxY, width: b.width, height: b.height))
            }
        }
        x += avanzamenti[0].width + spaziatura
    }
    return (d, x - spaziatura, unione)
}

/// Avvolge un tracciato in un <g> che lo porta a occupare `larghezzaBersaglio`
/// centrato su `cx`, con il bordo alto a `y`.
func collocato(_ p: (d: String, larghezza: Double, riquadro: CGRect),
               cx: Double, y: Double, larghezzaBersaglio: Double) -> String {
    let r = p.riquadro
    guard r.width > 0 else { return "" }
    let s = larghezzaBersaglio / r.width
    let tx = cx - (r.minX + r.width / 2) * s
    let ty = y - r.minY * s
    return #"  <path transform="translate(\#(f(tx)) \#(f(ty))) scale(\#(f(s)))" d="\#(p.d)"/>"#
}

func f(_ v: Double) -> String { String(format: "%.3f", v) }

// --- La cornice ------------------------------------------------------------

func cornice(cx: Double, cy: Double, rx: Double, ry: Double, spessore: Double) -> String {
    // Bombatura degli archi, in frazione del raggio.
    //   k = 0.50  lati dritti: la figura diventa un rombo
    //   k = 0.62  petali larghi e lati visibilmente curvi  <- il marchio
    //   k = 0.80  petali ridotti a fettine
    // Per una quadratica il punto di mezzo dell'arco cade a (2k+1)/4 * radice(2)
    // del raggio: con k = 0.62 arriva al 79%, contro il 71% dei lati dritti.
    // Tarato sul confronto a sei valori con il marchio inviato dal cliente.
    let k = kBombatura
    let cxk = rx * k, cyk = ry * k
    let su = (cx, cy - ry), giu = (cx, cy + ry)
    let dx = (cx + rx, cy), sx = (cx - rx, cy)

    let losanga = """
    M\(f(su.0)) \(f(su.1)) \
    Q\(f(cx + cxk)) \(f(cy - cyk)) \(f(dx.0)) \(f(dx.1)) \
    Q\(f(cx + cxk)) \(f(cy + cyk)) \(f(giu.0)) \(f(giu.1)) \
    Q\(f(cx - cxk)) \(f(cy + cyk)) \(f(sx.0)) \(f(sx.1)) \
    Q\(f(cx - cxk)) \(f(cy - cyk)) \(f(su.0)) \(f(su.1)) Z
    """

    return """
      <g fill="none" stroke="\(bruno)" stroke-width="\(f(spessore))" stroke-linejoin="round">
        <ellipse cx="\(f(cx))" cy="\(f(cy))" rx="\(f(rx))" ry="\(f(ry))"/>
        <path d="\(losanga)"/>
      </g>
    """
}

// --- Monogramma ------------------------------------------------------------

/// La I e la C intrecciate. Le due lettere si sovrappongono: la C sta a
/// destra e leggermente piu' bassa, la I la attraversa.
func monogramma(cx: Double, cy: Double, larghezza: Double) -> String {
    let i = percorso("I", fontMonogramma, 100)
    let c = percorso("C", fontMonogramma, 100)
    guard i.riquadro.width > 0, c.riquadro.width > 0 else { return "" }

    // Scala comune, calcolata perche' l'insieme sovrapposto occupi `larghezza`.
    let sovrapposizione = 0.42          // quanto la C entra dentro la I
    let largheUnite = i.riquadro.width + c.riquadro.width * (1 - sovrapposizione)
    let s = larghezza / largheUnite

    let altezza = max(i.riquadro.height, c.riquadro.height) * s
    let y0 = cy - altezza / 2
    let x0 = cx - larghezza / 2

    let txI = x0 - i.riquadro.minX * s
    let tyI = y0 - i.riquadro.minY * s - altezza * 0.04     // la I sta un filo piu' alta
    let txC = x0 + i.riquadro.width * s * (1 - sovrapposizione) - c.riquadro.minX * s
    let tyC = y0 - c.riquadro.minY * s + altezza * 0.06     // la C scende un poco

    return """
      <g fill="\(bruno)" stroke="none">
        <path transform="translate(\(f(txI)) \(f(tyI))) scale(\(f(s)))" d="\(i.d)"/>
        <path transform="translate(\(f(txC)) \(f(tyC))) scale(\(f(s)))" d="\(c.d)"/>
      </g>
    """
}

// --- Emblema ---------------------------------------------------------------

let emblema = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 288" role="img" aria-label="I Costanti">
  <!-- Generato da tools/marchio.swift — non modificare a mano.
       Ovale + quattro archi che bombano verso il bordo, e monogramma IC
       intrecciato. Le lettere sono tracciati, non testo. -->
\(cornice(cx: 100, cy: 144, rx: 76, ry: 106, spessore: 3.2))
\(monogramma(cx: 100, cy: 146, larghezza: 84))
</svg>

"""

// --- Lockup completo -------------------------------------------------------

let agriturismo = percorso("AGRITURISMO", "Didot", 100, 12)
let costanti = percorso("I Costanti", "SnellRoundhand", 100)

let lockup = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 470" role="img" aria-label="Agriturismo I Costanti">
  <!-- Generato da tools/marchio.swift — non modificare a mano. -->
\(cornice(cx: 160, cy: 140, rx: 76, ry: 106, spessore: 3.0))
\(monogramma(cx: 160, cy: 142, larghezza: 84))
  <g fill="\(bruno)" stroke="none">
\(collocato(agriturismo, cx: 160, y: 292, larghezzaBersaglio: 208))
\(collocato(costanti, cx: 160, y: 348, larghezzaBersaglio: 236))
  </g>
  <g stroke="\(bruno)" stroke-width="1.1">
    <line x1="46" y1="326" x2="146" y2="326"/>
    <line x1="174" y1="326" x2="274" y2="326"/>
  </g>
  <path d="M160 321 L165 326 L160 331 L155 326 Z" fill="\(bruno)"/>
</svg>

"""

let radice = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "public/logo"
try? FileManager.default.createDirectory(atPath: radice, withIntermediateDirectories: true)
try! emblema.write(toFile: radice + "/i-costanti-emblema.svg", atomically: true, encoding: .utf8)
try! lockup.write(toFile: radice + "/i-costanti.svg", atomically: true, encoding: .utf8)
print("scritti emblema (\(emblema.count) byte) e lockup (\(lockup.count) byte) in \(radice)/")
