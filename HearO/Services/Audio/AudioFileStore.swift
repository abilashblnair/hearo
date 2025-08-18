import Foundation

enum AudioFileStore {
    static func url(for id: UUID) throws -> URL {
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return docs.appendingPathComponent("audio/\(id.uuidString).m4a")
    }
}
