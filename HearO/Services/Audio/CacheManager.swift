import Foundation

final class CacheManager {
    static let shared = CacheManager()
    
    lazy var cacheDirectory: URL = {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let cacheDir = documentsPath.appendingPathComponent("TTSCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true, attributes: nil)
        return cacheDir
    }()
    
    private init() {}
    
    func getCachedAudioURL(forKey key: String) -> URL? {
        let fileURL = cacheDirectory.appendingPathComponent(key + ".mp3")
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    
    func cacheAudio(data: Data, forKey key: String) -> URL {
        let fileURL = cacheDirectory.appendingPathComponent(key + ".mp3")
        try? data.write(to: fileURL)
        return fileURL
    }
    
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil)
    }
    
    func getCacheSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }
}
