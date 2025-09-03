import Foundation
import UserNotifications
import UIKit

@MainActor
class LocalNotificationService: NSObject, ObservableObject {
    static let shared = LocalNotificationService()
    
    private let notificationCenter = UNUserNotificationCenter.current()
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var recordingStartTime: Date?
    
    // Notification IDs
    private enum NotificationID {
        static let recording = "hearo.recording.ongoing"
        static let playback = "hearo.playback.ongoing"
    }
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        setupNotificationCategories()
    }
    
    // MARK: - Permission Management
    
    func requestPermissions() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(
                options: [.alert, .sound, .badge, .providesAppNotificationSettings]
            )
            print("📱 Notification permissions granted: \(granted)")
            return granted
        } catch {
            print("❌ Failed to request notification permissions: \(error)")
            return false
        }
    }
    
    // MARK: - Recording Notifications
    
    func startRecordingNotifications(title: String = "New Recording") {
        recordingStartTime = Date()
        
        Task {
            await showRecordingNotification(title: title, elapsed: 0)
            
            // Update notification every 10 seconds while recording
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let elapsed = Date().timeIntervalSince(startTime)
                
                Task { @MainActor in
                    await self.showRecordingNotification(title: title, elapsed: elapsed)
                }
            }
        }
    }
    
    func stopRecordingNotifications() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingStartTime = nil
    }

    func showRecordingSuccessNotification() {
        Task {
            await removeNotification(identifier: NotificationID.recording)
            await showRecordingCompletedNotification()
        }
    }

    private func showRecordingNotification(title: String, elapsed: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = "🎙️ AuryO Recording"
        content.subtitle = title
        content.body = "Recording in progress • \(formatTime(elapsed))"
        content.sound = nil // Silent for ongoing recording
        content.categoryIdentifier = "RECORDING_ONGOING"
        
        // Add custom data
        content.userInfo = [
            "type": "recording",
            "elapsed": elapsed,
            "title": title
        ]
        
        // Rich notification with progress
        if let attachment = await createProgressAttachment(progress: min(elapsed / 3600, 1.0), isRecording: true) {
            content.attachments = [attachment]
        }
        
        let request = UNNotificationRequest(
            identifier: NotificationID.recording,
            content: content,
            trigger: nil // Show immediately
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("❌ Failed to show recording notification: \(error)")
        }
    }
    
    private func showRecordingCompletedNotification() async {
        let content = UNMutableNotificationContent()
        content.title = "✅ Recording Complete"
        content.body = "Your recording has been saved successfully"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "RECORDING_COMPLETE"
        
        let request = UNNotificationRequest(
            identifier: "hearo.recording.complete",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("❌ Failed to show recording complete notification: \(error)")
        }
    }
    
    // MARK: - Playback Notifications
    
    func startPlaybackNotifications(title: String, duration: TimeInterval) {
        Task {
            await showPlaybackNotification(title: title, elapsed: 0, duration: duration)
            
            // Update notification every 5 seconds during playback
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] timer in
                // You'll need to get actual playback progress from your audio player
                // For now, this is a placeholder
                let elapsed = timer.fireDate.timeIntervalSince(Date()) // This needs actual playback time
                
                Task { @MainActor in
                    await self?.showPlaybackNotification(title: title, elapsed: max(0, elapsed), duration: duration)
                }
            }
        }
    }
    
    func stopPlaybackNotifications() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        Task {
            await removeNotification(identifier: NotificationID.playback)
        }
    }
    
    private func showPlaybackNotification(title: String, elapsed: TimeInterval, duration: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = "▶️ AuryO Playing"
        content.subtitle = title
        content.body = "Playing • \(formatTime(elapsed)) / \(formatTime(duration))"
        content.sound = nil // Silent for ongoing playback
        content.categoryIdentifier = "PLAYBACK_ONGOING"
        
        // Add progress info
        content.userInfo = [
            "type": "playback",
            "elapsed": elapsed,
            "duration": duration,
            "title": title
        ]
        
        // Rich notification with playback progress
        let progress = duration > 0 ? elapsed / duration : 0
        if let attachment = await createProgressAttachment(progress: progress, isRecording: false) {
            content.attachments = [attachment]
        }
        
        let request = UNNotificationRequest(
            identifier: NotificationID.playback,
            content: content,
            trigger: nil
        )
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("❌ Failed to show playback notification: \(error)")
        }
    }
    
    // MARK: - Rich Media Attachments
    
    private func createProgressAttachment(progress: Double, isRecording: Bool) async -> UNNotificationAttachment? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100))
        
        let image = renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: 300, height: 100)
            
            // Background
            UIColor.systemBackground.setFill()
            context.fill(rect)
            
            // App icon area
            let iconRect = CGRect(x: 10, y: 20, width: 60, height: 60)
            let iconColor = isRecording ? UIColor.systemRed : UIColor.systemGreen
            iconColor.setFill()
            context.fill(iconRect.insetBy(dx: 5, dy: 5))
            context.cgContext.fillEllipse(in: iconRect.insetBy(dx: 5, dy: 5))
            
            // Icon symbol
            UIColor.white.setFill()
            if isRecording {
                // Microphone icon (simplified)
                let micRect = CGRect(x: 28, y: 35, width: 24, height: 30)
                context.fill(micRect)
            } else {
                // Play button (triangle)
                let playPath = UIBezierPath()
                playPath.move(to: CGPoint(x: 32, y: 35))
                playPath.addLine(to: CGPoint(x: 32, y: 65))
                playPath.addLine(to: CGPoint(x: 52, y: 50))
                playPath.close()
                playPath.fill()
            }
            
            // Progress bar background
            let progressBG = CGRect(x: 80, y: 45, width: 200, height: 10)
            UIColor.systemGray5.setFill()
            context.fill(progressBG)
            
            // Progress bar fill
            let progressFill = CGRect(x: 80, y: 45, width: 200 * progress, height: 10)
            (isRecording ? UIColor.systemRed : UIColor.systemGreen).setFill()
            context.fill(progressFill)
            
            // Animated waveform (for recording)
            if isRecording {
                let waveColor = UIColor.systemRed.withAlphaComponent(0.6)
                waveColor.setFill()
                
                for i in 0..<20 {
                    let x = 80 + i * 10
                    let height = CGFloat.random(in: 5...25)
                    let waveRect = CGRect(x: CGFloat(x), y: 75 - height/2, width: 6, height: height)
                    context.fill(waveRect)
                }
            }
        }
        
        // Save to temporary file
        guard let data = image.pngData() else { return nil }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        
        do {
            try data.write(to: tempURL)
            return try UNNotificationAttachment(identifier: "progress", url: tempURL)
        } catch {
            print("❌ Failed to create notification attachment: \(error)")
            return nil
        }
    }
    
    // MARK: - Notification Categories & Actions
    
    private func setupNotificationCategories() {
        let recordingCategory = UNNotificationCategory(
            identifier: "RECORDING_ONGOING",
            actions: [
                UNNotificationAction(
                    identifier: "STOP_RECORDING",
                    title: "Stop Recording",
                    options: [.destructive]
                ),
                UNNotificationAction(
                    identifier: "OPEN_APP",
                    title: "Open AuryO",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: []
        )
        
        let playbackCategory = UNNotificationCategory(
            identifier: "PLAYBACK_ONGOING",
            actions: [
                UNNotificationAction(
                    identifier: "PAUSE_PLAYBACK",
                    title: "Pause",
                    options: []
                ),
                UNNotificationAction(
                    identifier: "STOP_PLAYBACK",
                    title: "Stop",
                    options: [.destructive]
                ),
                UNNotificationAction(
                    identifier: "OPEN_APP",
                    title: "Open AuryO",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: []
        )
        
        let completeCategory = UNNotificationCategory(
            identifier: "RECORDING_COMPLETE",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_RECORDING",
                    title: "View Recording",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: []
        )
        
        notificationCenter.setNotificationCategories([
            recordingCategory,
            playbackCategory,
            completeCategory
        ])
    }
    
    // MARK: - Utility
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func removeNotification(identifier: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    
    func removeAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.removeAllDeliveredNotifications()
        recordingTimer?.invalidate()
        playbackTimer?.invalidate()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension LocalNotificationService: UNUserNotificationCenterDelegate {
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound])
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        
        Task { @MainActor in
            await handleNotificationAction(actionIdentifier: actionIdentifier, userInfo: userInfo)
            completionHandler()
        }
    }
    
    private func handleNotificationAction(actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        switch actionIdentifier {
        case "STOP_RECORDING":
            // Post notification to stop recording
            NotificationCenter.default.post(name: .stopRecordingFromNotification, object: nil)
            
        case "PAUSE_PLAYBACK":
            // Post notification to pause playback
            NotificationCenter.default.post(name: .pausePlaybackFromNotification, object: nil)
            
        case "STOP_PLAYBACK":
            // Post notification to stop playback
            NotificationCenter.default.post(name: .stopPlaybackFromNotification, object: nil)
            
        case "OPEN_APP", "VIEW_RECORDING", UNNotificationDefaultActionIdentifier:
            // App will automatically open when notification is tapped
            break
            
        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let stopRecordingFromNotification = Notification.Name("stopRecordingFromNotification")
    static let pausePlaybackFromNotification = Notification.Name("pausePlaybackFromNotification")
    static let stopPlaybackFromNotification = Notification.Name("stopPlaybackFromNotification")
}


