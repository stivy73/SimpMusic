import CoreImage.CIFilterBuiltins
import Foundation

/// Pixel-aligned QR with an opaque white quiet zone, shared by phone and CarPlay.
/// Never cached on disk: the image contains the ephemeral invitation secret.
public enum PassengerQRCode {
  public static func image(for invitation: PassengerInvitation, side: Int = 720) -> CGImage? {
    guard (128...2048).contains(side) else { return nil }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(invitation.text.utf8)
    filter.correctionLevel = "M"
    guard let code = filter.outputImage,
      let raw = CIContext().createCGImage(code, from: code.extent),
      let canvas = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let scale = max(1, side / (raw.width + 8))
    let size = raw.width * scale
    let inset = (side - size) / 2
    canvas.setFillColor(CGColor(gray: 1, alpha: 1))
    canvas.fill(CGRect(x: 0, y: 0, width: side, height: side))
    canvas.interpolationQuality = .none
    canvas.draw(raw, in: CGRect(x: inset, y: inset, width: size, height: size))
    return canvas.makeImage()
  }
}
