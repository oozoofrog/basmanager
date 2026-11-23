import SwiftUI

struct RegisterSheet: View {
    let id: UUID

    @Environment(BatteryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 현관 도어락", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } header: {
                    Text("이름")
                }

                if let sighting = store.sightings[id] {
                    Section("현재 상태") {
                        BatteryRow(
                            name: trimmed.isEmpty ? String(localized: "새 건전지") : trimmed,
                            reading: sighting.reading,
                            size: sighting.reading.reportedSize,
                            isOnline: store.isOnline(sighting.lastSeen),
                            lastSeen: sighting.lastSeen,
                            connection: nil
                        )
                    }
                }
            }
            .navigationTitle("건전지 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록", action: save).disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard store.register(id, name: trimmed) else { return }
        dismiss()
    }
}
