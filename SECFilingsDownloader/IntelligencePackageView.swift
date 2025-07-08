import SwiftUI
import AppKit

struct IntelligencePackageView: View {
    @StateObject private var viewModel = IntelligencePackageViewModel()
    @State private var showingAPIKeyInfo = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            IntelligenceHeaderView()
            
            // Main Content
            ScrollView {
                VStack(spacing: 20) {
                    // Company Input
                    SectionCard(title: "Target Company", icon: "building.2.crop.circle") {
                        HStack {
                            TextField("Enter ticker symbol", text: $viewModel.ticker)
                                .textFieldStyle(.roundedBorder)
                                .textCase(.uppercase)
                                .disabled(viewModel.isGenerating)
                            
                            if !viewModel.ticker.isEmpty {
                                Button(action: { viewModel.ticker = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isGenerating)
                            }
                        }
                    }
                    
                    // Data Sources Configuration
                    SectionCard(title: "Data Sources", icon: "chart.line.uptrend.xyaxis") {
                        VStack(spacing: 16) {
                            // Market Data Toggle
                            Toggle(isOn: $viewModel.includeMarketData) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Include Market Data")
                                            .font(.system(.body, weight: .medium))
                                        
                                        Button(action: { showingAPIKeyInfo = true }) {
                                            Image(systemName: "info.circle")
                                                .foregroundColor(.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    
                                    Text("Technical indicators, moving averages, and volume data")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(viewModel.isGenerating)
                            
                            if viewModel.includeMarketData {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Alpha Vantage API Key")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        SecureField("Enter API key", text: $viewModel.alphaVantageAPIKey)
                                            .textFieldStyle(.roundedBorder)
                                            .disabled(viewModel.isGenerating)
                                        
                                        Button("Save") {
                                            viewModel.saveAPIKey()
                                        }
                                        .disabled(viewModel.alphaVantageAPIKey.isEmpty || viewModel.isGenerating)
                                    }
                                    
                                    if viewModel.alphaVantageAPIKey.isEmpty {
                                        Text("Get a free API key at alphavantage.co")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                            .onTapGesture {
                                                NSWorkspace.shared.open(URL(string: "https://www.alphavantage.co/support/#api-key")!)
                                            }
                                    }
                                }
                                .padding(.leading, 20)
                            }
                            
                            Divider()
                            
                            // Short Interest Toggle
                            Toggle(isOn: $viewModel.includeShortInterest) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Include Short Interest Data")
                                        .font(.system(.body, weight: .medium))
                                    
                                    Text("FINRA bi-monthly reports (may not be available for all symbols)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Text("Data is typically delayed by 2-4 weeks")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(viewModel.isGenerating)
                        }
                    }
                    
                    // Included Filings
                    SectionCard(title: "SEC Filings to Include", icon: "doc.text.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            FilingCategoryRow(
                                title: "Financial Reports",
                                items: ["Latest 10-K", "2 Recent 10-Qs"],
                                icon: "chart.bar.doc.horizontal"
                            )
                            
                            FilingCategoryRow(
                                title: "Material Events",
                                items: ["Recent 8-Ks (last 12 months)"],
                                icon: "exclamationmark.triangle"
                            )
                            
                            FilingCategoryRow(
                                title: "Capital Structure",
                                items: ["S-3/S-1 Registration", "424B Prospectus"],
                                icon: "dollarsign.circle"
                            )
                            
                            FilingCategoryRow(
                                title: "Ownership",
                                items: ["Forms 3/4/5", "13D/13G Filings"],
                                icon: "person.2.circle"
                            )
                            
                            FilingCategoryRow(
                                title: "Governance",
                                items: ["DEF 14A Proxy", "SC 13D/A Amendments"],
                                icon: "building.columns"
                            )
                        }
                    }
                    
                    // Package Location
                    SectionCard(title: "Package Location", icon: "folder") {
                        HStack {
                            if let folder = viewModel.packageLocation {
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
                                viewModel.selectPackageLocation()
                            }
                            .disabled(viewModel.isGenerating)
                        }
                    }
                    
                    // Generation Progress
                    if viewModel.isGenerating {
                        SectionCard(title: "Generation Progress", icon: "gearshape.2") {
                            VStack(spacing: 8) {
                                ProgressView(value: viewModel.generationProgress)
                                    .progressViewStyle(.linear)
                                
                                Text(viewModel.statusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if let packageURL = viewModel.lastGeneratedPackage {
                        SectionCard(title: "Last Generated Package", icon: "checkmark.circle.fill") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Package created successfully")
                                    .font(.system(.body))
                                
                                Button("Open Package Folder") {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: packageURL.path)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer with Generate Button
            IntelligenceFooterView(viewModel: viewModel)
        }
        .frame(minWidth: 600, minHeight: 700)
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.showingError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
        .sheet(isPresented: $showingAPIKeyInfo) {
            APIKeyInfoView()
        }
    }
}

struct IntelligenceHeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading) {
                    Text("AI Intelligence Package")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Generate comprehensive data packages for AI analysis")
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

struct IntelligenceFooterView: View {
    @ObservedObject var viewModel: IntelligencePackageViewModel
    
    var body: some View {
        HStack {
            if !viewModel.statusMessage.isEmpty && !viewModel.isGenerating {
                Text(viewModel.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Generate Package") {
                viewModel.generatePackage()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canGeneratePackage)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct FilingCategoryRow: View {
    let title: String
    let items: [String]
    let icon: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, weight: .medium))
                
                ForEach(items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
}

struct APIKeyInfoView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "key.fill")
                    .font(.largeTitle)
                    .foregroundColor(.accentColor)
                
                Text("Alpha Vantage API Key")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("To include market data in your intelligence packages, you need a free Alpha Vantage API key.")
                
                Text("What's included:")
                    .font(.headline)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Real-time and historical stock prices", systemImage: "chart.line.uptrend.xyaxis")
                    Label("20, 50, and 200-day moving averages", systemImage: "waveform.path.ecg")
                    Label("Trading volume and averages", systemImage: "chart.bar")
                    Label("52-week high/low data", systemImage: "arrow.up.arrow.down")
                }
                .font(.callout)
                
                Text("Free tier includes:")
                    .font(.headline)
                    .padding(.top)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• 5 API requests per minute")
                    Text("• 500 requests per day")
                    Text("• No credit card required")
                }
                .font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Get Free API Key") {
                    NSWorkspace.shared.open(URL(string: "https://www.alphavantage.co/support/#api-key")!)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 500)
    }
}
