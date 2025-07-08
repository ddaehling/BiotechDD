import Foundation

class FINRAClient {
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Fetch Short Interest Data
    
    func fetchShortInterest(for symbol: String) async throws -> ShortInterestData? {
        // FINRA publishes data twice monthly
        // Files are available at: http://regsho.finra.org/
        // Format: CNMSshvol[YYYYMMDD].txt
        
        print("Fetching short interest for \(symbol)")
        
        // Get the most recent file dates (typically 15th and last day of month)
        let recentDates = getRecentFINRADates()
        print("Checking FINRA dates: \(recentDates)")
        
        for dateString in recentDates {
            do {
                let data = try await fetchFINRAFile(date: dateString)
                if let shortData = parseShortInterest(from: data, symbol: symbol, date: dateString) {
                    print("Found short interest data for \(symbol) on \(dateString)")
                    return shortData
                }
            } catch {
                print("Failed to fetch FINRA file for \(dateString): \(error)")
                // Continue to next date
            }
        }
        
        print("No short interest data found for \(symbol)")
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func getRecentFINRADates() -> [String] {
        var dates: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        
        let calendar = Calendar.current
        let today = Date()
        
        // FINRA publishes data twice monthly, typically around the 15th and end of month
        // Data is delayed by about 2 weeks, so we look at past dates
        for monthOffset in 0..<3 {  // Check last 3 months
            guard let monthDate = calendar.date(byAdding: .month, value: -monthOffset, to: today) else { continue }
            
            // Mid-month (15th)
            var components = calendar.dateComponents([.year, .month], from: monthDate)
            components.day = 15
            if let midMonth = calendar.date(from: components),
               midMonth < today {  // Only past dates
                dates.append(formatter.string(from: midMonth))
            }
            
            // End of month
            components.day = 1
            if let firstOfMonth = calendar.date(from: components),
               let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth),
               let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth),
               lastOfMonth < today {  // Only past dates
                dates.append(formatter.string(from: lastOfMonth))
            }
        }
        
        // Sort dates in descending order (most recent first)
        dates.sort(by: >)
        
        return dates
    }
    
    private func fetchFINRAFile(date: String) async throws -> String {
        // Try HTTPS first, fall back to HTTP if needed
        let httpsURLString = "https://regsho.finra.org/CNMSshvol\(date).txt"
        let httpURLString = "http://regsho.finra.org/CNMSshvol\(date).txt"
        
        // Try HTTPS first
        if let url = URL(string: httpsURLString) {
            do {
                let (data, response) = try await session.data(from: url)
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200,
                   let content = String(data: data, encoding: .utf8) {
                    return content
                }
            } catch {
                print("HTTPS request failed, trying HTTP: \(error.localizedDescription)")
            }
        }
        
        // Fall back to HTTP
        guard let url = URL(string: httpURLString) else {
            throw FINRAError.invalidURL
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw FINRAError.fileNotFound
        }
        
        guard let content = String(data: data, encoding: .utf8) else {
            throw FINRAError.invalidData
        }
        
        return content
    }
    
    private func parseShortInterest(from content: String, symbol: String, date: String) -> ShortInterestData? {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let fields = line.components(separatedBy: "|")
            
            // FINRA format: Date|Symbol|ShortVolume|TotalVolume|Market
            if fields.count >= 4 && fields[1] == symbol {
                guard let shortVolume = Int(fields[2]),
                      let totalVolume = Int(fields[3]) else { continue }
                
                let shortPercent = Double(shortVolume) / Double(totalVolume) * 100
                
                // Create date from string
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd"
                let recordDate = formatter.date(from: date) ?? Date()
                
                // Settlement date is typically T+2
                let settlementDate = Calendar.current.date(byAdding: .day, value: 2, to: recordDate) ?? recordDate
                
                return ShortInterestData(
                    symbol: symbol,
                    shortInterest: shortVolume,
                    shortInterestRatio: shortPercent / 100,
                    percentOfFloat: 0, // Would need additional data
                    daysTocover: 0, // Would need average volume
                    previousShortInterest: 0, // Would need historical data
                    changePercent: 0,
                    recordDate: recordDate,
                    settlementDate: settlementDate
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Alternative: SEC Fails-to-Deliver Data
    
    func fetchFailsToDeliver(for symbol: String) async throws -> FailsToDeliverData? {
        // SEC publishes FTD data monthly
        // Available at: https://www.sec.gov/data/foiadocsfailsdatahtm
        
        let currentDate = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMM"
        
        // Try current and previous month
        for monthOffset in 0..<2 {
            guard let monthDate = Calendar.current.date(byAdding: .month, value: -monthOffset, to: currentDate) else { continue }
            let monthString = formatter.string(from: monthDate)
            
            if let data = try? await fetchSECFailsData(yearMonth: monthString) {
                if let ftdData = parseFailsToDeliver(from: data, symbol: symbol) {
                    return ftdData
                }
            }
        }
        
        return nil
    }
    
    private func fetchSECFailsData(yearMonth: String) async throws -> String {
        // SEC FTD files are in a specific format
        // This is a simplified implementation
        let urlString = "https://www.sec.gov/files/data/fails-deliver-data/cnsfails\(yearMonth).zip"
        
        // Would need to download, unzip, and parse
        // For now, returning empty string as placeholder
        return ""
    }
    
    private func parseFailsToDeliver(from content: String, symbol: String) -> FailsToDeliverData? {
        // Parse SEC FTD format
        // Format: Settlement Date|CUSIP|Symbol|Quantity|Description|Price
        
        // Simplified implementation
        return nil
    }
}

// MARK: - Error Types

enum FINRAError: LocalizedError {
    case invalidURL
    case fileNotFound
    case invalidData
    case symbolNotFound
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid FINRA data URL"
        case .fileNotFound:
            return "FINRA data file not found for this date"
        case .invalidData:
            return "Unable to parse FINRA data"
        case .symbolNotFound:
            return "Symbol not found in FINRA data"
        }
    }
}

// MARK: - Data Models

struct FailsToDeliverData: Codable {
    let symbol: String
    let settlementDate: Date
    let failedShares: Int
    let price: Double?
}
