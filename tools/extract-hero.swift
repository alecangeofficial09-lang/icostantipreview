import AVFoundation
import ImageIO
import CoreGraphics
import Foundation

// Genera la sequenza di frame dell'hero de I Costanti.
// Sostituisce ffmpeg (non installato): AVAssetImageGenerator con tolleranza zero
// estrae fotogrammi esatti, poi ritaglio e riscalo con CoreGraphics.
//
// Due output dallo stesso decode:
//   land/  1280 x 549   frame pieno, per viewport orizzontali
//   port/   560 x 810   crop verticale centrato sul varco, per mobile portrait
//
// Il crop verticale e' centrato su VARCO_X = 49.52% della larghezza sorgente,
// misurato sull'ultimo frame (fessura fra le ante: colonne 607..849 di 1470).
//
// Uso: swift extract-hero.swift <video> <outdir> [numFrames]

let args = CommandLine.arguments
guard args.count > 2 else { print("uso: extract-hero.swift <video> <outdir> [n]"); exit(1) }
let src = URL(fileURLWithPath: args[1])
let outRoot = URL(fileURLWithPath: args[2], isDirectory: true)
let N = args.count > 3 ? Int(args[3])! : 120

let VARCO_X = 0.4952          // centro del varco, frazione della larghezza sorgente
let LAND_W = 1280
let PORT_W = 560, PORT_H = 810
// q0.42 e' il ginocchio della curva: sotto 0.50 ImageIO passa a 4:2:0 e il peso
// crolla del 37% senza danni visibili su un girato gia' morbido e con grana sopra.
let JPG_Q_LAND = 0.42, JPG_Q_PORT = 0.45, JPG_Q_POSTER = 0.72

let landDir = outRoot.appendingPathComponent("land")
let portDir = outRoot.appendingPathComponent("port")
for d in [landDir, portDir] {
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
}

let asset = AVAsset(url: src)
let dur = CMTimeGetSeconds(asset.duration)
guard let track = asset.tracks(withMediaType: .video).first else { exit(1) }
let natural = track.naturalSize
let SW = Int(natural.width), SH = Int(natural.height)

// L'ultimo frame decodificabile in modo affidabile: 15.000s (verificato col probe).
let LAST_T = min(dur - 0.042, 15.000)

let landH = Int((Double(LAND_W) * Double(SH) / Double(SW)).rounded(.down)) & ~1
print("sorgente \(SW)x\(SH)  durata \(dur)s")
print("land \(LAND_W)x\(landH)   port \(PORT_W)x\(PORT_H)   frame=\(N)   ultimo t=\(LAST_T)s")

let gen = AVAssetImageGenerator(asset: asset)
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
gen.appliesPreferredTrackTransform = true   // niente maximumSize: voglio la piena risoluzione per ritagliare

let cs = CGColorSpaceCreateDeviceRGB()

func resize(_ img: CGImage, _ w: Int, _ h: Int) -> CGImage? {
    guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    c.interpolationQuality = .high
    c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return c.makeImage()
}

func writeJPEG(_ img: CGImage, _ url: URL, _ q: Double) -> Int {
    guard let d = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) else { return 0 }
    CGImageDestinationAddImage(d, img, [kCGImageDestinationLossyCompressionQuality: q] as CFDictionary)
    guard CGImageDestinationFinalize(d) else { return 0 }
    return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
}

// Rettangolo di crop per il ritratto: altezza piena, larghezza derivata dal rapporto
// di destinazione, centrata sul varco e clampata dentro i bordi della sorgente.
let cropW = Double(SH) * Double(PORT_W) / Double(PORT_H)
var cropX = Double(SW) * VARCO_X - cropW / 2
cropX = max(0, min(Double(SW) - cropW, cropX))
let cropRect = CGRect(x: cropX.rounded(), y: 0, width: cropW.rounded(), height: Double(SH))
print("crop ritratto: x \(Int(cropRect.minX))..\(Int(cropRect.maxX)) di \(SW) (larghezza \(Int(cropRect.width)))")

var landBytes = 0, portBytes = 0, failed = 0

for i in 0..<N {
    let t = Double(i) / Double(N - 1) * LAST_T
    let time = CMTime(seconds: t, preferredTimescale: 600)
    guard let full = try? gen.copyCGImage(at: time, actualTime: nil) else {
        print("frame \(i) FALLITO a \(t)s"); failed += 1; continue
    }
    let name = String(format: "f_%03d.jpg", i)

    if let l = resize(full, LAND_W, landH) {
        landBytes += writeJPEG(l, landDir.appendingPathComponent(name), JPG_Q_LAND)
    }
    if let cropped = full.cropping(to: cropRect), let p = resize(cropped, PORT_W, PORT_H) {
        portBytes += writeJPEG(p, portDir.appendingPathComponent(name), JPG_Q_PORT)
    }
    if i == 0, let poster = resize(full, LAND_W, landH) {
        _ = writeJPEG(poster, outRoot.appendingPathComponent("poster.jpg"), JPG_Q_POSTER)
    }
    if i == N - 1, let soglia = resize(full, LAND_W, landH) {
        _ = writeJPEG(soglia, outRoot.appendingPathComponent("soglia.jpg"), JPG_Q_POSTER)
    }
    if i % 20 == 0 { print("  \(i)/\(N)  t=\(String(format: "%.3f", t))s") }
}

func mb(_ b: Int) -> String { String(format: "%.2f MB", Double(b) / 1_048_576) }
print("\nland: \(mb(landBytes))  (media \(landBytes / max(1, N - failed) / 1024) KB/frame)")
print("port: \(mb(portBytes))  (media \(portBytes / max(1, N - failed) / 1024) KB/frame)")
print("falliti: \(failed)")
