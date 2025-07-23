import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
class IntelligencePackageViewModel: ObservableObject {
    // Input fields
    @Published var ticker = ""
    @Published var alphaVantageAPIKey = ""
    @Published var finraClientID = ""
    @Published var finraClientSecret = ""
    @Published var includeMarketData = true
    @Published var includeShortInterest = true
    @Published var packageLocation: URL?
    
    // UI State
    @Published var isGenerating = false
    @Published var generationProgress: Double = 0
    @Published var statusMessage = ""
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var lastGeneratedPackage: URL?
    
    // Clients
    private let secClient = SECAPIClient.shared
    private var alphaVantageClient: AlphaVantageClient?
    private let finraClient = FINRAClient()
    
    init() {
        // Load saved API key if available
        if let savedKey = UserDefaults.standard.string(forKey: "AlphaVantageAPIKey") {
            self.alphaVantageAPIKey = savedKey
            self.alphaVantageClient = AlphaVantageClient(apiKey: savedKey)
        }
        
        // Load saved FINRA credentials if available
        if let savedClientID = UserDefaults.standard.string(forKey: "FINRAClientID") {
            self.finraClientID = savedClientID
        }
        if let savedSecret = UserDefaults.standard.string(forKey: "FINRAClientSecret") {
            self.finraClientSecret = savedSecret
        }
        
        // Set default package location
        self.packageLocation = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    var canGeneratePackage: Bool {
        !ticker.isEmpty &&
        packageLocation != nil &&
        !isGenerating &&
        (!includeMarketData || !alphaVantageAPIKey.isEmpty) &&
        (!includeShortInterest || (!finraClientID.isEmpty && !finraClientSecret.isEmpty))
    }
    
    func saveAPIKey() {
        UserDefaults.standard.set(alphaVantageAPIKey, forKey: "AlphaVantageAPIKey")
        alphaVantageClient = AlphaVantageClient(apiKey: alphaVantageAPIKey)
    }
    
    func saveFINRACredentials() {
        UserDefaults.standard.set(finraClientID, forKey: "FINRAClientID")
        UserDefaults.standard.set(finraClientSecret, forKey: "FINRAClientSecret")
    }
    
    func selectPackageLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select location for intelligence package"
        
        if panel.runModal() == .OK {
            packageLocation = panel.url
        }
    }
    
    func generatePackage() {
        guard canGeneratePackage else { return }
        
        Task {
            await performPackageGeneration()
        }
    }
    
    private func performPackageGeneration() async {
        isGenerating = true
        generationProgress = 0
        statusMessage = "Starting package generation..."
        lastGeneratedPackage = nil
        
        do {
            // Step 1: Get company info
            updateProgress(0.05, "Looking up company information...")
            let (cik, companyName) = try await getCompanyInfo()
            
            // Step 2: Fetch market data if requested
            var marketData: MarketData? = nil
            if includeMarketData {
                updateProgress(0.15, "Fetching market data...")
                marketData = try await fetchMarketData()
            }
            
            // Step 3: Fetch short interest if requested
            var shortInterestData: ShortInterestData? = nil
            if includeShortInterest {
                updateProgress(0.20, "Fetching short interest data...")
                do {
                    shortInterestData = try await fetchShortInterest()
                    if shortInterestData == nil {
                        print("Warning: No short interest data available for \(ticker)")
                    }
                } catch {
                    print("Warning: Could not fetch short interest data: \(error)")
                    // Continue without short interest data
                }
            }
            
            // Step 4: Fetch SEC filings
            updateProgress(0.25, "Retrieving SEC filings...")
            let filings = try await fetchIntelligenceFilings(cik: cik)
            
            // Step 5: Download filing PDFs
            updateProgress(0.40, "Downloading filing documents...")
            let packageURL = try await downloadFilingPackage(
                ticker: ticker,
                cik: cik,
                companyName: companyName,
                filings: filings,
                marketData: marketData,
                shortInterest: shortInterestData
            )
            
            // Step 6: Create manifest
            updateProgress(0.90, "Creating package manifest...")
            try await createPackageManifest(
                at: packageURL,
                ticker: ticker,
                cik: cik,
                companyName: companyName,
                marketData: marketData,
                shortInterest: shortInterestData,
                filings: filings
            )
            
            updateProgress(1.0, "Package generation complete!")
            lastGeneratedPackage = packageURL
            
            // Open the package folder
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: packageURL.path)
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            statusMessage = "Package generation failed"
        }
        
        isGenerating = false
    }
    
    // MARK: - Helper Methods
    
    private func updateProgress(_ progress: Double, _ message: String) {
        self.generationProgress = progress
        self.statusMessage = message
    }
    
    private func getCompanyInfo() async throws -> (cik: String, name: String) {
        // Try to get CIK from ticker
        let cik: String
        if ticker.allSatisfy({ $0.isNumber }) {
            cik = String(format: "%010d", Int(ticker) ?? 0)
        } else {
            guard let foundCIK = try await secClient.getCIK(for: ticker) else {
                throw NSError(domain: "IntelligencePackage", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Could not find company with ticker \(ticker)"])
            }
            cik = foundCIK
        }
        
        // Get company name from submissions
        let submissions = try await secClient.getSubmissions(for: cik)
        let companyName = submissions.name
        
        return (cik, companyName)
    }
    
    private func fetchMarketData() async throws -> MarketData? {
        guard let client = alphaVantageClient else { return nil }
        do {
            return try await client.fetchMarketData(for: ticker.uppercased())
        } catch {
            print("Failed to fetch market data: \(error)")
            return nil
        }
    }
    
    private func fetchShortInterest() async throws -> ShortInterestData? {
        do {
            // First try the official API with credentials
            if !finraClientID.isEmpty && !finraClientSecret.isEmpty {
                return try await finraClient.fetchShortInterest(
                    for: ticker.uppercased(),
                    clientID: finraClientID,
                    clientSecret: finraClientSecret
                )
            } else {
                // Fall back to legacy file-based approach if no credentials
                return try await finraClient.fetchShortInterestLegacy(for: ticker.uppercased())
            }
        } catch {
            print("Failed to fetch short interest: \(error)")
            // Don't throw - just return nil and continue without short interest data
            return nil
        }
    }
    
    private func fetchIntelligenceFilings(cik: String) async throws -> IntelligenceFilings {
        let submissions = try await secClient.getSubmissions(for: cik)
        
        let allFilings = parseAllFilings(from: submissions)
        
        // Sort and categorize filings
        let now = Date()
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        
        // Latest 10-K
        let latestTenK = allFilings
            .filter { $0.form == "10-K" }
            .sorted { $0.filingDate > $1.filingDate }
            .first
        
        // Recent 10-Qs (last 2)
        let recentTenQs = allFilings
            .filter { $0.form == "10-Q" }
            .sorted { $0.filingDate > $1.filingDate }
            .prefix(2)
            .map { $0 }
        
        // Recent 8-Ks (last 12 months)
        let recentEightKs = allFilings
            .filter { $0.form == "8-K" && isDateAfter($0.filingDate, date: oneYearAgo) }
            .sorted { $0.filingDate > $1.filingDate }
        
        // Registration statements (S-3/S-1, last 2 years)
        let registrationStatements = allFilings
            .filter { ($0.form.hasPrefix("S-3") || $0.form.hasPrefix("S-1")) &&
                     isDateAfter($0.filingDate, date: twoYearsAgo) }
            .sorted { $0.filingDate > $1.filingDate }
        
        // Prospectus supplements (424B variants)
        let prospectusSupplements = allFilings
            .filter { $0.form.hasPrefix("424B") && isDateAfter($0.filingDate, date: twoYearsAgo) }
            .sorted { $0.filingDate > $1.filingDate }
        
        // Insider transactions (Forms 3/4/5, last 12 months)
        let insiderTransactions = allFilings
            .filter { ["3", "4", "5"].contains($0.form) && isDateAfter($0.filingDate, date: oneYearAgo) }
            .sorted { $0.filingDate > $1.filingDate }
        
        // Major shareholder filings (13D/13G)
        let majorShareholderFilings = allFilings
            .filter { $0.form.contains("13D") || $0.form.contains("13G") }
            .sorted { $0.filingDate > $1.filingDate }
        
        // Latest proxy statement
        let latestProxyStatement = allFilings
            .filter { $0.form.contains("14A") && !$0.form.contains("N-") }
            .sorted { $0.filingDate > $1.filingDate }
            .first
        
        // Activist amendments
        let activistAmendments = allFilings
            .filter { $0.form == "SC 13D/A" }
            .sorted { $0.filingDate > $1.filingDate }
        
        return IntelligenceFilings(
            latestTenK: latestTenK,
            recentTenQs: recentTenQs,
            recentEightKs: recentEightKs,
            registrationStatements: registrationStatements,
            prospectusSupplements: prospectusSupplements,
            insiderTransactions: insiderTransactions,
            majorShareholderFilings: majorShareholderFilings,
            latestProxyStatement: latestProxyStatement,
            activistAmendments: activistAmendments
        )
    }
    
    private func parseAllFilings(from submissions: Submissions) -> [Filing] {
        var filings: [Filing] = []
        let recent = submissions.filings.recent
        
        for i in 0..<recent.form.count {
            filings.append(Filing(
                form: recent.form[i],
                filingDate: recent.filingDate[i],
                accessionNumber: recent.accessionNumber[i],
                primaryDocument: recent.primaryDocument[i],
                reportDate: recent.reportDate?[i]
            ))
        }
        
        return filings
    }
    
    private func isDateAfter(_ dateString: String, date: Date) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let filingDate = formatter.date(from: dateString) else { return false }
        return filingDate > date
    }
    
    private func downloadFilingPackage(
        ticker: String,
        cik: String,
        companyName: String,
        filings: IntelligenceFilings,
        marketData: MarketData?,
        shortInterest: ShortInterestData?
    ) async throws -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let timestamp = dateFormatter.string(from: Date())
        
        let packageName = "\(ticker.uppercased())_AI_Package_\(timestamp)"
        let packageURL = packageLocation!.appendingPathComponent(packageName)
        
        // Create directory structure
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        
        let filingsDir = packageURL.appendingPathComponent("filings")
        try FileManager.default.createDirectory(at: filingsDir, withIntermediateDirectories: true)
        
        // Create subdirectories
        let dirs = ["financials", "events", "capital", "ownership", "governance"]
        for dir in dirs {
            try FileManager.default.createDirectory(
                at: filingsDir.appendingPathComponent(dir),
                withIntermediateDirectories: true
            )
        }
        
        var totalFilings = 0
        var downloadedFilings = 0
        
        // Count total filings
        totalFilings = countTotalFilings(filings)
        
        // Download each category
        // Financials
        if let tenK = filings.latestTenK {
            updateProgress(0.45, "Downloading 10-K...")
            if await downloadSingleFiling(tenK, to: filingsDir.appendingPathComponent("financials"), cik: cik, ticker: ticker) {
                downloadedFilings += 1
            }
        }
        
        for (index, tenQ) in filings.recentTenQs.enumerated() {
            updateProgress(0.50 + Double(index) * 0.05, "Downloading 10-Q...")
            if await downloadSingleFiling(tenQ, to: filingsDir.appendingPathComponent("financials"), cik: cik, ticker: ticker) {
                downloadedFilings += 1
            }
        }
        
        // Download each category with progress updates
        var currentProgress = 0.45
        let progressIncrement = 0.40 / Double(totalFilings)
        
        // Download all filing categories
        let downloadTasks: [(String, [Filing], String)] = [
            ("financials", filings.latestTenK.map { [$0] } ?? [] + filings.recentTenQs, "Financial Reports"),
            ("events", Array(filings.recentEightKs.prefix(10)), "Material Events"),
            ("capital", Array(filings.registrationStatements.prefix(5) + filings.prospectusSupplements.prefix(5)), "Capital Structure"),
            ("ownership", Array(filings.insiderTransactions.prefix(20) + filings.majorShareholderFilings.prefix(10)), "Ownership"),
            ("governance", (filings.latestProxyStatement.map { [$0] } ?? []) + Array(filings.activistAmendments.prefix(5)), "Governance")
        ]
        
        for (directory, filingsToDownload, categoryName) in downloadTasks {
            for filing in filingsToDownload {
                updateProgress(currentProgress, "Downloading \(categoryName): \(filing.form)...")
                if await downloadSingleFiling(filing, to: filingsDir.appendingPathComponent(directory), cik: cik, ticker: ticker) {
                    downloadedFilings += 1
                }
                currentProgress += progressIncrement
            }
        }
        
        return packageURL
    }
    
    private func downloadSingleFiling(_ filing: Filing, to directory: URL, cik: String, ticker: String) async -> Bool {
        // Skip downloading if it's a text-only filing
        guard filing.primaryDocument.hasSuffix(".htm") ||
              filing.primaryDocument.hasSuffix(".html") ||
              filing.primaryDocument.hasSuffix(".txt") else {
            return false
        }
        
        let url = secClient.constructFilingURL(
            cik: cik,
            accessionNumber: filing.accessionNumber,
            primaryDocument: filing.primaryDocument
        )
        
        // Create filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.date(from: filing.filingDate) ?? Date()
        
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let formattedDate = dateFormatter.string(from: date)
        
        let filename = "\(ticker.uppercased())_\(filing.form.replacingOccurrences(of: " ", with: ""))_\(formattedDate).htm"
        let localURL = directory.appendingPathComponent(filename)
        
        do {
            try await secClient.downloadFiling(from: url, to: localURL)
            
            // Convert to PDF
            let pdfURL = localURL.deletingPathExtension().appendingPathExtension("pdf")
            _ = await secClient.convertHTMLToPDF(from: localURL, to: pdfURL)
            
            // Delete HTML
            try? FileManager.default.removeItem(at: localURL)
            
            return true
        } catch {
            print("Failed to download filing: \(error)")
            return false
        }
    }
    
    private func countTotalFilings(_ filings: IntelligenceFilings) -> Int {
        var count = 0
        if filings.latestTenK != nil { count += 1 }
        count += filings.recentTenQs.count
        count += min(filings.recentEightKs.count, 10)
        count += min(filings.registrationStatements.count, 5)
        count += min(filings.prospectusSupplements.count, 5)
        count += min(filings.insiderTransactions.count, 20)
        count += min(filings.majorShareholderFilings.count, 10)
        if filings.latestProxyStatement != nil { count += 1 }
        count += min(filings.activistAmendments.count, 5)
        return count
    }
    
    private func createPackageManifest(
        at packageURL: URL,
        ticker: String,
        cik: String,
        companyName: String,
        marketData: MarketData?,
        shortInterest: ShortInterestData?,
        filings: IntelligenceFilings
    ) async throws {
        // Create manifest data
        let manifest = PackageManifest(
            generatedAt: Date(),
            company: CompanyInfo(
                ticker: ticker.uppercased(),
                cik: cik,
                name: companyName,
                sector: nil,
                industry: nil
            ),
            dataSnapshot: DataSnapshot(
                marketData: marketData.map { data in
                    MarketDataExport(
                        symbol: data.symbol,
                        asOf: data.lastUpdated,
                        previousClose: data.previousClose,
                        currentPrice: data.currentPrice,
                        volume20DayAvg: data.volume20DayAvg,
                        movingAverages: MovingAverages(
                            ma20: data.ma20,
                            ma50: data.ma50,
                            ma200: data.ma200
                        ),
                        range52Week: Range52Week(
                            high: data.high52Week,
                            low: data.low52Week,
                            currentVsHigh: ((data.currentPrice ?? data.previousClose) - data.high52Week) / data.high52Week * 100,
                            currentVsLow: ((data.currentPrice ?? data.previousClose) - data.low52Week) / data.low52Week * 100
                        )
                    )
                },
                shortInterest: shortInterest,
                keyMetrics: nil
            ),
            filingsIncluded: createFilingsManifest(filings),
            dataSources: DataSources(
                secFilings: SECDataSource(
                    lastUpdated: Date(),
                    filingCount: countTotalFilings(filings)
                ),
                marketData: marketData != nil ? MarketDataSource(
                    source: "Alpha Vantage",
                    apiKey: nil,
                    lastUpdated: Date()
                ) : nil,
                shortInterest: shortInterest != nil ? ShortInterestSource(
                    source: "FINRA",
                    lastUpdated: Date(),
                    isDelayed: true,
                    delayDays: 14
                ) : nil
            )
        )
        
        // Write manifest
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let manifestData = try encoder.encode(manifest)
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        try manifestData.write(to: manifestURL)
        
        // Write market data separately if available
        if let marketData = marketData {
            let marketDataURL = packageURL.appendingPathComponent("market_data.json")
            let marketDataJSON = try encoder.encode(marketData)
            try marketDataJSON.write(to: marketDataURL)
        }
        
        // Write short interest data separately if available
        if let shortInterest = shortInterest {
            let shortInterestURL = packageURL.appendingPathComponent("short_interest.json")
            let shortInterestJSON = try encoder.encode(shortInterest)
            try shortInterestJSON.write(to: shortInterestURL)
        }
        
        // Create README
        let readme = createReadmeContent(
            ticker: ticker,
            companyName: companyName,
            hasMarketData: marketData != nil,
            hasShortInterest: shortInterest != nil
        )
        let readmeURL = packageURL.appendingPathComponent("README.txt")
        try readme.write(to: readmeURL, atomically: true, encoding: .utf8)
    }
    
    private func createFilingsManifest(_ filings: IntelligenceFilings) -> FilingsManifest {
        var financials: [FilingReference] = []
        var events: [FilingReference] = []
        var capital: [FilingReference] = []
        var ownership: [FilingReference] = []
        var governance: [FilingReference] = []
        
        // Add filings to appropriate categories
        if let tenK = filings.latestTenK {
            financials.append(createFilingReference(tenK))
        }
        
        financials.append(contentsOf: filings.recentTenQs.map(createFilingReference))
        events.append(contentsOf: filings.recentEightKs.prefix(10).map(createFilingReference))
        capital.append(contentsOf: filings.registrationStatements.prefix(5).map(createFilingReference))
        capital.append(contentsOf: filings.prospectusSupplements.prefix(5).map(createFilingReference))
        ownership.append(contentsOf: filings.insiderTransactions.prefix(20).map(createFilingReference))
        ownership.append(contentsOf: filings.majorShareholderFilings.prefix(10).map(createFilingReference))
        
        if let proxy = filings.latestProxyStatement {
            governance.append(createFilingReference(proxy))
        }
        governance.append(contentsOf: filings.activistAmendments.prefix(5).map(createFilingReference))
        
        let totalCount = financials.count + events.count + capital.count + ownership.count + governance.count
        
        return FilingsManifest(
            totalCount: totalCount,
            categories: FilingCategories(
                financials: financials,
                materialEvents: events,
                capitalStructure: capital,
                ownership: ownership,
                governance: governance
            )
        )
    }
    
    private func createFilingReference(_ filing: Filing) -> FilingReference {
        return FilingReference(
            type: filing.form,
            date: filing.filingDate,
            filename: "\(filing.form.replacingOccurrences(of: " ", with: ""))_\(filing.filingDate).pdf",
            description: nil,
            items: nil
        )
    }
    
    private func createReadmeContent(ticker: String, companyName: String, hasMarketData: Bool, hasShortInterest: Bool) -> String {
        return """
        SEC Intelligence Package for \(companyName) (\(ticker.uppercased()))
        Generated: \(Date())
        
        This package contains:
        
        1. SEC Filings:
           - Latest 10-K (Annual Report)
           - Recent 10-Qs (2 most recent Quarterly Reports)
           - Recent 8-Ks (Material Events - last 12 months)
           - Registration Statements (S-3/S-1 - last 2 years)
           - Prospectus Supplements (424B - recent offerings)
           - Insider Transactions (Forms 3/4/5 - last 12 months)
           - Major Shareholder Filings (13D/13G - all current)
           - Proxy Statement (DEF 14A - latest)
           - Activist Amendments (SC 13D/A - if applicable)
        
        2. Market Data:
           \(hasMarketData ? "- Technical indicators and moving averages (see market_data.json)" : "- Not included")
           \(hasMarketData ? "- 20/50/200-day moving averages" : "")
           \(hasMarketData ? "- 52-week high/low" : "")
           \(hasMarketData ? "- Average volume (20-day)" : "")
        
        3. Short Interest Data:
           \(hasShortInterest ? "- FINRA short interest data (see short_interest.json)" : "- Not included")
           \(hasShortInterest ? "- Note: Data is typically delayed by 2 weeks" : "")
        
        4. Data Sources:
           - SEC EDGAR Database
           \(hasMarketData ? "- Alpha Vantage Market Data API" : "")
           \(hasShortInterest ? "- FINRA Consolidated Short Interest API" : "")
        
        Files are organized by category in the 'filings' directory:
        - /financials - 10-K and 10-Q reports
        - /events - 8-K material event filings
        - /capital - S-3/S-1 and 424B filings
        - /ownership - Insider and major shareholder filings
        - /governance - Proxy statements and activist filings
        
        All documents have been converted to PDF format for easy consumption.
        
        For detailed metadata, see manifest.json
        For market data details, see market_data.json
        For short interest details, see short_interest.json
        """
    }
}
