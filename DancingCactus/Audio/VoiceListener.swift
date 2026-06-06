import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceListener {

    enum State { case idle, capturing, playingBack, cooldown }
    private(set) var state: State = .idle

    // MARK: - Config
    private let rmsStartThreshold: Float  = -20.0  // dBFS to begin capture
    private let rmsStopThreshold:  Float  = -35.0  // dBFS silence to end capture
    private let silenceDuration:   TimeInterval = 0.4
    private let maxCaptureDuration: TimeInterval = 15.0
    private let cooldownDuration:  TimeInterval = 0.5
    private let pitchCents:        Float  = 400.0

    // MARK: - Engine
    private let engine      = AVAudioEngine()
    private let pitchEffect = AVAudioUnitTimePitch()
    private let playerNode  = AVAudioPlayerNode()
    private var tapInstalled    = false
    private var nodesConnected  = false
    private var captureFormat: AVAudioFormat?   // set once real hardware format is known

    // MARK: - Capture state
    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var silenceStart:    Date?
    private var captureStart:    Date?

    init() {
        engine.attach(playerNode)
        engine.attach(pitchEffect)
        pitchEffect.pitch = pitchCents
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

        // Determine the actual hardware input format NOW (after engine is running)
        let hwFormat = engine.inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            print("VoiceListener: invalid input format sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount), cannot install tap")
            return
        }
        captureFormat = hwFormat
        print("VoiceListener: hardware format sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount)")

        // Wire playback chain with the SAME format the mic produces
        if !nodesConnected {
            engine.connect(playerNode, to: pitchEffect,          format: hwFormat)
            engine.connect(pitchEffect, to: engine.mainMixerNode, format: hwFormat)
            nodesConnected = true
        }

        installTap(format: hwFormat)
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
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buf, _ in
            let rmsDB = buf.rmsDB()
            guard let copy = buf.safeCopy() else { return }
            Task { @MainActor [weak self] in
                self?.process(rmsDB: rmsDB, buffer: copy, format: format)
            }
        }
        tapInstalled = true
        print("VoiceListener: tap installed")
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    // MARK: - State machine

    private func process(rmsDB: Float, buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        switch state {
        case .idle:
            if rmsDB > rmsStartThreshold {
                state = .capturing
                capturedBuffers = [buffer]
                captureStart = Date()
                silenceStart = nil
                print("VoiceListener: capturing started (rms=\(rmsDB)dB)")
            }

        case .capturing:
            capturedBuffers.append(buffer)

            if rmsDB < rmsStopThreshold {
                if silenceStart == nil { silenceStart = Date() }
                if let s = silenceStart, Date().timeIntervalSince(s) >= silenceDuration {
                    print("VoiceListener: silence gap reached, triggering playback")
                    triggerPlayback(format: format)
                    return
                }
            } else {
                silenceStart = nil
            }

            if let s = captureStart, Date().timeIntervalSince(s) > maxCaptureDuration {
                print("VoiceListener: max capture duration reached, triggering playback")
                triggerPlayback(format: format)
            }

        case .playingBack, .cooldown:
            break
        }
    }

    private func triggerPlayback(format: AVAudioFormat) {
        state = .playingBack
        removeTap()
        let buffers = capturedBuffers
        capturedBuffers = []
        silenceStart = nil
        captureStart = nil

        guard let combined = mergeBuffers(buffers, format: format) else {
            enterCooldown()
            return
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
            if let fmt = self.captureFormat {
                self.installTap(format: fmt)
            }
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
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }
        guard let src = floatChannelData, let dst = copy.floatChannelData else { return nil }
        for ch in 0..<Int(format.channelCount) {
            memcpy(dst[ch], src[ch], Int(frameLength) * MemoryLayout<Float>.size)
        }
        copy.frameLength = frameLength
        return copy
    }
}
