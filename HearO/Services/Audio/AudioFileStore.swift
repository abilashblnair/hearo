import Foundation

enum AudioFileStore {
    static func url(for id: UUID) throws -> URL {
        let docs = try documentsDirectory()
        return docs.appendingPathComponent("audio/\(id.uuidString).m4a")
    }
    
    /// Consistent Documents directory resolution used across the app
    static func documentsDirectory() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "AudioFileStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not access Documents directory"])
        }
        return docs
    }
}
