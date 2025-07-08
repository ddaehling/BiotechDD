import Foundation
import SwiftUI
import Combine

@MainActor
class DownloaderViewModel: ObservableObject {
    // Input fields
    @Published var ticker = ""
    @Published var selectedFilingTypes: [FilingType] = []
    @Published var startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @Published var endDate = Date()
    @Published var downloadFolder: URL?
    @Published var convertToPDF = true
    @Published var keepOriginalHTML = false
    
    // UI State
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var statusMessage = ""
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var showingFilingTypeSelector = false
    
    // Download results
    @Published var lastDownloadResult: (successful: Int, total: Int)?
    
    private let apiClient = SECAPIClient.shared
    
    init() {
        // Set default download folder to Downloads
        self.downloadFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }
    
    var canStartDownload: Bool {
        !ticker.isEmpty &&
        !selectedFilingTypes.isEmpty &&
        downloadFolder != nil &&
        !isDownloading
    }
    
    func addFilingType(_ type: FilingType) {
        if selectedFilingTypes.count < 4 && !selectedFilingTypes.contains(where: { $0.name == type.name }) {
            selectedFilingTypes.append(type)
        }
    }
    
    func removeFilingType(_ type: FilingType) {
        selectedFilingTypes.removeAll { $0.id == type.id }
    }
    
    func selectDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select folder for SEC filings"
        
        if panel.runModal() == .OK {
            downloadFolder = panel.url
        }
    }
    
    func startDownload() {
        guard canStartDownload else { return }
        
        Task {
            await performDownload()
        }
    }
    
    private func performDownload() async {
        isDownloading = true
        downloadProgress = 0
        statusMessage = "Starting download..."
        lastDownloadResult = nil
        
        do {
            let formTypes = selectedFilingTypes.map { $0.name }
            
            let result = try await apiClient.downloadFilings(
                tickerOrCIK: ticker.trimmingCharacters(in: .whitespacesAndNewlines),
                formTypes: formTypes,
                startDate: startDate,
                endDate: endDate,
                outputDirectory: downloadFolder!,
                convertToPDF: convertToPDF,
                keepOriginalHTML: keepOriginalHTML,
                progressHandler: { progress, message in
                    Task { @MainActor in
                        self.downloadProgress = progress
                        self.statusMessage = message
                    }
                }
            )
            
            lastDownloadResult = result
            
            if result.total == 0 {
                statusMessage = "No filings found matching your criteria"
            } else {
                statusMessage = "Successfully downloaded \(result.successful) of \(result.total) filings"
            }
            
            // Open the download folder in Finder
            if result.successful > 0 {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadFolder!.path)
            }
            
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
            statusMessage = "Download failed"
        }
        
        isDownloading = false
    }
    
    func reset() {
        ticker = ""
        selectedFilingTypes = []
        downloadProgress = 0
        statusMessage = ""
        lastDownloadResult = nil
        convertToPDF = true
        keepOriginalHTML = false
    }
}
