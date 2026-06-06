import AVFoundation
import Observation

@Observable
@MainActor
final class VoiceListener {

    enum State { case idle, capturing, playingBack, cooldown }

    private(set) var state: State = .idle

    private let rmsStartThreshold: Float = -20.0
    private let rmsStopThreshold: Float  = -35.0
    private let silenceDuration: TimeInterval  = 0.4
    private let maxCaptureDuration: TimeInterval = 15.0
    private let cooldownDuration: TimeInterval  = 0.5
    private let pitchCents: Float = 400.0

    private let engine = AVAudioEngine()
    private let pitchEffect = AVAudioUnitTimePitch()
    private let playerNode = AVAudioPlayerNode()

    private var capturedBuffers: [AVAudioPCMBuffer] = []
    private var silenceStart: Date?
    private var captureStart: Date?
    private var tapInstalled = false

    init() {
        setupEngine()
    }

    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            installTap()
        } catch {
            print("VoiceListener start error: \(error)")
        }
    }

    func stop() {
        removeTap()
        if engine.isRunning { engine.stop() }
        capturedBuffers = []
        silenceStart = nil
        captureStart = nil
        state = .idle
    }

    private func setupEngine() {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )!
        engine.attach(playerNode)
        engine.attach(pitchEffect)
        engine.connect(playerNode, to: pitchEffect, format: format)
        engine.connect(pitchEffect, to: engine.mainMixerNode, format: format)
        pitchEffect.pitch = pitchCents
    }

    private func installTap() {
        guard !tapInstalled else { return }
        let inputNode = engine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: fmt) { [weak self] buf, _ in
            let rmsDB = buf.rmsDB()
            let copy = buf.copy() as! AVAudioPCMBuffer
            Task { @MainActor [weak self] in
                self?.process(rmsDB: rmsDB, buffer: copy, format: fmt)
            }
        }
        tapInstalled = true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func process(rmsDB: Float, buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        switch state {
        case .idle:
            if rmsDB > rmsStartThreshold {
                state = .capturing
                capturedBuffers = [buffer]
                captureStart = Date()
                silenceStart = nil
            }

        case .capturing:
            capturedBuffers.append(buffer)

            if rmsDB < rmsStopThreshold {
                if silenceStart == nil { silenceStart = Date() }
                if let s = silenceStart, Date().timeIntervalSince(s) >= silenceDuration {
                    triggerPlayback(format: format)
                    return
                }
            } else {
                silenceStart = nil
            }

            if let s = captureStart, Date().timeIntervalSince(s) > maxCaptureDuration {
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
        playBuffers(buffers, format: format)
    }

    private func playBuffers(_ buffers: [AVAudioPCMBuffer], format: AVAudioFormat) {
        guard let combined = merge(buffers, format: format) else {
            enterCooldown()
            return
        }
        playerNode.scheduleBuffer(combined, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in self?.enterCooldown() }
        }
        playerNode.play()
    }

    private func enterCooldown() {
        state = .cooldown
        playerNode.stop()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(cooldownDuration))
            self.state = .idle
            self.installTap()
        }
    }
}

private func merge(_ buffers: [AVAudioPCMBuffer], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let total = buffers.reduce(AVAudioFrameCount(0)) { $0 + $1.frameLength }
    guard total > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total) else { return nil }
    for buf in buffers {
        guard let src = buf.floatChannelData, let dst = out.floatChannelData else { continue }
        let offset = Int(out.frameLength)
        let count = Int(buf.frameLength)
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
        let rms = sqrt(sum / Float(n))
        return 20.0 * log10(max(rms, 1e-9))
    }
}
