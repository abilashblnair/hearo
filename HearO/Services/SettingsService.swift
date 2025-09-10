import Foundation
import Combine

final class SettingsService: ObservableObject {
    static let shared = SettingsService()
    
    // MARK: - Published Properties
    
    /// Whether folder management is enabled (default: true)
    @Published var isFolderManagementEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isFolderManagementEnabled, forKey: SettingsKeys.folderManagementEnabled)
        }
    }
    
    /// Whether live transcription is enabled
    @Published var isLiveTranscriptionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLiveTranscriptionEnabled, forKey: SettingsKeys.liveTranscriptionEnabled)
        }
    }
    
    /// Whether to show recording notifications
    @Published var showRecordingNotifications: Bool {
        didSet {
            UserDefaults.standard.set(showRecordingNotifications, forKey: SettingsKeys.recordingNotifications)
        }
    }
    
    /// Audio quality setting
    @Published var audioQuality: AudioQuality {
        didSet {
            UserDefaults.standard.set(audioQuality.rawValue, forKey: SettingsKeys.audioQuality)
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load settings from UserDefaults with default values
        self.isFolderManagementEnabled = UserDefaults.standard.object(forKey: SettingsKeys.folderManagementEnabled) as? Bool ?? true
        self.isLiveTranscriptionEnabled = UserDefaults.standard.object(forKey: SettingsKeys.liveTranscriptionEnabled) as? Bool ?? false
        self.showRecordingNotifications = UserDefaults.standard.object(forKey: SettingsKeys.recordingNotifications) as? Bool ?? true
        
        let qualityRawValue = UserDefaults.standard.string(forKey: SettingsKeys.audioQuality) ?? AudioQuality.high.rawValue
        self.audioQuality = AudioQuality(rawValue: qualityRawValue) ?? .high
    }
    
    // MARK: - Methods
    
    func resetToDefaults() {
        isFolderManagementEnabled = true
        isLiveTranscriptionEnabled = false
        showRecordingNotifications = true
        audioQuality = .high
    }
}

// MARK: - Settings Keys

private enum SettingsKeys {
    static let folderManagementEnabled = "folderManagementEnabled"
    static let liveTranscriptionEnabled = "liveTranscriptionEnabled"
    static let recordingNotifications = "recordingNotifications"
    static let audioQuality = "audioQuality"
}

// MARK: - Audio Quality Enum

enum AudioQuality: String, CaseIterable, Identifiable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case lossless = "lossless"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .low: return "Low (32 kbps)"
        case .medium: return "Medium (128 kbps)"
        case .high: return "High (256 kbps)"
        case .lossless: return "Lossless (ALAC)"
        }
    }
    
    var description: String {
        switch self {
        case .low: return "Smallest file size, basic quality"
        case .medium: return "Good balance of size and quality"
        case .high: return "High quality, recommended"
        case .lossless: return "Maximum quality, large files"
        }
    }
}


