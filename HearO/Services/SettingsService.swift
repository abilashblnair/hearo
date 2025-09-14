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
    
    
    // MARK: - Initialization
    
    private init() {
        // Load settings from UserDefaults with default values
        self.isFolderManagementEnabled = UserDefaults.standard.object(forKey: SettingsKeys.folderManagementEnabled) as? Bool ?? true
        self.isLiveTranscriptionEnabled = UserDefaults.standard.object(forKey: SettingsKeys.liveTranscriptionEnabled) as? Bool ?? false
        self.showRecordingNotifications = UserDefaults.standard.object(forKey: SettingsKeys.recordingNotifications) as? Bool ?? true
        
    }
    
    // MARK: - Methods
    
    func resetToDefaults() {
        isFolderManagementEnabled = true
        isLiveTranscriptionEnabled = false
        showRecordingNotifications = true
    }
}

// MARK: - Settings Keys

private enum SettingsKeys {
    static let folderManagementEnabled = "folderManagementEnabled"
    static let liveTranscriptionEnabled = "liveTranscriptionEnabled"
    static let recordingNotifications = "recordingNotifications"
}
