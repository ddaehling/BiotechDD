import Foundation

class FINRAClient {
    private let session: URLSession
    private let tokenEndpoint = "https://ews.fip.finra.org/fip/rest/ews/oauth2/access_token"
    private let apiBaseURL = "https://api.finra.org"
    
    private var accessToken: String?
    private var tokenExpirationDate: Date?
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "SECFilingsDownloader/1.0",
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        ]
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Authentication
    
    private func getAccessToken(clientID: String, clientSecret: String) async throws -> String {
        // Check if we have a valid cached token
        if let token = accessToken,
           let expiration = tokenExpirationDate,
           expiration > Date() {
            return token
        }
        
        print("Attempting to get FINRA access token...")
        
        // Create Basic Auth token
        let credentials = "\(clientID):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw FINRAError.invalidCredentials
        }
        let base64Credentials = credentialsData.base64EncodedString()
        print("Auth header will be: Basic \(String(base64Credentials.prefix(10)))...")  // Show partial for debugging
        
        // Create request
        let urlString = "\(tokenEndpoint)?grant_type=client_credentials"
        guard let url = URL(string: urlString) else {
            throw FINRAError.invalidURL
        }
        
        print("Token endpoint: \(urlString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Add grant_type in the body as form data
        let bodyString = "grant_type=client_credentials"
        request.httpBody = bodyString.data(using: .utf8)
        
        // Make request
        let (data, response) = try await session.data(for: request)
        
        // Log response for debugging
        if let httpResponse = response as? HTTPURLResponse {
            print("FINRA Auth Response Status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("FINRA Auth Response Body: \(responseString)")
            }
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FINRAError.authenticationFailed
        }
        
        // Check for various error status codes
        if httpResponse.statusCode == 401 {
            throw FINRAError.invalidCredentials
        } else if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                throw FINRAError.apiError("Authentication failed with status \(httpResponse.statusCode): \(errorString)")
            } else {
                throw FINRAError.apiError("Authentication failed with status \(httpResponse.statusCode)")
            }
        }
        
        // Parse response - handle both possible response formats
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            // Try to parse as dictionary first
            if let dict = json as? [String: Any] {
                // Check for error message
                if let error = dict["error"] as? String {
                    throw FINRAError.apiError("Authentication error: \(error)")
                }
                
                // Look for access token with different possible keys
                if let token = dict["access_token"] as? String,
                   let expiresIn = (dict["expires_in"] as? Int) ?? (dict["expires_in"] as? String).flatMap({ Int($0) }) {
                    // Cache token
                    self.accessToken = token
                    self.tokenExpirationDate = Date().addingTimeInterval(TimeInterval(expiresIn - 60))
                    print("Successfully obtained FINRA access token")
                    
                    // Print debug info for testing
                    print("To test your credentials with curl:")
                    print("curl -X POST '\(urlString)' \\")
                    print("  -H 'Authorization: Basic \(base64Credentials)' \\")
                    print("  -H 'Content-Type: application/x-www-form-urlencoded' \\")
                    print("  -d 'grant_type=client_credentials'")
                    
                    return token
                }
            }
            
            // If we get here, we couldn't parse the expected format
            if let responseString = String(data: data, encoding: .utf8) {
                print("Unexpected token response format: \(responseString)")
            }
            throw FINRAError.invalidResponse
            
        } catch {
            print("Failed to parse token response: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Raw response: \(responseString)")
            }
            throw FINRAError.invalidResponse
        }
    }
    
    // MARK: - Fetch Consolidated Short Interest Data
    
    func fetchShortInterest(for symbol: String, clientID: String, clientSecret: String) async throws -> ShortInterestData? {
        print("Fetching short interest for \(symbol) using FINRA API")
        print("Using Client ID: \(String(clientID.prefix(4)))...")  // Only show first 4 chars for security
        
        // Get access token
        let token = try await getAccessToken(clientID: clientID, clientSecret: clientSecret)
        
        // Try different endpoint variations
        let endpoints = [
            "\(apiBaseURL)/data/group/otcmarket/name/consolidatedShortInterest",
            "\(apiBaseURL)/data/group/otcMarket/name/consolidatedShortInterest",  // Different casing
            "\(apiBaseURL)/data/group/otcmarket/name/consolidatedShortInterestMock",
            "\(apiBaseURL)/data/consolidatedShortInterest"  // Simplified path
        ]
        
        for endpoint in endpoints {
            print("Trying endpoint: \(endpoint)")
            do {
                if let data = try await fetchShortInterestFromEndpoint(
                    endpoint: endpoint,
                    symbol: symbol,
                    token: token
                ) {
                    return data
                }
            } catch {
                print("Failed to fetch from \(endpoint): \(error)")
                continue
            }
        }
        
        print("No short interest data found for \(symbol) from any endpoint")
        return nil
    }
    
    private func fetchShortInterestFromEndpoint(
        endpoint: String,
        symbol: String,
        token: String
    ) async throws -> ShortInterestData? {
        // Construct URL with query parameters
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "limit", value: "1") // Get most recent record
        ]
        
        guard let url = components?.url else {
            throw FINRAError.invalidURL
        }
        
        print("Fetching short interest from: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw FINRAError.invalidResponse
        }
        
        print("Short interest API response status: \(httpResponse.statusCode)")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("Short interest API response: \(responseString)")
        }
        
        if httpResponse.statusCode == 404 {
            // No data found for this symbol
            print("No short interest data found for symbol \(symbol)")
            return nil
        }
        
        guard httpResponse.statusCode == 200 else {
            if let errorString = String(data: data, encoding: .utf8) {
                throw FINRAError.apiError("HTTP \(httpResponse.statusCode): \(errorString)")
            } else {
                throw FINRAError.apiError("HTTP \(httpResponse.statusCode)")
            }
        }
        
        // Parse the response
        return try parseConsolidatedShortInterest(from: data, symbol: symbol)
    }
    
    private func parseConsolidatedShortInterest(from data: Data, symbol: String) throws -> ShortInterestData? {
        // First try to parse as raw JSON
        do {
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            print("Parsed JSON structure: \(type(of: json))")
            
            // Check if it's an error response
            if let dict = json as? [String: Any] {
                if let error = dict["error"] as? String {
                    print("API returned error: \(error)")
                    throw FINRAError.apiError(error)
                }
                if let message = dict["message"] as? String {
                    print("API returned message: \(message)")
                    throw FINRAError.apiError(message)
                }
            }
            
            // Try different possible response structures
            let records: [[String: Any]]
            if let dataArray = (json as? [String: Any])?["data"] as? [[String: Any]] {
                records = dataArray
            } else if let recordsArray = (json as? [String: Any])?["records"] as? [[String: Any]] {
                records = recordsArray
            } else if let array = json as? [[String: Any]] {
                records = array
            } else if let singleRecord = json as? [String: Any], singleRecord["symbol"] != nil {
                records = [singleRecord]
            } else {
                print("Unexpected JSON structure, cannot find records")
                return nil
            }
            
            print("Found \(records.count) records")
            
            // Find the record for our symbol
            guard let record = records.first(where: {
                ($0["symbol"] as? String)?.uppercased() == symbol.uppercased()
            }) else {
                print("No record found for symbol \(symbol)")
                return nil
            }
            
            // Parse the record
            return parseShortInterestRecord(record)
            
        } catch {
            print("JSON parsing error: \(error)")
            throw FINRAError.invalidData
        }
    }
    
    private func parseShortInterestRecord(_ record: [String: Any]) -> ShortInterestData? {
        guard let symbol = record["symbol"] as? String else { return nil }
        
        // Parse dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let recordDate: Date
        if let dateString = record["recordDate"] as? String,
           let date = dateFormatter.date(from: dateString) {
            recordDate = date
        } else {
            recordDate = Date()
        }
        
        let settlementDate: Date
        if let dateString = record["settlementDate"] as? String,
           let date = dateFormatter.date(from: dateString) {
            settlementDate = date
        } else {
            // Default to T+2 from record date
            settlementDate = Calendar.current.date(byAdding: .day, value: 2, to: recordDate) ?? recordDate
        }
        
        // Parse numeric values with flexible type handling
        let shortInterest = parseNumericValue(record["shortInterest"] ?? record["shortShareQuantity"]) ?? 0
        let shortInterestRatio = parseDoubleValue(record["shortInterestRatio"]) ?? 0
        let percentOfFloat = parseDoubleValue(record["percentOfFloat"]) ?? 0
        let daysToCover = parseDoubleValue(record["daysToCover"]) ?? 0
        let previousShortInterest = parseNumericValue(record["previousShortInterest"]) ?? 0
        let changePercent = parseDoubleValue(record["changePercent"]) ?? 0
        
        return ShortInterestData(
            symbol: symbol,
            shortInterest: shortInterest,
            shortInterestRatio: shortInterestRatio,
            percentOfFloat: percentOfFloat,
            daysTocover: daysToCover,
            previousShortInterest: previousShortInterest,
            changePercent: changePercent,
            recordDate: recordDate,
            settlementDate: settlementDate
        )
    }
    
    private func parseNumericValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        } else if let doubleValue = value as? Double {
            return Int(doubleValue)
        } else if let stringValue = value as? String {
            return Int(stringValue.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }
    
    private func parseDoubleValue(_ value: Any?) -> Double? {
        if let doubleValue = value as? Double {
            return doubleValue
        } else if let intValue = value as? Int {
            return Double(intValue)
        } else if let stringValue = value as? String {
            return Double(stringValue.replacingOccurrences(of: ",", with: ""))
        }
        return nil
    }
    
    // MARK: - Alternative: Try legacy file-based approach as fallback
    
    func fetchShortInterestLegacy(for symbol: String) async throws -> ShortInterestData? {
        print("Trying legacy FINRA file approach for \(symbol)")
        
        // Get the most recent file dates (typically 15th and last day of month)
        let recentDates = getRecentFINRADates()
        
        for dateString in recentDates {
            do {
                let data = try await fetchFINRAFile(date: dateString)
                if let shortData = parseShortInterestLegacy(from: data, symbol: symbol, date: dateString) {
                    print("Found short interest data for \(symbol) on \(dateString)")
                    return shortData
                }
            } catch {
                // Continue to next date
                continue
            }
        }
        
        return nil
    }
    
    private func getRecentFINRADates() -> [String] {
        var dates: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        
        let calendar = Calendar.current
        let today = Date()
        
        // FINRA publishes data twice monthly, typically around the 15th and end of month
        // Data is delayed by about 2 weeks
        for monthOffset in 0..<3 {
            guard let monthDate = calendar.date(byAdding: .month, value: -monthOffset, to: today) else { continue }
            
            // Mid-month (15th)
            var components = calendar.dateComponents([.year, .month], from: monthDate)
            components.day = 15
            if let midMonth = calendar.date(from: components),
               midMonth < today {
                dates.append(formatter.string(from: midMonth))
            }
            
            // End of month
            components.day = 1
            if let firstOfMonth = calendar.date(from: components),
               let firstOfNextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth),
               let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: firstOfNextMonth),
               lastOfMonth < today {
                dates.append(formatter.string(from: lastOfMonth))
            }
        }
        
        dates.sort(by: >)
        return dates
    }
    
    private func fetchFINRAFile(date: String) async throws -> String {
        let urlString = "https://regsho.finra.org/CNMSshvol\(date).txt"
        
        guard let url = URL(string: urlString) else {
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
    
    private func parseShortInterestLegacy(from content: String, symbol: String, date: String) -> ShortInterestData? {
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let fields = line.components(separatedBy: "|")
            
            if fields.count >= 4 && fields[1] == symbol {
                guard let shortVolume = Int(fields[2]),
                      let totalVolume = Int(fields[3]) else { continue }
                
                let shortPercent = Double(shortVolume) / Double(totalVolume) * 100
                
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd"
                let recordDate = formatter.date(from: date) ?? Date()
                
                let settlementDate = Calendar.current.date(byAdding: .day, value: 2, to: recordDate) ?? recordDate
                
                return ShortInterestData(
                    symbol: symbol,
                    shortInterest: shortVolume,
                    shortInterestRatio: shortPercent / 100,
                    percentOfFloat: 0,
                    daysTocover: 0,
                    previousShortInterest: 0,
                    changePercent: 0,
                    recordDate: recordDate,
                    settlementDate: settlementDate
                )
            }
        }
        
        return nil
    }
    // MARK: - Test Method for Debugging
    
    func testConnection(clientID: String, clientSecret: String) async {
        print("=== FINRA API Connection Test ===")
        print("Testing with Client ID: \(String(clientID.prefix(4)))...")
        
        do {
            // Test 1: Try to get access token
            print("\n1. Testing OAuth authentication...")
            let token = try await getAccessToken(clientID: clientID, clientSecret: clientSecret)
            print("✓ Successfully obtained access token")
            print("Token (first 20 chars): \(String(token.prefix(20)))...")
            
            // Test 2: Try to access the API
            print("\n2. Testing API access...")
            let testURL = URL(string: "\(apiBaseURL)/data/group/otcmarket/name/consolidatedShortInterestMock")!
            var request = URLRequest(url: testURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("API Response Status: \(httpResponse.statusCode)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("API Response (first 200 chars): \(String(responseString.prefix(200)))...")
                }
                
                if httpResponse.statusCode == 200 {
                    print("✓ API access successful")
                } else {
                    print("✗ API returned status \(httpResponse.statusCode)")
                }
            }
            
        } catch {
            print("✗ Test failed: \(error)")
        }
        
        print("\n=== End of Connection Test ===")
    }
    
    // MARK: - Error Types
    
    enum FINRAError: LocalizedError {
        case invalidURL
        case invalidCredentials
        case authenticationFailed
        case fileNotFound
        case invalidData
        case symbolNotFound
        case apiError(String)
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid FINRA API URL"
            case .invalidCredentials:
                return "Invalid FINRA API credentials"
            case .authenticationFailed:
                return "Failed to authenticate with FINRA API"
            case .fileNotFound:
                return "FINRA data file not found"
            case .invalidData:
                return "Unable to parse FINRA data"
            case .symbolNotFound:
                return "Symbol not found in FINRA data"
            case .apiError(let message):
                return "FINRA API Error: \(message)"
            case .invalidResponse:
                return "Invalid response from FINRA API"
            }
        }
    }
}
