import CoreGraphics
import Vision
import XCTest

@testable import PrototypeCore

final class PassengerQRCodeTests: XCTestCase {
  private func read(_ image: CGImage) throws -> String? {
    let request = VNDetectBarcodesRequest()
    request.symbologies = [.qr]
    try VNImageRequestHandler(cgImage: image).perform([request])
    return request.results?.first?.payloadStringValue
  }

  func testPhoneAndCarPlaySizesDecodeToTheSameInvitation() throws {
    let invitation = PassengerInvitation()
    for side in [128, 160, 180, 220, 240, 360, 440, 720] {
      let image = try XCTUnwrap(PassengerQRCode.image(for: invitation, side: side))
      XCTAssertEqual(image.width, side)
      XCTAssertEqual(image.height, side)
      XCTAssertEqual(try read(image), invitation.text, "Unreadable QR at \(side) pixels")
    }
  }

  func testNativeDownscalingAndSessionRotation() throws {
    let original = PassengerInvitation()
    let image = try XCTUnwrap(PassengerQRCode.image(for: original))
    for side in [160, 200, 240] {
      let context = try XCTUnwrap(CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
      XCTAssertEqual(try read(XCTUnwrap(context.makeImage())), original.text)
    }
    let replacement = PassengerInvitation()
    let next = try XCTUnwrap(PassengerQRCode.image(for: replacement))
    XCTAssertEqual(try read(next), replacement.text)
    XCTAssertNotEqual(try read(next), original.text)
  }

  func testImageSizeIsBounded() {
    let invitation = PassengerInvitation()
    XCTAssertNil(PassengerQRCode.image(for: invitation, side: 0))
    XCTAssertNil(PassengerQRCode.image(for: invitation, side: 4096))
  }
}
