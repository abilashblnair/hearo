import Foundation

enum HighlightKind: String, Codable { case actionItem, decision, quote, fact }

struct HighlightItem: Identifiable, Hashable, Codable {
    let id: UUID
    var kind: HighlightKind
    var text: String
    var dueDate: Date?
}
