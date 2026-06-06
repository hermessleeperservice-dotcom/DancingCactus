import AVFoundation
import Observation

@Observable
@MainActor
final class ParrotMode {

    private(set) var isActive: Bool = false
    private(set) var isWiggling: Bool = false

    private let pitchCents: Float = 600.0
    private let silenceGap: TimeInterval = 0.3
    private let windowDuration: TimeInterval = 1.0
    private let rmsThreshold: Float = -30.0

    private let engine = AVAudioEngine()
    private let pitchEffect = AVAudioUnitTimePitch()
    private let playerNode = AVAudioPlayerNode()

    private var rollingBuffers: [AVAudioPCMBuffer] = []
    private var rollingSeconds: TimeInterval = 0
    private var silenceStart: Date?
    private var tapInstalled = false
    private var isPlayingBack = false

    init() {
        setupEngine()
    }

    func activate() {
        isActive = true
        do {
            try engine.start()
            installTap()
        } catch {
            print("ParrotMode start error: \(error)")
        }
    }

    func deactivate() {
        removeTap()
        if engine.isRunning { engine.stop() }
        rollingBuffers = []
        rollingSeconds = 0
        silenceStart = nil
        isPlayingBack = false
        isActive = false
        isWiggling = false
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            let rmsDB = buf.rmsDB()
            let copy = buf.copy() as! AVAudioPCMBuffer
            let dur = Double(buf.frameLength) / buf.format.sampleRate
            Task { @MainActor [weak self] in
                self?.process(rmsDB: rmsDB, buffer: copy, duration: dur)
            }
        }
        tapInstalled = true
    }

    private func removeTap() {
        guard tapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func process(rmsDB: Float, buffer: AVAudioPCMBuffer, duration: TimeInterval) {
        guard !isPlayingBack else { return }

        rollingBuffers.append(buffer)
        rollingSeconds += duration
        while rollingSeconds > windowDuration, let first = rollingBuffers.first {
            rollingSeconds -= Double(first.frameLength) / first.format.sampleRate
            rollingBuffers.removeFirst()
        }

        if rmsDB < rmsThreshold {
            if silenceStart == nil { silenceStart = Date() }
            if let s = silenceStart,
               Date().timeIntervalSince(s) >= silenceGap,
               !rollingBuffers.isEmpty {
                triggerPlayback()
            }
        } else {
            silenceStart = nil
        }
    }

    private func triggerPlayback() {
        guard !rollingBuffers.isEmpty else { return }
        isPlayingBack = true
        isWiggling = true
        removeTap()

        let format = rollingBuffers[0].format
        guard let combined = mergeBuffers(rollingBuffers, format: format) else {
            finishPlayback()
            return
        }
        rollingBuffers = []
        rollingSeconds = 0
        silenceStart = nil

        playerNode.scheduleBuffer(combined, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in self?.finishPlayback() }
        }
        playerNode.play()
    }

    private func finishPlayback() {
        playerNode.stop()
        isWiggling = false
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            self.isPlayingBack = false
            self.installTap()
        }
    }
}

private func mergeBuffers(_ buffers: [AVAudioPCMBuffer], format: AVAudioFormat) -> AVAudioPCMBuffer? {
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
