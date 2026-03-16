import SwiftUI

/// Sheet for selecting and loading sample documents
struct SamplePickerSheet: View {
    @Bindable var viewModel: DocumentListViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SampleDocument.SampleCategory.allCases, id: \.self) { category in
                    Section {
                        ForEach(SampleDocument.samples.filter { $0.category == category }) { sample in
                            Button {
                                Task {
                                    await viewModel.createNewDocument(content: sample.content)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: category.icon)
                                        .font(.title2)
                                        .foregroundStyle(Color.stridAccent)
                                        .frame(width: 40)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sample.title)
                                            .font(.headline)
                                            .foregroundStyle(Color.stridText)

                                        Text(sample.description)
                                            .font(.caption)
                                            .foregroundStyle(Color.stridTextSecondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(Color.stridGray)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    } header: {
                        Text(category.rawValue)
                    }
                }
            }
            .navigationTitle("Sample Documents")
            .platformNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .platformTopBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .foregroundStyle(Color.stridBlack)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
