import Foundation
import UIKit

struct Track: Identifiable, Equatable {
    let id: UUID
    let url: URL
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artworkData: Data?

    var artwork: UIImage? {
        artworkData.flatMap { UIImage(data: $0) }
    }

    var durationFormatted: String {
        let total = Int(max(0, duration))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}
