import Foundation
import AppKit

extension SECAPIClient {
    func convertHTMLToPDF(from htmlURL: URL, to pdfURL: URL) async -> Bool {
        // Run the conversion on the main thread since it uses AppKit
        return await MainActor.run {
            convertUsingAttributedString(from: htmlURL, to: pdfURL)
        }
    }
    
    @MainActor
    private func convertUsingAttributedString(from htmlURL: URL, to pdfURL: URL) -> Bool {
        do {
            // Read HTML content
            let htmlContent = try String(contentsOf: htmlURL, encoding: .utf8)
            
            // Clean the HTML for better PDF rendering
            let cleanedHTML = cleanHTMLForPDF(htmlContent)
            
            guard let data = cleanedHTML.data(using: .utf8) else { return false }
            
            // Create attributed string from HTML
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            guard let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
                print("Failed to create attributed string from HTML")
                return false
            }
            
            // Create text view with attributed string
            let textView = NSTextView()
            textView.textStorage?.setAttributedString(attributedString)
            
            // Configure page layout
            let pageWidth: CGFloat = 540 // 612 - 72 (margins)
            let pageHeight: CGFloat = 720 // 792 - 72 (margins)
            
            // Set frame and layout
            textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            textView.textContainer?.containerSize = NSSize(width: pageWidth, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = false
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            
            // Force layout
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? NSRect.zero
            textView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: max(usedRect.height, pageHeight))
            
            // Generate PDF data
            let pdfData = textView.dataWithPDF(inside: textView.bounds)
            
            // Write to file
            try pdfData.write(to: pdfURL)
            return true
            
        } catch {
            print("PDF conversion error: \(error)")
            return false
        }
    }
    
    private func cleanHTMLForPDF(_ html: String) -> String {
        // Enhanced CSS for better PDF rendering
        let css = """
        <style>
            @charset "UTF-8";
            * {
                -webkit-print-color-adjust: exact !important;
                print-color-adjust: exact !important;
            }
            body {
                font-family: -apple-system, system-ui, 'Helvetica Neue', Arial, sans-serif;
                font-size: 11pt;
                line-height: 1.5;
                color: #000;
                background: #fff;
                margin: 0;
                padding: 20px;
                max-width: 100%;
            }
            h1, h2, h3, h4, h5, h6 {
                margin-top: 1em;
                margin-bottom: 0.5em;
                font-weight: bold;
            }
            h1 { font-size: 18pt; }
            h2 { font-size: 16pt; }
            h3 { font-size: 14pt; }
            h4 { font-size: 12pt; }
            p {
                margin: 0.5em 0;
            }
            table {
                border-collapse: collapse;
                width: 100%;
                margin: 1em 0;
                font-size: 10pt;
            }
            td, th {
                border: 1px solid #ccc;
                padding: 6px 8px;
                text-align: left;
            }
            th {
                background-color: #f0f0f0;
                font-weight: bold;
            }
            tr:nth-child(even) {
                background-color: #f9f9f9;
            }
            img {
                max-width: 100%;
                height: auto;
                display: block;
                margin: 10px 0;
            }
            pre {
                background-color: #f5f5f5;
                padding: 10px;
                border: 1px solid #ddd;
                border-radius: 4px;
                overflow-x: auto;
                white-space: pre-wrap;
                word-wrap: break-word;
                font-family: Menlo, Monaco, 'Courier New', monospace;
                font-size: 9pt;
            }
            code {
                background-color: #f5f5f5;
                padding: 2px 4px;
                border-radius: 3px;
                font-family: Menlo, Monaco, 'Courier New', monospace;
                font-size: 9pt;
            }
            a {
                color: #0066cc;
                text-decoration: underline;
            }
            blockquote {
                margin: 1em 0;
                padding-left: 1em;
                border-left: 3px solid #ccc;
                color: #666;
            }
            hr {
                border: none;
                border-top: 1px solid #ccc;
                margin: 1em 0;
            }
            /* Page break handling */
            h1, h2, h3 {
                page-break-after: avoid;
            }
            table, pre, blockquote {
                page-break-inside: avoid;
            }
            tr {
                page-break-inside: avoid;
                page-break-after: auto;
            }
        </style>
        """
        
        // Clean up common HTML issues
        var cleanedHTML = html
        
        // Remove any existing style tags to avoid conflicts
        cleanedHTML = cleanedHTML.replacingOccurrences(
            of: #"<style[^>]*>[\s\S]*?</style>"#,
            with: "",
            options: .regularExpression
        )
        
        // Insert our CSS
        if cleanedHTML.contains("</head>") {
            cleanedHTML = cleanedHTML.replacingOccurrences(of: "</head>", with: "\(css)\n</head>")
        } else if cleanedHTML.contains("<html>") {
            cleanedHTML = cleanedHTML.replacingOccurrences(of: "<html>", with: "<html>\n<head>\n<meta charset=\"UTF-8\">\n\(css)\n</head>")
        } else {
            cleanedHTML = """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="UTF-8">
            <title>SEC Filing</title>
            \(css)
            </head>
            <body>
            \(cleanedHTML)
            </body>
            </html>
            """
        }
        
        return cleanedHTML
    }
}
