import Foundation
import Combine
import os.log

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
        
        // Increase timeouts to prevent network warnings
        config.timeoutIntervalForRequest = 60  // Increased from default
        config.timeoutIntervalForResource = 300 // 5 minutes for large downloads
        
        // Configure TCP settings to reduce connection issues
        config.waitsForConnectivity = true
        config.allowsConstrainedNetworkAccess = true
        config.allowsExpensiveNetworkAccess = true
        
        // Set service type for better performance
        config.networkServiceType = .responsiveData
        
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
        
        let data = try await performRequestWithRetry {
            try await self.session.data(from: url).0
        }
        
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
        
        let data = try await performRequestWithRetry {
            try await self.session.data(from: url).0
        }
        
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
        
        let data = try await performRequestWithRetry {
            let (data, response) = try await self.session.data(from: url)
            
            // Verify we got a good response
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                throw NSError(
                    domain: "SECAPIClient",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) error"]
                )
            }
            
            return data
        }
        
        // Create directory if needed
        let directory = localURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Write file
        try data.write(to: localURL)
    }
    
    // MARK: - Helper Methods
    
    func sanitizeFilename(_ filename: String) -> String {
        // Replace invalid filename characters
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let components = filename.components(separatedBy: invalidCharacters)
        return components.joined(separator: "-")
    }
    
    private func performRequestWithRetry<T>(
        operation: () async throws -> T,
        maxRetries: Int = 3
    ) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                
                if #available(macOS 11.0, *) {
                    Logger.network.warning("Request attempt \(attempt + 1) failed: \(error.localizedDescription)")
                }
                
                // If it's a network timeout, wait before retrying
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain &&
                   (nsError.code == NSURLErrorTimedOut ||
                    nsError.code == NSURLErrorNetworkConnectionLost) &&
                   attempt < maxRetries - 1 {
                    
                    let delay = Double(attempt + 1) * 2.0 // Exponential backoff
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                
                // For other errors, fail immediately
                throw error
            }
        }
        
        throw lastError ?? NSError(
            domain: "SECAPIClient",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Failed after \(maxRetries) attempts"]
        )
    }
    
    // MARK: - Main Download Method
    
    func downloadFilings(tickerOrCIK: String,
                        formTypes: [String],
                        startDate: Date,
                        endDate: Date,
                        outputDirectory: URL,
                        convertToPDF: Bool = false,
                        keepOriginalHTML: Bool = false,
                        mergeHTMLFiles: Bool = false,
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
            let progress = 0.2 + (0.7 * Double(index) / Double(filings.count))
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
                
                // Convert to PDF if requested and not merging
                // (If merging, we'll convert after merging)
                if convertToPDF && !mergeHTMLFiles && (filing.primaryDocument.hasSuffix(".htm") || filing.primaryDocument.hasSuffix(".html")) {
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
                
                successful += 1
            } catch {
                if #available(macOS 11.0, *) {
                    Logger.network.error("Failed to download \(filing.form): \(error.localizedDescription)")
                }
            }
        }
        
        // Merge HTML files if requested
        if mergeHTMLFiles && successful > 0 {
            progressHandler(0.95, "Merging HTML files by type...")
            
            do {
                try await mergeHTMLFilesByType(
                    in: companyDir,
                    ticker: ticker.uppercased(),
                    formTypes: formTypes,
                    filings: filings
                )
                
                // If merging was successful and we're converting to PDF,
                // convert the merged files too
                if convertToPDF {
                    progressHandler(0.98, "Converting merged files to PDF...")
                    
                    for formType in formTypes {
                        let cleanFormType = sanitizeFilename(formType.replacingOccurrences(of: " ", with: "_"))
                        let formDir = companyDir.appendingPathComponent(cleanFormType)
                        
                        // Find merged HTML file
                        if let mergedFile = try? FileManager.default.contentsOfDirectory(at: formDir, includingPropertiesForKeys: nil)
                            .first(where: { $0.lastPathComponent.contains("MERGED") && ($0.pathExtension == "htm" || $0.pathExtension == "html") }) {
                            
                            let pdfURL = mergedFile.deletingPathExtension().appendingPathExtension("pdf")
                            let conversionSuccess = await convertHTMLToPDF(from: mergedFile, to: pdfURL)
                            
                            if conversionSuccess && !keepOriginalHTML {
                                try? FileManager.default.removeItem(at: mergedFile)
                            }
                        }
                    }
                }
            } catch {
                if #available(macOS 11.0, *) {
                    Logger.merge.error("Failed to merge HTML files: \(error.localizedDescription)")
                }
                // Continue without failing the entire operation
            }
        }
        
        progressHandler(1.0, "Download complete!")
        
        return (successful, filings.count)
    }
}
