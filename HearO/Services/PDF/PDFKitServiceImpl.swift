import Foundation
import PDFKit

final class PDFKitServiceImpl: PDFService {
    func buildPDF(for session: Session) throws -> URL {
        // MVP stub: Create a blank PDF and return its URL
        let pdfDoc = PDFDocument()
        let page = PDFPage()
        pdfDoc.insert(page, at: 0)
        let url = try AudioFileStore.url(for: session.id).deletingPathExtension().appendingPathExtension("pdf")
        pdfDoc.write(to: url)
        return url
    }
}
