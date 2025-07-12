import Foundation

// Import MarketData type from AlphaVantageClient
// Note: MarketData should be defined in AlphaVantageClient.swift

// MARK: - Intelligence Package Models

struct IntelligencePackage {
    let companyInfo: CompanyInfo
    let marketData: MarketData?
    let shortInterestData: ShortInterestData?
    let filings: IntelligenceFilings
    let generatedAt: Date
    let dataSource: DataSources
}

struct CompanyInfo: Codable {
    let ticker: String
    let cik: String
    let name: String
    let sector: String?
    let industry: String?
}

struct IntelligenceFilings {
    // Core financials
    let latestTenK: Filing?
    let recentTenQs: [Filing]
    
    // Material events
    let recentEightKs: [Filing]
    
    // Capital structure
    let registrationStatements: [Filing] // S-3/S-1
    let prospectusSupplements: [Filing] // 424B
    
    // Ownership
    let insiderTransactions: [Filing] // Forms 3/4/5
    let majorShareholderFilings: [Filing] // 13D/13G
    
    // Governance
    let latestProxyStatement: Filing? // DEF 14A
    let activistAmendments: [Filing] // SC 13D/A
}

struct ShortInterestData: Codable {
    let symbol: String
    let shortInterest: Int
    let shortInterestRatio: Double
    let percentOfFloat: Double
    let daysToCover: Double
    let previousShortInterest: Int
    let changePercent: Double
    let recordDate: Date
    let settlementDate: Date

    enum CodingKeys: String, CodingKey {
        case symbol
        case shortInterest
        case shortInterestRatio
        case percentOfFloat
        case daysToCover = "daysTocover"
        case previousShortInterest
        case changePercent
        case recordDate
        case settlementDate
    }
}

struct DataSources: Codable {
    let secFilings: SECDataSource
    let marketData: MarketDataSource?
    let shortInterest: ShortInterestSource?
}

struct SECDataSource: Codable {
    let source: String
    let lastUpdated: Date
    let filingCount: Int
    
    init(lastUpdated: Date, filingCount: Int) {
        self.source = "SEC EDGAR"
        self.lastUpdated = lastUpdated
        self.filingCount = filingCount
    }
}

struct MarketDataSource: Codable {
    let source: String
    let apiKey: String?
    let lastUpdated: Date
}

struct ShortInterestSource: Codable {
    let source: String
    let lastUpdated: Date
    let isDelayed: Bool
    let delayDays: Int?
}

// MARK: - Extended Filing Types

extension FilingType {
    static let extendedTypes = [
        // Core financials
        FilingType(name: "10-K"),
        FilingType(name: "10-Q"),
        
        // Material events
        FilingType(name: "8-K"),
        
        // Capital structure
        FilingType(name: "S-3"),
        FilingType(name: "S-1"),
        FilingType(name: "424B"),
        FilingType(name: "424B2"),
        FilingType(name: "424B3"),
        FilingType(name: "424B4"),
        FilingType(name: "424B5"),
        
        // Ownership
        FilingType(name: "3"),
        FilingType(name: "4"),
        FilingType(name: "5"),
        FilingType(name: "SC 13D"),
        FilingType(name: "SC 13G"),
        FilingType(name: "SC 13D/A"),
        FilingType(name: "SC 13G/A"),
        
        // Governance
        FilingType(name: "DEF 14A"),
        FilingType(name: "PRE 14A"),
        FilingType(name: "DEFA14A"),
        
        // Other important
        FilingType(name: "425"), // M&A related
        FilingType(name: "S-4"), // M&A registration
        FilingType(name: "DEFM14A") // M&A proxy
    ]
}

// MARK: - Package Export Models

struct PackageManifest: Codable {
    let version: String
    let generatedAt: Date
    let company: CompanyInfo
    let dataSnapshot: DataSnapshot
    let filingsIncluded: FilingsManifest
    let dataSources: DataSources
    
    init(generatedAt: Date, company: CompanyInfo, dataSnapshot: DataSnapshot,
         filingsIncluded: FilingsManifest, dataSources: DataSources) {
        self.version = "1.0"
        self.generatedAt = generatedAt
        self.company = company
        self.dataSnapshot = dataSnapshot
        self.filingsIncluded = filingsIncluded
        self.dataSources = dataSources
    }
}

struct DataSnapshot: Codable {
    let marketData: MarketDataExport?
    let shortInterest: ShortInterestData?
    let keyMetrics: KeyMetrics?
}

struct MarketDataExport: Codable {
    let symbol: String
    let asOf: Date
    let previousClose: Double
    let currentPrice: Double?
    let volume20DayAvg: Int
    let movingAverages: MovingAverages
    let range52Week: Range52Week
}

struct MovingAverages: Codable {
    let ma20: Double
    let ma50: Double
    let ma200: Double
}

struct Range52Week: Codable {
    let high: Double
    let low: Double
    let currentVsHigh: Double // percentage from high
    let currentVsLow: Double // percentage from low
}

struct KeyMetrics: Codable {
    let marketCap: Double?
    let enterpriseValue: Double?
    let peRatio: Double?
    let pegRatio: Double?
    let priceToBook: Double?
    let debtToEquity: Double?
}

struct FilingsManifest: Codable {
    let totalCount: Int
    let categories: FilingCategories
}

struct FilingCategories: Codable {
    let financials: [FilingReference]
    let materialEvents: [FilingReference]
    let capitalStructure: [FilingReference]
    let ownership: [FilingReference]
    let governance: [FilingReference]
}

struct FilingReference: Codable {
    let type: String
    let date: String
    let filename: String
    let description: String?
    let items: [String]? // For 8-Ks
}

// MARK: - 8-K Item Definitions

struct EightKItem {
    let number: String
    let description: String
    
    static let importantItems = [
        EightKItem(number: "1.01", description: "Entry into a Material Definitive Agreement"),
        EightKItem(number: "1.02", description: "Termination of a Material Definitive Agreement"),
        EightKItem(number: "2.01", description: "Completion of Acquisition or Disposition of Assets"),
        EightKItem(number: "2.02", description: "Results of Operations and Financial Condition"),
        EightKItem(number: "2.03", description: "Creation of a Direct Financial Obligation"),
        EightKItem(number: "3.01", description: "Notice of Delisting or Failure to Satisfy a Listing Rule"),
        EightKItem(number: "4.01", description: "Changes in Registrant's Certifying Accountant"),
        EightKItem(number: "5.01", description: "Changes in Control of Registrant"),
        EightKItem(number: "5.02", description: "Departure of Directors or Certain Officers"),
        EightKItem(number: "5.03", description: "Amendments to Articles or Bylaws"),
        EightKItem(number: "7.01", description: "Regulation FD Disclosure"),
        EightKItem(number: "8.01", description: "Other Events")
    ]
}
