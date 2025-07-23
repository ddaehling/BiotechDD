import Foundation
import os.log

extension SECAPIClient {
    
    // MARK: - Merge HTML Files
    
    func mergeHTMLFilesByType(in companyDirectory: URL, ticker: String, formTypes: [String], filings: [Filing]) async throws {
        for formType in formTypes {
            let cleanFormType = sanitizeFilename(formType.replacingOccurrences(of: " ", with: "_"))
            let formDir = companyDirectory.appendingPathComponent(cleanFormType)
            
            // Only merge if directory exists
            guard FileManager.default.fileExists(atPath: formDir.path) else { continue }
            
            // Get filings of this type
            let filingsOfType = filings.filter { filing in
                filing.form.uppercased().contains(formType.uppercased())
            }
            
            if let mergedFileURL = try await mergeHTMLFiles(
                in: formDir,
                formType: formType,
                ticker: ticker,
                filings: filingsOfType
            ) {
                if #available(macOS 11.0, *) {
                    Logger.merge.info("Created merged file: \(mergedFileURL.lastPathComponent)")
                }
            }
        }
    }
    
    private func mergeHTMLFiles(in directory: URL, formType: String, ticker: String, filings: [Filing]) async throws -> URL? {
        let fileManager = FileManager.default
        
        // Get all HTML files in the directory
        let htmlFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "htm" || $0.pathExtension == "html" }
            .sorted { url1, url2 in
                // Sort by date in filename (newest first)
                return url1.lastPathComponent > url2.lastPathComponent
            }
        
        guard htmlFiles.count > 1 else {
            // No need to merge if there's only one file
            return nil
        }
        
        // Create merged filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let today = dateFormatter.string(from: Date())
        let cleanFormType = formType.replacingOccurrences(of: " ", with: "")
        let mergedFilename = "\(ticker.uppercased())_\(cleanFormType)_MERGED_\(today).html"
        let mergedFileURL = directory.appendingPathComponent(mergedFilename)
        
        // Build merged HTML content
        let mergedHTML = try buildMergedHTML(
            from: htmlFiles,
            formType: formType,
            ticker: ticker,
            filings: filings
        )
        
        // Write merged file
        try mergedHTML.write(to: mergedFileURL, atomically: true, encoding: .utf8)
        
        // Delete individual HTML files after successful merge
        for htmlFile in htmlFiles {
            try? fileManager.removeItem(at: htmlFile)
        }
        
        return mergedFileURL
    }
    
    private func buildMergedHTML(from files: [URL], formType: String, ticker: String, filings: [Filing]) throws -> String {
        var mergedContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <title>\(ticker.uppercased()) - \(formType) Merged Filings</title>
            <style>
                body {
                    font-family: -apple-system, system-ui, 'Helvetica Neue', Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 1200px;
                    margin: 0 auto;
                    padding: 20px;
                    background-color: #f5f5f5;
                }
                .header {
                    background-color: #003366;
                    color: white;
                    padding: 30px;
                    border-radius: 8px;
                    margin-bottom: 30px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
                .header h1 {
                    margin: 0;
                    font-size: 28px;
                }
                .header p {
                    margin: 10px 0 0 0;
                    opacity: 0.9;
                }
                .toc {
                    background-color: white;
                    border: 1px solid #ddd;
                    border-radius: 8px;
                    padding: 20px;
                    margin-bottom: 30px;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                }
                .toc h2 {
                    margin-top: 0;
                    color: #003366;
                    font-size: 20px;
                }
                .toc ul {
                    list-style-type: none;
                    padding-left: 0;
                }
                .toc li {
                    margin: 10px 0;
                    padding: 10px;
                    background-color: #f8f9fa;
                    border-radius: 4px;
                    transition: background-color 0.2s;
                }
                .toc li:hover {
                    background-color: #e9ecef;
                }
                .toc a {
                    text-decoration: none;
                    color: #003366;
                    display: block;
                    font-weight: 500;
                }
                .toc .filing-date {
                    color: #666;
                    font-size: 14px;
                    margin-left: 10px;
                }
                .filing-separator {
                    background-color: #003366;
                    color: white;
                    padding: 20px;
                    margin: 40px 0;
                    border-radius: 8px;
                    page-break-before: always;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                }
                .filing-separator h2 {
                    margin: 0;
                    font-size: 22px;
                }
                .filing-separator .meta {
                    margin-top: 10px;
                    font-size: 14px;
                    opacity: 0.9;
                }
                .filing-content {
                    background-color: white;
                    padding: 30px;
                    border-radius: 8px;
                    margin-bottom: 40px;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                }
                .filing-content table {
                    border-collapse: collapse;
                    width: 100%;
                    margin: 20px 0;
                }
                .filing-content td, .filing-content th {
                    border: 1px solid #ddd;
                    padding: 8px;
                    text-align: left;
                }
                .filing-content th {
                    background-color: #f2f2f2;
                    font-weight: bold;
                }
                /* Handle nested tables */
                .filing-content table table {
                    margin: 0;
                }
                @media print {
                    body {
                        background-color: white;
                    }
                    .toc {
                        page-break-after: always;
                    }
                    .filing-separator {
                        page-break-before: always;
                    }
                }
            </style>
        </head>
        <body>
        """
        
        // Add header
        mergedContent += """
            <div class="header">
                <h1>\(ticker.uppercased()) - \(formType) Filings</h1>
                <p>Combined SEC EDGAR Filings</p>
                <p>Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))</p>
                <p>Total Filings: \(files.count)</p>
            </div>
        """
        
        // Add table of contents
        mergedContent += """
            <div class="toc">
                <h2>Table of Contents</h2>
                <ul>
        """
        
        // Create a mapping of files to filings based on dates
        var fileFilingPairs: [(file: URL, filing: Filing?)] = []
        for file in files {
            // Try to extract date from filename
            let filename = file.lastPathComponent
            let filing = filings.first { filing in
                filename.contains(filing.filingDate.replacingOccurrences(of: "-", with: "."))
            }
            fileFilingPairs.append((file: file, filing: filing))
        }
        
        // Sort by filing date (newest first)
        fileFilingPairs.sort { pair1, pair2 in
            let date1 = pair1.filing?.filingDate ?? ""
            let date2 = pair2.filing?.filingDate ?? ""
            return date1 > date2
        }
        
        for (index, pair) in fileFilingPairs.enumerated() {
            let filing = pair.filing
            let displayDate = filing?.filingDate ?? "Unknown Date"
            let reportDate = filing?.reportDate ?? ""
            
            mergedContent += """
                    <li>
                        <a href="#filing-\(index + 1)">
                            \(formType) - Filed: \(displayDate)
                            \(reportDate.isEmpty ? "" : "<span class='filing-date'>Period: \(reportDate)</span>")
                        </a>
                    </li>
            """
        }
        
        mergedContent += """
                </ul>
            </div>
        """
        
        // Add each filing's content
        for (index, pair) in fileFilingPairs.enumerated() {
            let file = pair.file
            let filing = pair.filing
            
            let content = try String(contentsOf: file, encoding: .utf8)
            
            // Extract body content from HTML
            let bodyContent = extractBodyContent(from: content)
            
            mergedContent += """
                <div class="filing-separator" id="filing-\(index + 1)">
                    <h2>\(formType) Filing #\(index + 1)</h2>
                    <div class="meta">
                        <p><strong>Filing Date:</strong> \(filing?.filingDate ?? "Unknown")</p>
                        \(filing?.accessionNumber != nil ? "<p><strong>Accession Number:</strong> \(filing!.accessionNumber)</p>" : "")
                        \(filing?.reportDate != nil ? "<p><strong>Report Period:</strong> \(filing!.reportDate!)</p>" : "")
                        <p><strong>Original File:</strong> \(file.lastPathComponent)</p>
                    </div>
                </div>
                <div class="filing-content">
                    \(bodyContent)
                </div>
            """
        }
        
        // Close HTML
        mergedContent += """
        </body>
        </html>
        """
        
        return mergedContent
    }
    
    private func extractBodyContent(from html: String) -> String {
        // Try to extract content between <body> tags
        if let bodyRange = html.range(of: "<body[^>]*>", options: .regularExpression),
           let endBodyRange = html.range(of: "</body>", options: .caseInsensitive) {
            let startIndex = bodyRange.upperBound
            let endIndex = endBodyRange.lowerBound
            if startIndex < endIndex {
                return String(html[startIndex..<endIndex])
            }
        }
        
        // If no body tags, look for main content
        if html.contains("<html") {
            // It's a full HTML document but without body tags
            if let htmlRange = html.range(of: "<html[^>]*>", options: .regularExpression),
               let endHtmlRange = html.range(of: "</html>", options: .caseInsensitive) {
                let startIndex = htmlRange.upperBound
                let endIndex = endHtmlRange.lowerBound
                if startIndex < endIndex {
                    return String(html[startIndex..<endIndex])
                }
            }
        }
        
        // Return as-is if no standard HTML structure
        return html
    }
}
