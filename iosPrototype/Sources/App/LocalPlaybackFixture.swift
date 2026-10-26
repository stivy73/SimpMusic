#if DEBUG
  import AVFoundation
  import Foundation

  /// Only generated deterministic audio in the QA collection; never touches production downloads.
  enum LocalPlaybackFixture {
    static func audio(_ url: URL, seconds: Double, audibleSeconds: Double? = nil) throws {
      let rate = 44100.0
      let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
      buffer.frameLength = buffer.frameCapacity
      let file = try AVAudioFile(
        forWriting: url,
        settings: [
          AVFormatIDKey: kAudioFormatMPEG4AAC,
          AVSampleRateKey: rate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128000,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
      for block in 0..<Int(seconds * 10) {
        for channel in 0..<2 {
          for i in 0..<4410 {
            buffer.floatChannelData![channel][i] =
              audibleSeconds.map { Double(block) / 10 >= $0 } == true ? 0 : Float(
                sin(Double(block * 4410 + i) * 2 * .pi * 440 / rate) * 0.1)
          }
        }
        try file.write(from: buffer)
      }
    }
  }
#endif
