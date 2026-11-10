import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 0, space: rgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let tile = CGPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832),
                  cornerWidth: 184, cornerHeight: 184, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
                  color: CGColor(red: 0.08, green: 0.18, blue: 0.44, alpha: 0.31))
context.setFillColor(CGColor(red: 0.14, green: 0.34, blue: 0.90, alpha: 1))
context.addPath(tile)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
let gradient = CGGradient(colorsSpace: rgb, colors: [
    CGColor(red: 0.16, green: 0.36, blue: 0.94, alpha: 1),
    CGColor(red: 0.31, green: 0.55, blue: 1.00, alpha: 1),
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 280, y: 130),
                           end: CGPoint(x: 710, y: 890), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.restoreGState()

let paper = CGPath(roundedRect: CGRect(x: 270, y: 285, width: 484, height: 435),
                   cornerWidth: 58, cornerHeight: 58, transform: nil)
context.addPath(paper)
context.setFillColor(CGColor(gray: 1, alpha: 0.14))
context.fillPath()
context.addPath(paper)
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(30)
context.setLineCap(.round)
context.setLineJoin(.round)
context.strokePath()
context.strokeLineSegments(between: [
    CGPoint(x: 270, y: 599), CGPoint(x: 754, y: 599),
    CGPoint(x: 392, y: 682), CGPoint(x: 392, y: 763),
    CGPoint(x: 632, y: 682), CGPoint(x: 632, y: 763),
])
context.setLineWidth(42)
context.move(to: CGPoint(x: 416, y: 456))
context.addLine(to: CGPoint(x: 486, y: 390))
context.addLine(to: CGPoint(x: 610, y: 515))
context.strokePath()

let png = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output))
