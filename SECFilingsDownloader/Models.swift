import Foundation

// MARK: - Data Models

struct CompanyTicker: Codable {
    let cik_str: Int
    let ticker: String
    let title: String
}

struct Submissions: Codable {
    let cik: String
    let name: String
    let tickers: [String]
    let filings: Filings
}

struct Filings: Codable {
    let recent: RecentFilings
}

struct RecentFilings: Codable {
    let form: [String]
    let filingDate: [String]
    let accessionNumber: [String]
    let primaryDocument: [String]
    let reportDate: [String]?
}

struct Filing: Identifiable, Codable {
    let id = UUID()
    let form: String
    let filingDate: String
    let accessionNumber: String
    let primaryDocument: String
    let reportDate: String?
    
    var downloadURL: String {
        // This will be constructed when downloading
        return ""
    }
    
    enum CodingKeys: String, CodingKey {
        case form
        case filingDate
        case accessionNumber
        case primaryDocument
        case reportDate
    }
}

// MARK: - App Models

struct FilingType: Identifiable, Equatable {
    let id = UUID()
    let name: String
    
    static let commonTypes = [
        FilingType(name: "10-K"),
        FilingType(name: "10-Q"),
        FilingType(name: "8-K"),
        FilingType(name: "DEF 14A"),
        FilingType(name: "20-F"),
        FilingType(name: "S-1"),
        FilingType(name: "S-3"),
        FilingType(name: "424B"),
        FilingType(name: "424B2"),
        FilingType(name: "424B3"),
        FilingType(name: "424B4"),
        FilingType(name: "424B5"),
        FilingType(name: "SC 13G"),
        FilingType(name: "SC 13G/A"),
        FilingType(name: "SC 13D"),
        FilingType(name: "SC 13D/A"),
        FilingType(name: "3"),
        FilingType(name: "4"),
        FilingType(name: "5"),
        FilingType(name: "425"),
        FilingType(name: "S-4"),
        FilingType(name: "DEFM14A")
    ]
}

enum DownloadStatus {
    case idle
    case downloading(progress: Double)
    case completed(successful: Int, total: Int)
    case error(String)
}
