import Foundation
import PDFKit
import UIKit
import CoreText

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
        let pdfDoc = PDFDocument()
        
        // Create the PDF content using NSAttributedString
        let content = buildPDFContent(from: summary, sessionDuration: sessionDuration, sessionTitle: sessionTitle)
        
        // Create PDF data from attributed string
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        let pdfData = NSMutableData()
        
        UIGraphicsBeginPDFContextToData(pdfData, pageRect, nil)
        
        let textRect = pageRect.insetBy(dx: 50, dy: 50) // Add margins
        var currentY: CGFloat = textRect.minY
        
        // Draw content with pagination
        let maxHeight = textRect.height - 50 // Leave space for page numbers
        let pageContext = UIGraphicsGetCurrentContext()!
        
        drawPDFContent(content, in: textRect, context: pageContext, startY: &currentY, maxHeight: maxHeight, pageRect: pageRect)
        
        UIGraphicsEndPDFContext()
        
        // Save PDF to file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let fileName = "Summary_\(Date().timeIntervalSince1970).pdf"
        let url = documentsPath.appendingPathComponent(fileName)
        
        try pdfData.write(to: url)
        
        return url
    }
    
    private func buildPDFContent(from summary: Summary, sessionDuration: TimeInterval?, sessionTitle: String?) -> NSAttributedString {
        let content = NSMutableAttributedString()
        
        // Title
        let title = sessionTitle ?? "Meeting Summary"
        content.append(styledText(title, style: .title))
        content.append(NSAttributedString(string: "\n\n"))
        
        // Metadata
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        content.append(styledText("Generated: \(dateFormatter.string(from: summary.generatedAt))", style: .metadata))
        
        if let duration = sessionDuration, duration > 0 {
            content.append(styledText("\nDuration: \(formatDuration(duration))", style: .metadata))
        }
        content.append(NSAttributedString(string: "\n\n"))
        
        // Overview
        if !summary.overview.isEmpty {
            content.append(styledText("📋 Overview", style: .heading))
            content.append(NSAttributedString(string: "\n"))
            content.append(styledText(summary.overview, style: .body))
            content.append(NSAttributedString(string: "\n\n"))
        }
        
        // Key Points
        if !summary.keyPoints.isEmpty {
            content.append(styledText("🔑 Key Points", style: .heading))
            content.append(NSAttributedString(string: "\n"))
            for point in summary.keyPoints {
                content.append(styledText("• \(point.text)", style: .body))
                content.append(NSAttributedString(string: "\n"))
            }
            content.append(NSAttributedString(string: "\n"))
        }
        
        // Action Items
        if !summary.actionItems.isEmpty {
            content.append(styledText("✅ Action Items", style: .heading))
            content.append(NSAttributedString(string: "\n"))
            for item in summary.actionItems {
                content.append(styledText("• \(item.text)", style: .body))
                
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
                    content.append(styledText(" (\(details.joined(separator: ", ")))", style: .metadata))
                }
                
                content.append(NSAttributedString(string: "\n"))
            }
            content.append(NSAttributedString(string: "\n"))
        }
        
        // Decisions
        if !summary.decisions.isEmpty {
            content.append(styledText("🎯 Decisions", style: .heading))
            content.append(NSAttributedString(string: "\n"))
            for decision in summary.decisions {
                content.append(styledText("• \(decision.text)", style: .body))
                if let impact = decision.impact {
                    content.append(styledText(" (Impact: \(impact.rawValue.capitalized))", style: .metadata))
                }
                content.append(NSAttributedString(string: "\n"))
            }
            content.append(NSAttributedString(string: "\n"))
        }
        
        // Notable Quotes
        if !summary.quotes.isEmpty {
            content.append(styledText("💬 Notable Quotes", style: .heading))
            content.append(NSAttributedString(string: "\n"))
            for quote in summary.quotes {
                content.append(styledText("\"\(quote.text)\"", style: .quote))
                if let speaker = quote.speaker {
                    content.append(styledText(" — \(speaker)", style: .metadata))
                }
                if let context = quote.context {
                    content.append(styledText(" (\(context))", style: .metadata))
                }
                content.append(NSAttributedString(string: "\n\n"))
            }
        }
        
        // Timeline
        if !summary.timeline.isEmpty {
            content.append(styledText("⏱️ Timeline", style: .heading))
            content.append(NSAttributedString(string: "\n"))
            for entry in summary.timeline {
                content.append(styledText("• \(entry.text)", style: .body))
                if let importance = entry.importance {
                    content.append(styledText(" (\(importance.rawValue.capitalized) importance)", style: .metadata))
                }
                content.append(NSAttributedString(string: "\n"))
            }
        }
        
        return content
    }
    
    private enum TextStyle {
        case title, heading, body, metadata, quote
    }
    
    private func styledText(_ text: String, style: TextStyle) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any]
        
        switch style {
        case .title:
            attributes = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
        case .heading:
            attributes = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black
            ]
        case .body:
            attributes = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.black
            ]
        case .metadata:
            attributes = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.gray
            ]
        case .quote:
            attributes = [
                .font: UIFont.italicSystemFont(ofSize: 12),
                .foregroundColor: UIColor.darkGray
            ]
        }
        
        return NSAttributedString(string: text, attributes: attributes)
    }
    
    private func drawPDFContent(_ content: NSAttributedString, in rect: CGRect, context: CGContext, startY: inout CGFloat, maxHeight: CGFloat, pageRect: CGRect) {
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        var currentRange = CFRange(location: 0, length: content.length)
        var pageNumber = 1
        
        while currentRange.location < content.length {
            UIGraphicsBeginPDFPage()
            
            let frameRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: maxHeight)
            let path = CGPath(rect: frameRect, transform: nil)
            
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            
            // Flip coordinate system for PDF
            context.saveGState()
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -rect.maxY)
            
            CTFrameDraw(frame, context)
            
            context.restoreGState()
            
            // Draw page number
            let pageNumberText = "Page \(pageNumber)"
            let pageAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.gray
            ]
            let pageAttrString = NSAttributedString(string: pageNumberText, attributes: pageAttributes)
            let pageSize = pageAttrString.boundingRect(with: CGSize(width: 200, height: 20), options: [], context: nil)
            let pageY = rect.maxY - 30
            pageAttrString.draw(at: CGPoint(x: rect.midX - pageSize.width/2, y: pageY))
            
            // Get the range that was actually drawn
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += visibleRange.length
            currentRange.length = content.length - currentRange.location
            
            // Break if no more content to draw
            if visibleRange.length == 0 || currentRange.length <= 0 {
                break
            }
            
            pageNumber += 1
        }
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
