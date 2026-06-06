import AVFoundation
import QuartzCore
import Observation
import Foundation

@Observable
@MainActor
final class MusicPlayer: NSObject {

    private(set) var currentSong: Song?
    private(set) var isPlaying: Bool = false
    private(set) var beatPhase: Double = 0.0
    private(set) var songs: [Song] = []
    private(set) var currentIndex: Int = 0

    private var player: AVAudioPlayer?
    private var displayLink: CADisplayLink?
    private var beatStartTime: CFTimeInterval = 0
    private var beatDuration: CFTimeInterval = 60.0 / 96.0

    override init() {
        super.init()
        loadSongs()
    }

    private func loadSongs() {
        guard
            let url = Bundle.main.url(forResource: "songs", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([Song].self, from: data)
        else { return }
        songs = decoded
        currentSong = decoded.first
    }

    func play() {
        guard let song = currentSong else { return }

        let url = Bundle.main.url(forResource: song.file, withExtension: "mp3")
            ?? Bundle.main.url(forResource: song.file, withExtension: "mp3", subdirectory: "Songs")

        guard let url else { return }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            isPlaying = true
            beatDuration = 60.0 / song.bpm
            startDisplayLink()
        } catch {
            print("MusicPlayer play error: \(error)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopDisplayLink()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func next() {
        guard !songs.isEmpty else { return }
        currentIndex = (currentIndex + 1) % songs.count
        currentSong = songs[currentIndex]
        if isPlaying { play() }
    }

    func previous() {
        guard !songs.isEmpty else { return }
        currentIndex = (currentIndex - 1 + songs.count) % songs.count
        currentSong = songs[currentIndex]
        if isPlaying { play() }
    }

    private func startDisplayLink() {
        stopDisplayLink()
        beatStartTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        beatPhase = 0.0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = CACurrentMediaTime() - beatStartTime
        beatPhase = (elapsed / beatDuration).truncatingRemainder(dividingBy: 1.0)
    }
}

extension MusicPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.next()
            if self.isPlaying { self.play() }
        }
    }
}
