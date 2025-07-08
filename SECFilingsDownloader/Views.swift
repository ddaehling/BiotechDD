import SwiftUI

// MARK: - Filing Type Selector

struct FilingTypeSelectorView: View {
    @Binding var selectedTypes: [FilingType]
    @Binding var isPresented: Bool
    
    @State private var searchText = ""
    
    var filteredTypes: [FilingType] {
        if searchText.isEmpty {
            return FilingType.commonTypes
        } else {
            return FilingType.commonTypes.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Filing Type")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search filing types", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding()
            
            // List
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredTypes) { type in
                        FilingTypeRow(
                            type: type,
                            isSelected: selectedTypes.contains(where: { $0.name == type.name }),
                            isDisabled: selectedTypes.count >= 4 && !selectedTypes.contains(where: { $0.name == type.name })
                        ) {
                            if selectedTypes.contains(where: { $0.name == type.name }) {
                                selectedTypes.removeAll { $0.name == type.name }
                            } else if selectedTypes.count < 4 {
                                selectedTypes.append(type)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Divider()
            
            // Footer
            HStack {
                Text("\(selectedTypes.count) of 4 selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding()
        }
        .frame(width: 350, height: 400)
    }
}

struct FilingTypeRow: View {
    let type: FilingType
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .imageScale(.large)
                
                Text(type.name)
                    .foregroundColor(isDisabled && !isSelected ? .secondary : .primary)
                
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled && !isSelected)
    }
}

// MARK: - Selected Filing Types View

struct SelectedFilingTypesView: View {
    @Binding var selectedTypes: [FilingType]
    let onRemove: (FilingType) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedTypes) { type in
                    FilingTypeChip(type: type) {
                        onRemove(type)
                    }
                }
            }
        }
    }
}

struct FilingTypeChip: View {
    let type: FilingType
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text(type.name)
                .font(.caption)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Custom Components

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .imageScale(.large)
                Text(title)
                    .font(.headline)
            }
            
            content
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct DownloadProgressView: View {
    let progress: Double
    let message: String
    
    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Date Range Picker

struct DateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("From")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
            
            Image(systemName: "arrow.right")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("To")
                    .font(.caption)
                    .foregroundColor(.secondary)
                DatePicker("", selection: $endDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
            }
        }
    }
}
