import Foundation
import SwiftData
import SwiftUI

@Model
final class RecordingFolder: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorName: String // Store color name for persistence
    var createdAt: Date
    var isDefault: Bool // Mark default folder
    
    // Relationship to recordings
    @Relationship(deleteRule: .cascade, inverse: \Recording.folder)
    var recordings: [Recording] = []
    
    init(id: UUID = UUID(), name: String, colorName: String = "blue", createdAt: Date = Date(), isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.createdAt = createdAt
        self.isDefault = isDefault
    }
    
    // Computed property to get actual Color from colorName
    var color: Color {
        FolderColor.allCases.first { $0.name == colorName }?.color ?? .blue
    }
    
    // Computed properties for folder statistics
    var recordingCount: Int {
        recordings.count
    }
    
    var totalDuration: TimeInterval {
        recordings.reduce(0) { $0 + $1.duration }
    }
    
    var latestRecordingDate: Date? {
        recordings.max(by: { $0.createdAt < $1.createdAt })?.createdAt
    }
}

// MARK: - Folder Color System
enum FolderColor: String, CaseIterable, Identifiable {
    case blue = "blue"
    case green = "green"
    case orange = "orange"
    case red = "red"
    case purple = "purple"
    case pink = "pink"
    case teal = "teal"
    case indigo = "indigo"
    case mint = "mint"
    case cyan = "cyan"
    case yellow = "yellow"
    case gray = "gray"
    
    var id: String { rawValue }
    
    var name: String { rawValue }
    
    var color: Color {
        switch self {
        case .blue: return Color.blue
        case .green: return Color.green
        case .orange: return Color.orange
        case .red: return Color.red
        case .purple: return Color.purple
        case .pink: return Color.pink
        case .teal: 
            if #available(iOS 15.0, *) {
                return Color.teal
            } else {
                return Color(red: 0.18, green: 0.8, blue: 0.8)
            }
        case .indigo:
            if #available(iOS 15.0, *) {
                return Color.indigo
            } else {
                return Color(red: 0.29, green: 0.0, blue: 0.51)
            }
        case .mint:
            if #available(iOS 15.0, *) {
                return Color.mint
            } else {
                return Color(red: 0.0, green: 0.78, blue: 0.75)
            }
        case .cyan:
            if #available(iOS 15.0, *) {
                return Color.cyan
            } else {
                return Color(red: 0.0, green: 0.73, blue: 1.0)
            }
        case .yellow: return Color.yellow
        case .gray: return Color.gray
        }
    }
    
    var displayName: String {
        switch self {
        case .blue: return "Blue"
        case .green: return "Green"
        case .orange: return "Orange"
        case .red: return "Red"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        case .mint: return "Mint"
        case .cyan: return "Cyan"
        case .yellow: return "Yellow"
        case .gray: return "Gray"
        }
    }
    
    // Native iOS folder-like icon
    var iconName: String {
        "folder.fill"
    }
}
