import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.presentationMode) private var presentationMode
    var onSelect: (HistoryEntry) -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.locale = Locale(identifier: "zh_TW")
        return f
    }()

    var body: some View {
        NavigationView {
            Group {
                if history.entries.isEmpty {
                    Text("還沒有紀錄")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(history.entries) { entry in
                            Button {
                                onSelect(entry)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.modeLabel)
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Spacer()
                                        Text(Self.dateFormatter.string(from: entry.date))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(entry.text)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("歷史紀錄(最近 \(HistoryStore.limit) 筆)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !history.entries.isEmpty {
                        Button("清空") {
                            history.clear()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView(onSelect: { _ in })
            .environmentObject(HistoryStore())
    }
}
