import Foundation
import PDFKit
import UIKit

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
    
    func buildPDF(from summary: Summary, sessionDuration: TimeInterval?, sessionTitle: String?) throws -> URL {
        // Create PDF data
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let pdfData = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        
        let margin: CGFloat = 50
        let textRect = pageRect.insetBy(dx: margin, dy: margin)
        
        // Draw content using simple text rendering approach
        drawPDFContentSimple(summary: summary, sessionDuration: sessionDuration, sessionTitle: sessionTitle, textRect: textRect, pageRect: pageRect)
        
        UIGraphicsEndPDFContext()
        
        // Save PDF to file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "Summary_\(Date().timeIntervalSince1970).pdf"
        let url = documentsPath.appendingPathComponent(fileName)
        
        try pdfData.write(to: url)
        
        return url
    }
    
    private func drawPDFContentSimple(summary: Summary, sessionDuration: TimeInterval?, sessionTitle: String?, textRect: CGRect, pageRect: CGRect) {
        var currentY: CGFloat = textRect.minY
        let lineHeight: CGFloat = 20
        let sectionSpacing: CGFloat = 30
        let itemSpacing: CGFloat = 15
        let pageBottomMargin: CGFloat = 80
        var pageNumber = 1
        
        // Helper function to check if we need a new page
        func checkNewPage() {
            if currentY + lineHeight > pageRect.height - pageBottomMargin {
                drawPageNumber(pageNumber, in: pageRect)
                pageNumber += 1
                UIGraphicsBeginPDFPage()
                currentY = textRect.minY
            }
        }
        
        // Helper function to draw text with style
        func drawText(_ text: String, font: UIFont, color: UIColor = .black) {
            checkNewPage()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color
            ]
            let attributedText = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributedText.boundingRect(with: CGSize(width: textRect.width, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
            
            attributedText.draw(in: CGRect(x: textRect.minX, y: currentY, width: textRect.width, height: textSize.height))
            currentY += textSize.height + itemSpacing
        }
        
        // Start first page
        UIGraphicsBeginPDFPage()
        
        // Title
        let title = sessionTitle ?? "Meeting Summary"
        drawText(title, font: .boldSystemFont(ofSize: 24))
        currentY += 10
        
        // Metadata
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        drawText("Generated: \(dateFormatter.string(from: summary.generatedAt))", font: .systemFont(ofSize: 10), color: .gray)
        
        if let duration = sessionDuration, duration > 0 {
            drawText("Duration: \(formatDuration(duration))", font: .systemFont(ofSize: 10), color: .gray)
        }
        
        currentY += sectionSpacing
        
        // Overview
        if !summary.overview.isEmpty {
            drawText("📋 Overview", font: .boldSystemFont(ofSize: 18))
            drawText(summary.overview, font: .systemFont(ofSize: 12))
            currentY += sectionSpacing
        }
        
        // Key Points
        if !summary.keyPoints.isEmpty {
            drawText("🔑 Key Points", font: .boldSystemFont(ofSize: 18))
            for point in summary.keyPoints {
                drawText("• \(point.text)", font: .systemFont(ofSize: 12))
            }
            currentY += sectionSpacing
        }
        
        // Action Items
        if !summary.actionItems.isEmpty {
            drawText("✅ Action Items", font: .boldSystemFont(ofSize: 18))
            for item in summary.actionItems {
                var itemText = "• \(item.text)"
                
                var details: [String] = []
                if let owner = item.owner {
                    details.append("@\(owner)")
                }
                if let dueDate = item.dueDateFormatted {
                    details.append("Due: \(dueDate)")
                }
                if let priority = item.priority {
                    details.append("Priority: \(priority.rawValue.capitalized)")
                }
                
                if !details.isEmpty {
                    itemText += " (\(details.joined(separator: ", ")))"
                }
                
                drawText(itemText, font: .systemFont(ofSize: 12))
            }
            currentY += sectionSpacing
        }
        
        // Decisions
        if !summary.decisions.isEmpty {
            drawText("🎯 Decisions", font: .boldSystemFont(ofSize: 18))
            for decision in summary.decisions {
                var decisionText = "• \(decision.text)"
                if let impact = decision.impact {
                    decisionText += " (Impact: \(impact.rawValue.capitalized))"
                }
                drawText(decisionText, font: .systemFont(ofSize: 12))
            }
            currentY += sectionSpacing
        }
        
        // Notable Quotes
        if !summary.quotes.isEmpty {
            drawText("💬 Notable Quotes", font: .boldSystemFont(ofSize: 18))
            for quote in summary.quotes {
                var quoteText = "\"\(quote.text)\""
                if let speaker = quote.speaker {
                    quoteText += " — \(speaker)"
                }
                if let context = quote.context {
                    quoteText += " (\(context))"
                }
                drawText(quoteText, font: .italicSystemFont(ofSize: 12), color: .darkGray)
            }
            currentY += sectionSpacing
        }
        
        // Timeline
        if !summary.timeline.isEmpty {
            drawText("⏱️ Timeline", font: .boldSystemFont(ofSize: 18))
            for entry in summary.timeline {
                var timelineText = "• \(entry.text)"
                if let importance = entry.importance {
                    timelineText += " (\(importance.rawValue.capitalized) importance)"
                }
                drawText(timelineText, font: .systemFont(ofSize: 12))
            }
        }
        
        // Draw final page number
        drawPageNumber(pageNumber, in: pageRect)
    }
    
    private func drawPageNumber(_ pageNumber: Int, in pageRect: CGRect) {
        let pageNumberText = "Page \(pageNumber)"
        let pageAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray
        ]
        let pageAttrString = NSAttributedString(string: pageNumberText, attributes: pageAttributes)
        let pageSize = pageAttrString.boundingRect(with: CGSize(width: 200, height: 20), options: [], context: nil)
        let pageNumberY = pageRect.height - 30
        let pageNumberX = (pageRect.width - pageSize.width) / 2
        pageAttrString.draw(at: CGPoint(x: pageNumberX, y: pageNumberY))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration <= 0 {
            return "Unknown"
        }
        
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

