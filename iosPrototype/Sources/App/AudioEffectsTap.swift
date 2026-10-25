#if os(iOS)
  import AVFoundation
  import MediaToolbox
  import Foundation

  /// The audio callback never waits for the settings UI. A concurrent update bypasses one block.
  final class EffectsTapState: @unchecked Sendable {
    let lock = NSLock()
    var settings = AudioEffects()
    var processor: EffectsDSP?
    var rate = 44100.0
    var channels = 2
    var supported = false
    var frames = 0
    let sweep = DJSweep()
    func setDJ(_ progress: Double?, incoming: Bool) {
      lock.lock()
      defer { lock.unlock() }
      sweep.configure(progress: progress, incoming: incoming, rate: rate)
    }
    var processedFrames: Int {
      lock.lock()
      defer { lock.unlock() }
      return frames
    }
    func configure(_ value: AudioEffects) {
      lock.lock()
      defer { lock.unlock() }
      settings = value
      processor = EffectsDSP(settings: value, rate: rate, channels: channels)
    }
  }
  @MainActor final class AudioEffectsTap {
    let state = EffectsTapState()
    func attach(to item: AVPlayerItem, track: AVAssetTrack) {
      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: Unmanaged.passRetained(state).toOpaque(),
        init: { _, info, storage in storage.pointee = info },
        finalize: { tap in
          Unmanaged<EffectsTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
        },
        prepare: { tap, _, format in
          let state = Unmanaged<EffectsTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
            .takeUnretainedValue()
          state.lock.lock()
          defer { state.lock.unlock() }
          let f = format.pointee
          state.supported =
            f.mFormatID == kAudioFormatLinearPCM && f.mBitsPerChannel == 32
            && f.mFormatFlags & kAudioFormatFlagIsFloat != 0
          state.rate = f.mSampleRate
          state.channels = Int(f.mChannelsPerFrame)
          state.processor = EffectsDSP(
            settings: state.settings, rate: state.rate, channels: state.channels)
        },
        unprepare: { _ in },
        process: { tap, requested, flags, buffers, count, flagsOut in
          guard
            MTAudioProcessingTapGetSourceAudio(tap, requested, buffers, flagsOut, nil, count)
              == noErr
          else {
            count.pointee = 0
            return
          }
          let state = Unmanaged<EffectsTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
            .takeUnretainedValue()
          guard state.lock.try() else { return }
          defer { state.lock.unlock() }
          guard state.supported, let processor = state.processor else { return }
          state.frames += Int(count.pointee)
          let list = UnsafeMutableAudioBufferListPointer(buffers)
          var channelBase = 0
          for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self), channels > 0
            else { continue }
            let samples = min(
              Int(count.pointee) * channels, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            for i in 0..<samples {
              pointer[i] = state.sweep.process(
                processor.process(pointer[i], channel: channelBase + i % channels),
                channel: channelBase + i % channels)
            }
            channelBase += channels
          }
        })
      var unmanaged: MTAudioProcessingTap?
      let result = MTAudioProcessingTapCreate(
        kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &unmanaged)
      guard result == noErr, let unmanaged else {
        Unmanaged.passUnretained(state).release()
        return
      }
      let parameters = AVMutableAudioMixInputParameters(track: track)
      parameters.audioTapProcessor = unmanaged
      let mix = AVMutableAudioMix()
      mix.inputParameters = [parameters]
      item.audioMix = mix
    }
    func configure(_ settings: AudioEffects) { state.configure(settings) }
  }
#endif
