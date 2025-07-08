import Foundation
import Combine

class SECAPIClient: ObservableObject {
    static let shared = SECAPIClient()
    
    private let baseURL = "https://www.sec.gov"
    private let dataURL = "https://data.sec.gov"
    private let rateLimitDelay: TimeInterval = 0.1 // 10 requests per second
    private var lastRequestTime = Date()
    
    private let session: URLSession
    private let decoder = JSONDecoder()
    
    private let companyName: String
    private let email: String
    
    init(companyName: String = "SECFilingsDownloader", email: String = "user@example.com") {
        self.companyName = companyName
        self.email = email
        
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "\(companyName) \(email)",
            "Accept-Encoding": "gzip, deflate",
            "Accept": "application/json, text/plain, */*"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Rate Limiting
    
    private func enforceRateLimit() async {
        let timeSinceLastRequest = Date().timeIntervalSince(lastRequestTime)
        if timeSinceLastRequest < rateLimitDelay {
            try? await Task.sleep(nanoseconds: UInt64((rateLimitDelay - timeSinceLastRequest) * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
    
    // MARK: - API Methods
    
    func getCIK(for ticker: String) async throws -> String? {
        await enforceRateLimit()
        
        let url = URL(string: "\(baseURL)/files/company_tickers.json")!
        let (data, _) = try await session.data(from: url)
        
        let tickers = try decoder.decode([String: CompanyTicker].self, from: data)
        
        for (_, company) in tickers {
            if company.ticker.uppercased() == ticker.uppercased() {
                return String(format: "%010d", company.cik_str)
            }
        }
        
        return nil
    }
    
    func getSubmissions(for cik: String) async throws -> Submissions {
        await enforceRateLimit()
        
        let paddedCIK = String(format: "%010d", Int(cik) ?? 0)
        let url = URL(string: "\(dataURL)/submissions/CIK\(paddedCIK).json")!
        
        let (data, _) = try await session.data(from: url)
        return try decoder.decode(Submissions.self, from: data)
    }
    
    func filterFilings(from submissions: Submissions,
                      formTypes: [String],
                      startDate: Date,
                      endDate: Date) -> [Filing] {
        
        var filteredFilings: [Filing] = []
        let recent = submissions.filings.recent
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for i in 0..<recent.form.count {
            let form = recent.form[i]
            let filingDateStr = recent.filingDate[i]
            
            // Check if form type matches any of the selected types
            let matchesFormType = formTypes.contains { formType in
                form.uppercased().contains(formType.uppercased())
            }
            
            if matchesFormType {
                if let filingDate = dateFormatter.date(from: filingDateStr),
                   filingDate >= startDate && filingDate <= endDate {
                    
                    filteredFilings.append(Filing(
                        form: form,
                        filingDate: filingDateStr,
                        accessionNumber: recent.accessionNumber[i],
                        primaryDocument: recent.primaryDocument[i],
                        reportDate: recent.reportDate?[i]
                    ))
                }
            }
        }
        
        // Sort by filing date (newest first)
        filteredFilings.sort { $0.filingDate > $1.filingDate }
        
        return filteredFilings
    }
    
    func constructFilingURL(cik: String, accessionNumber: String, primaryDocument: String) -> URL {
        let paddedCIK = String(format: "%010d", Int(cik) ?? 0)
        let accessionNoDash = accessionNumber.replacingOccurrences(of: "-", with: "")
        
        let urlString = "\(baseURL)/Archives/edgar/data/\(paddedCIK)/\(accessionNoDash)/\(primaryDocument)"
        return URL(string: urlString)!
    }
    
    func downloadFiling(from url: URL, to localURL: URL) async throws {
        await enforceRateLimit()
        
        let (data, _) = try await session.data(from: url)
        
        // Create directory if needed
        let directory = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Write file
        try data.write(to: localURL)
    }
    
    // MARK: - Helper Methods
    
    private func sanitizeFilename(_ filename: String) -> String {
        // Replace invalid filename characters
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let components = filename.components(separatedBy: invalidCharacters)
        return components.joined(separator: "-")
    }
    
    // MARK: - Main Download Method
    
    func downloadFilings(tickerOrCIK: String,
                        formTypes: [String],
                        startDate: Date,
                        endDate: Date,
                        outputDirectory: URL,
                        convertToPDF: Bool = false,
                        keepOriginalHTML: Bool = false,
                        progressHandler: @escaping (Double, String) -> Void) async throws -> (successful: Int, total: Int) {
        
        // Get CIK
        let cik: String
        if tickerOrCIK.allSatisfy({ $0.isNumber }) {
            cik = String(format: "%010d", Int(tickerOrCIK) ?? 0)
        } else {
            guard let foundCIK = try await getCIK(for: tickerOrCIK) else {
                throw NSError(domain: "SECAPIClient", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Could not find CIK for ticker \(tickerOrCIK)"])
            }
            cik = foundCIK
        }
        
        progressHandler(0.1, "Fetching company submissions...")
        
        // Get submissions
        let submissions = try await getSubmissions(for: cik)
        let companyName = submissions.name
        let ticker = tickerOrCIK.allSatisfy({ $0.isNumber }) ? (submissions.tickers.first ?? "") : tickerOrCIK
        
        progressHandler(0.2, "Filtering filings...")
        
        // Filter filings
        let filings = filterFilings(from: submissions,
                                   formTypes: formTypes,
                                   startDate: startDate,
                                   endDate: endDate)
        
        if filings.isEmpty {
            return (0, 0)
        }
        
        // Create company directory (just using ticker for cleaner structure)
        let companyDir = outputDirectory
            .appendingPathComponent(ticker.uppercased())
        
        var successful = 0
        
        for (index, filing) in filings.enumerated() {
            let progress = 0.2 + (0.8 * Double(index) / Double(filings.count))
            progressHandler(progress, "Downloading \(filing.form) from \(filing.filingDate)...")
            
            // Create form type directory
            let cleanFormType = sanitizeFilename(filing.form.replacingOccurrences(of: " ", with: "_"))
            let formDir = companyDir.appendingPathComponent(cleanFormType)
            
            // Construct URL
            let url = constructFilingURL(cik: cik,
                                       accessionNumber: filing.accessionNumber,
                                       primaryDocument: filing.primaryDocument)
            
            // Create beautified filename
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let date = dateFormatter.date(from: filing.filingDate) ?? Date()
            
            dateFormatter.dateFormat = "dd.MM.yyyy"
            let formattedDate = dateFormatter.string(from: date)
            
            // Clean filing form for filename (remove spaces but keep it readable)
            let cleanFilingForm = filing.form.replacingOccurrences(of: " ", with: "")
            
            // Format: "TICKER FILING-TYPE DATE.extension"
            let fileExtension = filing.primaryDocument.components(separatedBy: ".").last ?? "htm"
            let baseFilename = "\(ticker.uppercased()) \(cleanFilingForm) \(formattedDate).\(fileExtension)"
            let beautifiedFilename = sanitizeFilename(baseFilename)
            let localURL = formDir.appendingPathComponent(beautifiedFilename)
            
            do {
                try await downloadFiling(from: url, to: localURL)
                
                // Convert to PDF if requested
                if convertToPDF && (filing.primaryDocument.hasSuffix(".htm") || filing.primaryDocument.hasSuffix(".html")) {
                    progressHandler(progress, "Converting \(filing.form) to PDF...")
                    
                    // Use same beautified filename but with .pdf extension
                    let pdfBaseFilename = "\(ticker.uppercased()) \(cleanFilingForm) \(formattedDate).pdf"
                    let pdfFilename = sanitizeFilename(pdfBaseFilename)
                    let pdfURL = formDir.appendingPathComponent(pdfFilename)
                    
                    // Perform PDF conversion
                    let conversionSuccess = await convertHTMLToPDF(from: localURL, to: pdfURL)
                    
                    // Delete original HTML if conversion was successful and not keeping it
                    if conversionSuccess && !keepOriginalHTML {
                        try? FileManager.default.removeItem(at: localURL)
                    }
                }
                
                // Note: JSON metadata files are no longer created per user request
                
                successful += 1
            } catch {
                print("Failed to download \(filing.form): \(error)")
            }
        }
        
        progressHandler(1.0, "Download complete!")
        
        return (successful, filings.count)
    }
}
