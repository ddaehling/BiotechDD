import Foundation

// MARK: - Data Models

struct MarketData: Codable {
    let symbol: String
    let previousClose: Double
    let currentPrice: Double?
    let volume20DayAvg: Int
    let ma20: Double
    let ma50: Double
    let ma200: Double
    let high52Week: Double
    let low52Week: Double
    let shortInterestRatio: Double?
    let lastUpdated: Date
    
    enum CodingKeys: String, CodingKey {
        case symbol
        case previousClose
        case currentPrice
        case volume20DayAvg
        case ma20
        case ma50
        case ma200
        case high52Week
        case low52Week
        case shortInterestRatio
        case lastUpdated
    }
}

struct AlphaVantageQuote: Codable {
    let globalQuote: GlobalQuote
    
    enum CodingKeys: String, CodingKey {
        case globalQuote = "Global Quote"
    }
}

struct GlobalQuote: Codable {
    let symbol: String
    let open: String
    let high: String
    let low: String
    let price: String
    let volume: String
    let latestTradingDay: String
    let previousClose: String
    let change: String
    let changePercent: String
    
    enum CodingKeys: String, CodingKey {
        case symbol = "01. symbol"
        case open = "02. open"
        case high = "03. high"
        case low = "04. low"
        case price = "05. price"
        case volume = "06. volume"
        case latestTradingDay = "07. latest trading day"
        case previousClose = "08. previous close"
        case change = "09. change"
        case changePercent = "10. change percent"
    }
}

struct AlphaVantageSMA: Codable {
    let metaData: SMAMetaData
    let technicalAnalysis: [String: SMAValue]
    
    enum CodingKeys: String, CodingKey {
        case metaData = "Meta Data"
        case technicalAnalysis = "Technical Analysis: SMA"
    }
}

struct SMAMetaData: Codable {
    let symbol: String
    let indicator: String
    let lastRefreshed: String
    let interval: String
    let timePeriod: Int
    let seriesType: String
    let timeZone: String
    
    enum CodingKeys: String, CodingKey {
        case symbol = "1: Symbol"
        case indicator = "2: Indicator"
        case lastRefreshed = "3: Last Refreshed"
        case interval = "4: Interval"
        case timePeriod = "5: Time Period"
        case seriesType = "6: Series Type"
        case timeZone = "7: Time Zone"
    }
}

struct SMAValue: Codable {
    let sma: String
    
    enum CodingKeys: String, CodingKey {
        case sma = "SMA"
    }
}

// MARK: - Alpha Vantage Client

class AlphaVantageClient: ObservableObject {
    private let baseURL = "https://www.alphavantage.co/query"
    private var apiKey: String
    private let session: URLSession
    private let rateLimiter = RateLimiter(requestsPerMinute: 5)
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }
    
    func updateAPIKey(_ key: String) {
        self.apiKey = key
    }
    
    // MARK: - Fetch Market Data
    
    func fetchMarketData(for symbol: String) async throws -> MarketData {
        // Fetch quote data
        let quote = try await fetchQuote(for: symbol)
        
        // Fetch moving averages
        let ma20 = try await fetchSMA(for: symbol, period: 20)
        let ma50 = try await fetchSMA(for: symbol, period: 50)
        let ma200 = try await fetchSMA(for: symbol, period: 200)
        
        // Fetch additional data
        let dailyData = try await fetchDailyData(for: symbol)
        
        return MarketData(
            symbol: symbol,
            previousClose: Double(quote.globalQuote.previousClose) ?? 0,
            currentPrice: Double(quote.globalQuote.price),
            volume20DayAvg: calculateAverageVolume(from: dailyData),
            ma20: ma20,
            ma50: ma50,
            ma200: ma200,
            high52Week: calculate52WeekHigh(from: dailyData),
            low52Week: calculate52WeekLow(from: dailyData),
            shortInterestRatio: nil, // Will be fetched separately
            lastUpdated: Date()
        )
    }
    
    // MARK: - Individual API Calls
    
    private func fetchQuote(for symbol: String) async throws -> AlphaVantageQuote {
        await rateLimiter.waitIfNeeded()
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "function", value: "GLOBAL_QUOTE"),
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        let (data, _) = try await session.data(from: components.url!)
        
        // Check for API error
        if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorMessage = errorResponse["Error Message"] as? String {
            throw AlphaVantageError.apiError(errorMessage)
        }
        
        return try JSONDecoder().decode(AlphaVantageQuote.self, from: data)
    }
    
    private func fetchSMA(for symbol: String, period: Int) async throws -> Double {
        await rateLimiter.waitIfNeeded()
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "function", value: "SMA"),
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "interval", value: "daily"),
            URLQueryItem(name: "time_period", value: String(period)),
            URLQueryItem(name: "series_type", value: "close"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        let (data, _) = try await session.data(from: components.url!)
        let smaData = try JSONDecoder().decode(AlphaVantageSMA.self, from: data)
        
        // Get the most recent SMA value
        if let firstDate = smaData.technicalAnalysis.keys.sorted().last,
           let smaValue = smaData.technicalAnalysis[firstDate],
           let value = Double(smaValue.sma) {
            return value
        }
        
        throw AlphaVantageError.dataNotFound
    }
    
    private func fetchDailyData(for symbol: String) async throws -> [String: [String: String]] {
        await rateLimiter.waitIfNeeded()
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "function", value: "TIME_SERIES_DAILY"),
            URLQueryItem(name: "symbol", value: symbol),
            URLQueryItem(name: "outputsize", value: "full"),
            URLQueryItem(name: "apikey", value: apiKey)
        ]
        
        let (data, _) = try await session.data(from: components.url!)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timeSeries = json["Time Series (Daily)"] as? [String: [String: String]] else {
            throw AlphaVantageError.invalidResponse
        }
        
        return timeSeries
    }
    
    // MARK: - Calculations
    
    private func calculateAverageVolume(from dailyData: [String: [String: String]]) -> Int {
        let sortedDates = dailyData.keys.sorted().suffix(20)
        var totalVolume: Int64 = 0
        var count = 0
        
        for date in sortedDates {
            if let volumeStr = dailyData[date]?["5. volume"],
               let volume = Int64(volumeStr) {
                totalVolume += volume
                count += 1
            }
        }
        
        return count > 0 ? Int(totalVolume / Int64(count)) : 0
    }
    
    private func calculate52WeekHigh(from dailyData: [String: [String: String]]) -> Double {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        var highest: Double = 0
        
        for (dateStr, values) in dailyData {
            if let date = ISO8601DateFormatter().date(from: dateStr + "T00:00:00Z"),
               date > oneYearAgo,
               let highStr = values["2. high"],
               let high = Double(highStr) {
                highest = max(highest, high)
            }
        }
        
        return highest
    }
    
    private func calculate52WeekLow(from dailyData: [String: [String: String]]) -> Double {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date())!
        var lowest: Double = Double.infinity
        
        for (dateStr, values) in dailyData {
            if let date = ISO8601DateFormatter().date(from: dateStr + "T00:00:00Z"),
               date > oneYearAgo,
               let lowStr = values["3. low"],
               let low = Double(lowStr) {
                lowest = min(lowest, low)
            }
        }
        
        return lowest == Double.infinity ? 0 : lowest
    }
}

// MARK: - Rate Limiter

class RateLimiter {
    private let requestsPerMinute: Int
    private var requestTimes: [Date] = []
    private let queue = DispatchQueue(label: "com.secdownloader.ratelimiter")
    
    init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
    }
    
    func waitIfNeeded() async {
        await withCheckedContinuation { continuation in
            queue.async {
                let now = Date()
                let oneMinuteAgo = now.addingTimeInterval(-60)
                
                // Remove old requests
                self.requestTimes.removeAll { $0 < oneMinuteAgo }
                
                if self.requestTimes.count >= self.requestsPerMinute {
                    // Need to wait
                    let oldestRequest = self.requestTimes[0]
                    let waitTime = oldestRequest.addingTimeInterval(60).timeIntervalSince(now)
                    
                    if waitTime > 0 {
                        Thread.sleep(forTimeInterval: waitTime)
                    }
                }
                
                self.requestTimes.append(Date())
                continuation.resume()
            }
        }
    }
}

// MARK: - Errors

enum AlphaVantageError: LocalizedError {
    case apiError(String)
    case invalidResponse
    case dataNotFound
    case rateLimitExceeded
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Alpha Vantage API Error: \(message)"
        case .invalidResponse:
            return "Invalid response from Alpha Vantage"
        case .dataNotFound:
            return "Required data not found in response"
        case .rateLimitExceeded:
            return "API rate limit exceeded. Please wait before retrying."
        }
    }
}
