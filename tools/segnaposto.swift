import CoreGraphics
import ImageIO
import Foundation

// Genera i segnaposto come file JPEG veri, ai percorsi e alle proporzioni
// definitive: quando arriva la foto vera si sovrascrive il file e basta,
// senza toccare l'HTML.
//
// Le voci marcate REALE sono quelle per cui il cliente ha gia' scelto una
// foto: qui restano segnaposto solo finche' il file non viene copiato sopra.

let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "public/foto"
let cs = CGColorSpaceCreateDeviceRGB()

struct Posto { let path: String; let w: Int; let h: Int; let a: (Double,Double,Double); let b: (Double,Double,Double) }

let pietra   = (198.0, 178.0, 152.0)
let terra    = (166.0, 116.0,  78.0)
let oliva    = (124.0, 128.0,  96.0)
let crema    = (226.0, 214.0, 194.0)
let penombra = ( 74.0,  58.0,  44.0)
let coccio   = (150.0,  92.0,  62.0)
let acqua    = (120.0, 162.0, 168.0)

let posti: [Posto] = [
  // La dimora — REALI, in attesa dei file del cliente
  Posto(path: "dimora/corte.jpg",   w: 1500, h: 1000, a: pietra,   b: penombra),
  Posto(path: "dimora/arredi.jpg",  w: 1500, h: 1000, a: crema,    b: terra),

  // Le camere — segnaposto dichiarato
  Posto(path: "camere/camere.jpg",  w: 1500, h: 1000, a: crema,    b: pietra),

  // Servizi
  Posto(path: "servizi/piscina.jpg",      w: 1500, h: 1000, a: acqua,    b: pietra),  // REALE
  Posto(path: "servizi/solarium.jpg",     w: 1500, h: 1000, a: terra,    b: crema),
  Posto(path: "servizi/sala-lettura.jpg", w: 1500, h: 1000, a: penombra, b: coccio),
  Posto(path: "servizi/biciclette.jpg",   w: 1500, h: 1000, a: oliva,    b: pietra),

  // La terra — tutte REALI
  Posto(path: "terra/vigneto.jpg",  w: 1600, h: 1066, a: oliva,    b: crema),
  Posto(path: "terra/cantina.jpg",  w: 1200, h: 800,  a: penombra, b: terra),
  Posto(path: "terra/olio.jpg",     w: 1200, h: 800,  a: oliva,    b: pietra),

  // Dintorni — segnaposto dichiarati
  Posto(path: "dintorni/verona.jpg",  w: 1000, h: 1000, a: coccio, b: penombra),
  Posto(path: "dintorni/garda.jpg",   w: 1000, h: 1000, a: acqua,  b: oliva),
  Posto(path: "dintorni/sigurta.jpg", w: 1000, h: 1000, a: oliva,  b: crema),
  Posto(path: "dintorni/soave.jpg",   w: 1000, h: 1000, a: terra,  b: pietra),

  // Contatti: nessun segnaposto, la mappa e' un iframe Google al clic.
]

func genera(_ p: Posto) {
    let url = URL(fileURLWithPath: root + "/" + p.path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    guard let ctx = CGContext(data: nil, width: p.w, height: p.h, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }

    let colori = [CGColor(red: p.a.0/255, green: p.a.1/255, blue: p.a.2/255, alpha: 1),
                  CGColor(red: p.b.0/255, green: p.b.1/255, blue: p.b.2/255, alpha: 1)] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: colori, locations: [0, 1]) {
        ctx.drawLinearGradient(grad,
            start: CGPoint(x: 0, y: p.h), end: CGPoint(x: p.w, y: 0), options: [])
    }

    for _ in 0..<(p.w * p.h / 90) {
        let x = Double.random(in: 0..<Double(p.w)), y = Double.random(in: 0..<Double(p.h))
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: abs(Double.random(in: -0.05...0.05)))
        ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
    }

    ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.16)
    ctx.setLineWidth(1)
    let cx = Double(p.w)/2, cy = Double(p.h)/2, r = Double(min(p.w, p.h)) * 0.06
    ctx.move(to: CGPoint(x: cx - r, y: cy)); ctx.addLine(to: CGPoint(x: cx + r, y: cy))
    ctx.move(to: CGPoint(x: cx, y: cy - r)); ctx.addLine(to: CGPoint(x: cx, y: cy + r))
    ctx.strokePath()

    guard let img = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.5] as CFDictionary)
    _ = CGImageDestinationFinalize(dest)
}

for p in posti { genera(p) }
print("generati \(posti.count) segnaposto in \(root)/")
