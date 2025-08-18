import Foundation

protocol PDFService {
    func buildPDF(for session: Session) throws -> URL
}
