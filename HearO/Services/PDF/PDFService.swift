import Foundation

protocol PDFService {
    func buildPDF(for session: Session) throws -> URL
    func buildPDF(from summary: Summary, sessionDuration: TimeInterval?, sessionTitle: String?) throws -> URL
}
