import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceListener {

    enum State { case idle, capturing, playingBack, cooldown }
    private(set) var state: State = .idle

    private let rmsStartThreshold: Float        = -20.0
    private let rmsStopThreshold:  Float        = -30.0  // easier to detect silence
    private let silenceDuration:   TimeInterval = 2.5    // 2.5s of quiet ends capture
    private let maxCaptureDuration: TimeInterval = 30.0
    private let cooldownDuration:  TimeInterval = 0.3
    private let pitchCents:        Float        = 400.0

    private let engine      = AVAudioEngine()
    private let pitchEffect = AVAudioUnitTimePitch()
    private let playerNode  = AVAudioPlayerNode()
    private var tapInstalled = false
    private var playbackFormat: AVAudioFormat!   // format used for both tap and playback chain

    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var silenceStart:    Date?
    private var captureStart:    Date?

    init() {
        pitchEffect.pitch = pitchCents
        engine.attach(playerNode)
        engine.attach(pitchEffect)

        // Determine connection format before starting.
        // On a real device this returns the hardware format correctly.
        // On simulator it may return sampleRate=0 — fall back to 44100/1ch
        // (the tap will be skipped on simulator anyway since sr=0 post-start too).
        let inputFmt = engine.inputNode.outputFormat(forBus: 0)
        let fmt: AVAudioFormat
        if inputFmt.sampleRate > 0 {
            fmt = inputFmt
        } else {
            fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 44100, channels: 1, interleaved: false)!
        }
        playbackFormat = fmt
        engine.connect(playerNode, to: pitchEffect,           format: fmt)
        engine.connect(pitchEffect, to: engine.mainMixerNode, format: fmt)
    }

    // MARK: - Public

    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("VoiceListener: engine start failed — \(error)")
            return
        }

        // After start, confirm/update the actual hardware format
        let hwFmt = engine.inputNode.outputFormat(forBus: 0)
        guard hwFmt.sampleRate > 0, hwFmt.channelCount > 0 else {
            print("VoiceListener: no audio input available (sr=\(hwFmt.sampleRate))")
            return
        }
        print("VoiceListener: started — hw format sr=\(hwFmt.sampleRate) ch=\(hwFmt.channelCount)")

        // If hardware format differs from what we connected with, reconnect while running
        // (AVAudioEngine supports live reconnection)
        if hwFmt.sampleRate != playbackFormat.sampleRate ||
           hwFmt.channelCount != playbackFormat.channelCount {
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: pitchEffect,           format: hwFmt)
            engine.connect(pitchEffect, to: engine.mainMixerNode, format: hwFmt)
            playbackFormat = hwFmt
            print("VoiceListener: reconnected nodes with hw format")
        }

        installTap(format: hwFmt)
    }

    func stop() {
        removeTap()
        if engine.isRunning { engine.stop() }
        capturedBuffers = []
        silenceStart = nil
        captureStart = nil
        state = .idle
    }

    // MARK: - Tap

    private func installTap(format: AVAudioFormat) {
        guard !tapInstalled else { return }
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
            [weak self] buf, _ in
            let rmsDB = buf.rmsDB()
            guard let copy = buf.safeCopy() else { return }
            Task { @MainActor [weak self] in
                self?.process(rmsDB: rmsDB, buffer: copy)
            }
        }
        tapInstalled = true
        print("VoiceListener: tap installed (format \(format.sampleRate)Hz \(format.channelCount)ch)")
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    // MARK: - State machine

    private func process(rmsDB: Float, buffer: AVAudioPCMBuffer) {
        switch state {
        case .idle:
            if rmsDB > rmsStartThreshold {
                state = .capturing
                capturedBuffers = [buffer]
                captureStart = Date()
                silenceStart = nil
                print("VoiceListener: capturing (rms=\(String(format:"%.1f",rmsDB))dB)")
            }

        case .capturing:
            capturedBuffers.append(buffer)
            if rmsDB < rmsStopThreshold {
                if silenceStart == nil { silenceStart = Date() }
                if let s = silenceStart, Date().timeIntervalSince(s) >= silenceDuration {
                    triggerPlayback(); return
                }
            } else {
                silenceStart = nil
            }
            if let s = captureStart, Date().timeIntervalSince(s) > maxCaptureDuration {
                triggerPlayback()
            }

        case .playingBack, .cooldown:
            break
        }
    }

    private func triggerPlayback() {
        state = .playingBack
        removeTap()
        let buffers = capturedBuffers
        capturedBuffers = []; silenceStart = nil; captureStart = nil

        guard let combined = mergeBuffers(buffers, format: playbackFormat) else {
            enterCooldown(); return
        }
        print("VoiceListener: playing back \(combined.frameLength) frames")
        playerNode.scheduleBuffer(combined, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in self?.enterCooldown() }
        }
        playerNode.play()
    }

    private func enterCooldown() {
        state = .cooldown
        playerNode.stop()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.cooldownDuration))
            self.state = .idle
            self.installTap(format: self.playbackFormat)
        }
    }
}

// MARK: - Helpers

private func mergeBuffers(_ buffers: [AVAudioPCMBuffer], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let total = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
    guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
    for buf in buffers {
        guard let src = buf.floatChannelData, let dst = out.floatChannelData else { continue }
        let offset = Int(out.frameLength)
        let count  = Int(buf.frameLength)
        for ch in 0..<Int(format.channelCount) {
            memcpy(dst[ch] + offset, src[ch], count * MemoryLayout<Float>.size)
        }
        out.frameLength += buf.frameLength
    }
    return out
}

extension AVAudioPCMBuffer {
    func rmsDB() -> Float {
        guard let ch = floatChannelData else { return -160 }
        let n = Int(frameLength)
        guard n > 0 else { return -160 }
        var sum: Float = 0
        for i in 0..<n { let s = ch[0][i]; sum += s * s }
        return 20.0 * log10(max(sqrt(sum / Float(n)), 1e-9))
    }

    func safeCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity),
              let src = floatChannelData, let dst = copy.floatChannelData else { return nil }
        for ch in 0..<Int(format.channelCount) {
            memcpy(dst[ch], src[ch], Int(frameLength) * MemoryLayout<Float>.size)
        }
        copy.frameLength = frameLength
        return copy
    }
}
