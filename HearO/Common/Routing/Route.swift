import Foundation

enum Route: Hashable {
    case record
    case transcript(Session.ID)
    case pdfPreview(Session.ID)
    case settings
}
