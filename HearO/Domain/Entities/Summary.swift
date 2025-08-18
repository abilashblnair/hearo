import Foundation

/// Structured meeting summary with timestamped references
struct Summary: Codable, Identifiable, Hashable {
    let id: UUID
    var overview: String                 // 2–3 sentences, plain text
    var keyPoints: [Point]               // bullets
    var actionItems: [ActionItem]        // tasks
    var decisions: [Decision]
    var quotes: [Quote]
    var timeline: [TimelineEntry]        // optional chronological events
    var generatedAt: Date
    var locale: String
    
    // Custom coding keys - exclude runtime properties from API response
    private enum CodingKeys: String, CodingKey {
        case overview
        case keyPoints
        case actionItems
        case decisions
        case quotes
        case timeline
        // Exclude: id, generatedAt, locale from decoding
    }
    
    init(overview: String = "",
         keyPoints: [Point] = [],
         actionItems: [ActionItem] = [],
         decisions: [Decision] = [],
         quotes: [Quote] = [],
         timeline: [TimelineEntry] = [],
         generatedAt: Date = Date(),
         locale: String = "en-US") {
        self.id = UUID()
        self.overview = overview
        self.keyPoints = keyPoints
        self.actionItems = actionItems
        self.decisions = decisions
        self.quotes = quotes
        self.timeline = timeline
        self.generatedAt = generatedAt
        self.locale = locale
    }
    
    // Custom decoder to handle API response without id, generatedAt, locale
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode from API response
        overview = try container.decode(String.self, forKey: .overview)
        keyPoints = try container.decode([Point].self, forKey: .keyPoints)
        actionItems = try container.decode([ActionItem].self, forKey: .actionItems)
        decisions = try container.decode([Decision].self, forKey: .decisions)
        quotes = try container.decode([Quote].self, forKey: .quotes)
        timeline = try container.decodeIfPresent([TimelineEntry].self, forKey: .timeline) ?? []
        
        // Set default values for runtime properties
        id = UUID()
        generatedAt = Date()
        locale = "en-US" // Default, can be overridden
    }
    
    // Custom encoder to handle saving to local storage
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(overview, forKey: .overview)
        try container.encode(keyPoints, forKey: .keyPoints)
        try container.encode(actionItems, forKey: .actionItems)
        try container.encode(decisions, forKey: .decisions)
        try container.encode(quotes, forKey: .quotes)
        try container.encode(timeline, forKey: .timeline)
        
        // Note: id, generatedAt, locale are not encoded for API compatibility
    }
    
    struct Point: Codable, Identifiable, Hashable {
        let id: UUID
        var text: String
        var refs: [Ref]?
        
        private enum CodingKeys: String, CodingKey {
            case text
            case refs
        }
        
        init(text: String, refs: [Ref]? = nil) {
            self.id = UUID()
            self.text = text
            self.refs = refs
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            text = try container.decode(String.self, forKey: .text)
            refs = try container.decodeIfPresent([Ref].self, forKey: .refs)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(refs, forKey: .refs)
        }
    }
    
    struct ActionItem: Codable, Identifiable, Hashable {
        let id: UUID
        var text: String
        var owner: String?               // "Alice" if detected
        var dueDateISO8601: String?      // "2025-08-20"
        var priority: Priority?
        var status: Status
        var refs: [Ref]?
        
        private enum CodingKeys: String, CodingKey {
            case text
            case owner
            case dueDateISO8601
            case priority
            case status
            case refs
        }
        
        init(text: String, owner: String? = nil, dueDateISO8601: String? = nil, priority: Priority? = nil, status: Status = .pending, refs: [Ref]? = nil) {
            self.id = UUID()
            self.text = text
            self.owner = owner
            self.dueDateISO8601 = dueDateISO8601
            self.priority = priority
            self.status = status
            self.refs = refs
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            text = try container.decode(String.self, forKey: .text)
            owner = try container.decodeIfPresent(String.self, forKey: .owner)
            dueDateISO8601 = try container.decodeIfPresent(String.self, forKey: .dueDateISO8601)
            priority = try container.decodeIfPresent(Priority.self, forKey: .priority)
            status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .pending
            refs = try container.decodeIfPresent([Ref].self, forKey: .refs)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(owner, forKey: .owner)
            try container.encodeIfPresent(dueDateISO8601, forKey: .dueDateISO8601)
            try container.encodeIfPresent(priority, forKey: .priority)
            try container.encode(status, forKey: .status)
            try container.encodeIfPresent(refs, forKey: .refs)
        }
        
        enum Priority: String, Codable, CaseIterable {
            case low = "low"
            case medium = "medium"
            case high = "high"
            case urgent = "urgent"
            
            var color: String {
                switch self {
                case .low: return "blue"
                case .medium: return "orange"
                case .high: return "red"
                case .urgent: return "purple"
                }
            }
        }
        
        enum Status: String, Codable, CaseIterable {
            case pending = "pending"
            case inProgress = "in_progress"
            case completed = "completed"
            case cancelled = "cancelled"
        }
        
        var dueDateFormatted: String? {
            guard let dueDateISO8601 = dueDateISO8601 else { return nil }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dueDateISO8601) {
                formatter.dateStyle = .medium
                return formatter.string(from: date)
            }
            return dueDateISO8601
        }
    }
    
    struct Decision: Codable, Identifiable, Hashable {
        let id: UUID
        var text: String
        var impact: Impact?
        var refs: [Ref]?
        
        private enum CodingKeys: String, CodingKey {
            case text
            case impact
            case refs
        }
        
        init(text: String, impact: Impact? = nil, refs: [Ref]? = nil) {
            self.id = UUID()
            self.text = text
            self.impact = impact
            self.refs = refs
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            text = try container.decode(String.self, forKey: .text)
            impact = try container.decodeIfPresent(Impact.self, forKey: .impact)
            refs = try container.decodeIfPresent([Ref].self, forKey: .refs)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(impact, forKey: .impact)
            try container.encodeIfPresent(refs, forKey: .refs)
        }
        
        enum Impact: String, Codable, CaseIterable {
            case low = "low"
            case medium = "medium"
            case high = "high"
        }
    }
    
    struct Quote: Codable, Identifiable, Hashable {
        let id: UUID
        var speaker: String?
        var text: String
        var context: String?             // Brief context if helpful
        var refs: [Ref]?
        
        private enum CodingKeys: String, CodingKey {
            case speaker
            case text
            case context
            case refs
        }
        
        init(speaker: String? = nil, text: String, context: String? = nil, refs: [Ref]? = nil) {
            self.id = UUID()
            self.speaker = speaker
            self.text = text
            self.context = context
            self.refs = refs
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            speaker = try container.decodeIfPresent(String.self, forKey: .speaker)
            text = try container.decode(String.self, forKey: .text)
            context = try container.decodeIfPresent(String.self, forKey: .context)
            refs = try container.decodeIfPresent([Ref].self, forKey: .refs)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(speaker, forKey: .speaker)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(context, forKey: .context)
            try container.encodeIfPresent(refs, forKey: .refs)
        }
    }
    
    struct TimelineEntry: Codable, Identifiable, Hashable {
        let id: UUID
        var at: String                   // "00:12:34" or "12:34 PM"
        var text: String
        var importance: Importance?
        
        private enum CodingKeys: String, CodingKey {
            case at
            case text
            case importance
        }
        
        init(at: String, text: String, importance: Importance? = nil) {
            self.id = UUID()
            self.at = at
            self.text = text
            self.importance = importance
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            at = try container.decode(String.self, forKey: .at)
            text = try container.decode(String.self, forKey: .text)
            importance = try container.decodeIfPresent(Importance.self, forKey: .importance)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(at, forKey: .at)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(importance, forKey: .importance)
        }
        
        enum Importance: String, Codable, CaseIterable {
            case low = "low"
            case medium = "medium" 
            case high = "high"
        }
    }
    
    /// Timestamp reference with start/end times for seeking in transcript
    struct Ref: Codable, Identifiable, Hashable {
        let id: UUID
        var start: String                // "HH:MM:SS"
        var end: String                  // "HH:MM:SS"
        
        private enum CodingKeys: String, CodingKey {
            case start
            case end
        }
        
        init(start: String, end: String) {
            self.id = UUID()
            self.start = start
            self.end = end
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = UUID()
            start = try container.decode(String.self, forKey: .start)
            end = try container.decode(String.self, forKey: .end)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        }
        
        var startTimeInterval: TimeInterval? {
            return timeInterval(from: start)
        }
        
        var endTimeInterval: TimeInterval? {
            return timeInterval(from: end)
        }
        
        private func timeInterval(from timeString: String) -> TimeInterval? {
            let components = timeString.split(separator: ":").compactMap { Int($0) }
            guard components.count == 3 else { return nil }
            let hours = components[0]
            let minutes = components[1]
            let seconds = components[2]
            return TimeInterval(hours * 3600 + minutes * 60 + seconds)
        }
        
        var duration: TimeInterval {
            guard let start = startTimeInterval, let end = endTimeInterval else { return 0 }
            return end - start
        }
        
        var formattedRange: String {
            return "\(start) - \(end)"
        }
    }
}

// MARK: - Summary Extensions
extension Summary {
    var isEmpty: Bool {
        return overview.isEmpty && 
               keyPoints.isEmpty && 
               actionItems.isEmpty && 
               decisions.isEmpty && 
               quotes.isEmpty && 
               timeline.isEmpty
    }
    
    var totalItems: Int {
        return keyPoints.count + actionItems.count + decisions.count + quotes.count + timeline.count
    }
    
    var pendingActionItems: [ActionItem] {
        return actionItems.filter { $0.status == .pending }
    }
    
    var urgentActionItems: [ActionItem] {
        return actionItems.filter { $0.priority == .urgent || $0.priority == .high }
    }
    
    var sharingText: String {
        var text = "📄 Meeting Summary\n\n"
        
        if !overview.isEmpty {
            text += "📋 Overview:\n\(overview)\n\n"
        }
        
        if !keyPoints.isEmpty {
            text += "🔑 Key Points:\n"
            for point in keyPoints {
                text += "• \(point.text)\n"
            }
            text += "\n"
        }
        
        if !actionItems.isEmpty {
            text += "✅ Action Items:\n"
            for item in actionItems {
                var line = "• \(item.text)"
                if let owner = item.owner {
                    line += " (@\(owner))"
                }
                if let date = item.dueDateFormatted {
                    line += " - Due: \(date)"
                }
                text += line + "\n"
            }
            text += "\n"
        }
        
        if !decisions.isEmpty {
            text += "🎯 Decisions:\n"
            for decision in decisions {
                text += "• \(decision.text)\n"
            }
            text += "\n"
        }
        
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - TimeInterval Extensions for Formatting
extension TimeInterval {
    func formattedHMS() -> String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
    
    func formattedMS() -> String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
