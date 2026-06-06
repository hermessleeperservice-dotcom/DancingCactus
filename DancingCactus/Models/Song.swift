import Foundation

struct Song: Codable, Identifiable, Hashable {
    let id: Int
    let file: String
    let title: String
    let bpm: Double
}
