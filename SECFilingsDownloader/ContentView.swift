import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: Filings Downloader
            FilingsDownloaderView()
                .tabItem {
                    Label("Download Filings", systemImage: "arrow.down.doc")
                }
                .tag(0)
            
            // Tab 2: Intelligence Package
            IntelligencePackageView()
                .tabItem {
                    Label("AI Package", systemImage: "brain")
                }
                .tag(1)
        }
        .frame(minWidth: 700, idealWidth: 800, minHeight: 750, idealHeight: 850)
    }
}

struct FilingsDownloaderView: View {
    @StateObject private var viewModel = DownloaderViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HeaderView()
            
            // Main Content
            ScrollView {
                VStack(spacing: 20) {
                    // Ticker Input
                    SectionCard(title: "Company", icon: "building.2") {
                        HStack {
                            TextField("Enter ticker symbol or CIK", text: $viewModel.ticker)
                                .textFieldStyle(.roundedBorder)
                                .disabled(viewModel.isDownloading)
                            
                            if !viewModel.ticker.isEmpty {
                                Button(action: { viewModel.ticker = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isDownloading)
                            }
                        }
                    }
                    
                    // Filing Types
                    SectionCard(title: "Filing Types", icon: "doc.text") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                if viewModel.selectedFilingTypes.isEmpty {
                                    Text("No filing types selected")
                                        .foregroundColor(.secondary)
                                } else {
                                    SelectedFilingTypesView(
                                        selectedTypes: $viewModel.selectedFilingTypes,
                                        onRemove: viewModel.removeFilingType
                                    )
                                }
                                
                                Spacer()
                                
                                Button(action: { viewModel.showingFilingTypeSelector = true }) {
                                    Image(systemName: "plus.circle.fill")
                                        .imageScale(.large)
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.selectedFilingTypes.count >= 4 || viewModel.isDownloading)
                            }
                        }
                    }
                    
                    // Date Range
                    SectionCard(title: "Date Range", icon: "calendar") {
                        DateRangePicker(
                            startDate: $viewModel.startDate,
                            endDate: $viewModel.endDate
                        )
                        .disabled(viewModel.isDownloading)
                    }
                    
                    // Download Location
                    SectionCard(title: "Download Location", icon: "folder") {
                        HStack {
                            if let folder = viewModel.downloadFolder {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentColor)
                                Text(folder.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                            } else {
                                Text("No folder selected")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            Button("Choose...") {
                                viewModel.selectDownloadFolder()
                            }
                            .disabled(viewModel.isDownloading)
                        }
                    }
                    
                    // PDF Conversion Options
                    SectionCard(title: "PDF Conversion", icon: "doc.richtext") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $viewModel.convertToPDF) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Convert HTML to PDF")
                                        .font(.system(.body))
                                    Text("Automatically convert downloaded HTML filings to PDF format")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(viewModel.isDownloading)
                            
                            if viewModel.convertToPDF {
                                Toggle(isOn: $viewModel.keepOriginalHTML) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Keep original HTML files")
                                            .font(.system(.body))
                                        Text("Preserve the original HTML files alongside PDFs")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .disabled(viewModel.isDownloading)
                                .padding(.leading, 20)
                            }
                        }
                    }
                    
                    // Download Progress
                    if viewModel.isDownloading {
                        SectionCard(title: "Download Progress", icon: "arrow.down.circle") {
                            DownloadProgressView(
                                progress: viewModel.downloadProgress,
                                message: viewModel.statusMessage
                            )
                        }
                    } else if let result = viewModel.lastDownloadResult {
                        SectionCard(title: "Last Download", icon: "checkmark.circle") {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Successfully downloaded \(result.successful) of \(result.total) filings")
                                    .font(.system(.body, design: .default))
                                
                                if result.successful > 0 {
                                    Button("Open Download Folder") {
                                        if let folder = viewModel.downloadFolder {
                                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                                        }
                                    }
                                    .buttonStyle(.link)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer with Download Button
            FooterView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingFilingTypeSelector) {
            FilingTypeSelectorView(
                selectedTypes: $viewModel.selectedFilingTypes,
                isPresented: $viewModel.showingFilingTypeSelector
            )
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.showingError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("SEC Filings Downloader")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Download SEC EDGAR filings for any public company")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct FooterView: View {
    @ObservedObject var viewModel: DownloaderViewModel
    
    var body: some View {
        HStack {
            if !viewModel.statusMessage.isEmpty && !viewModel.isDownloading {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Reset") {
                viewModel.reset()
            }
            .disabled(viewModel.isDownloading)
            
            Button("Download Filings") {
                viewModel.startDownload()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canStartDownload)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
