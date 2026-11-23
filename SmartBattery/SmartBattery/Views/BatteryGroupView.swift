import SwiftUI

/// Result of a device check for one member, shown under its row in the main list.
enum BatteryGroupCheckStatus {
    case low, missing, charging, received, waiting

    init(sample: BatteryGroupCheck.Sample?, isWaiting: Bool, lowThreshold: Int) {
        guard let sample else {
            self = isWaiting ? .waiting : .missing
            return
        }
        if sample.percent < lowThreshold {
            self = .low
        } else {
            self = sample.isCharging ? .charging : .received
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .low: "점검: 잔량 낮음"
        case .missing: "점검: 새 신호 미수신"
        case .charging: "점검: 충전 중"
        case .received: "점검: 잔량 기준 충족"
        case .waiting: "점검: 수신 대기 중"
        }
    }

    /// Waiting shows a reception wave; the answer replaces it with the result symbol.
    var symbol: String {
        switch self {
        case .low: "exclamationmark.triangle.fill"
        case .missing: "antenna.radiowaves.left.and.right.slash"
        case .charging: "bolt.fill"
        case .received: "checkmark.circle.fill"
        case .waiting: "dot.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .low: .red
        case .missing: .orange
        case .charging, .received: .green
        case .waiting: .secondary
        }
    }
}

/// Device management sheet: replacement history, editing and deletion.
struct BatteryGroupManageView: View {
    @Environment(\.dismiss) private var dismiss

    let groupID: UUID
    let groups: BatteryGroupStore

    @State private var sheet: Sheet?
    @State private var deletion: Deletion?
    @State private var showsDeleteError = false

    private enum Sheet: Hashable, Identifiable {
        case edit, replacement
        var id: Self { self }
    }

    private enum Deletion {
        case group, replacement(BatteryGroup.Replacement)

        var title: LocalizedStringKey {
            switch self {
            case .group: "장비를 삭제할까요?"
            case .replacement: "교체 기록을 삭제할까요?"
            }
        }
    }

    var body: some View {
        NavigationStack {
            if let group = groups.groups.first(where: { $0.id == groupID }) {
                Form {
                    replacementHistory(group)
                    Section {
                        Button("장비 삭제", role: .destructive) { deletion = .group }
                    }
                }
                .navigationTitle(group.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("수정") { sheet = .edit }
                    }
                }
                .sheet(item: $sheet) { sheet in
                    switch sheet {
                    case .edit:
                        BatteryGroupEditor(group: group, groups: groups)
                    case .replacement:
                        BatteryGroupReplacementEditor(group: group, groups: groups)
                    }
                }
                .confirmationDialog(deletion?.title ?? "삭제할까요?", isPresented: Binding(
                    get: { deletion != nil },
                    set: { if !$0 { deletion = nil } }
                ), titleVisibility: .visible, presenting: deletion) { action in
                    Button("삭제", role: .destructive) { delete(action, in: group) }
                    Button("취소", role: .cancel) {}
                } message: { action in
                    if case .group = action {
                        Text("\(group.name) 장비와 교체 기록을 삭제해요. 등록한 건전지는 건전지 목록에 남아요.")
                    }
                }
                .alert("삭제하지 못했어요", isPresented: $showsDeleteError) {
                    Button("확인", role: .cancel) {}
                }
            }
        }
    }

    private func replacementHistory(_ group: BatteryGroup) -> some View {
        let replacements = group.replacements.sorted { $0.date > $1.date }
        return Section("교체 기록") {
            if let days = group.daysSinceReplacement() {
                if days == 0 {
                    Text("오늘 교체했어요")
                } else {
                    Text("지난 교체 후 \(days)일")
                }
            }
            Button("교체 날짜 기록", systemImage: "calendar.badge.plus") { sheet = .replacement }
            ForEach(replacements) { replacement in
                HStack {
                    Text(replacement.date, style: .date)
                    Spacer()
                    Button("삭제", role: .destructive) { deletion = .replacement(replacement) }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("\(replacement.date.formatted(date: .abbreviated, time: .omitted)) 교체 기록 삭제")
                }
            }
        }
    }

    private func delete(_ action: Deletion, in group: BatteryGroup) {
        do {
            switch action {
            case .group:
                try groups.delete(group.id)
                dismiss()
            case .replacement(let replacement):
                var updated = group
                updated.replacements.removeAll { $0.id == replacement.id }
                try groups.update(updated)
            }
        } catch {
            showsDeleteError = true
        }
    }
}

struct BatteryGroupEditor: View {
    @Environment(BatteryStore.self) private var batteries
    @Environment(\.dismiss) private var dismiss
    @State private var group: BatteryGroup
    let groups: BatteryGroupStore
    private let originalMembers: [BatteryGroup.Member]
    @State private var showsSaveError = false

    init(group: BatteryGroup, groups: BatteryGroupStore) {
        _group = State(initialValue: group)
        self.groups = groups
        originalMembers = group.members
    }

    private var name: String { group.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("장비 이름") {
                    TextField("카메라 플래시", text: $group.name)
                }
                Section("건전지 선택") {
                    ForEach(batteries.registered) { battery in
                        memberToggle(.init(id: battery.id, name: battery.name))
                    }
                    ForEach(originalMembers.filter { batteries.battery($0.id) == nil }) { member in
                        memberToggle(member, removed: true)
                    }
                }
            }
            .navigationTitle(groups.groups.contains(where: { $0.id == group.id }) ? "장비 수정" : "장비 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .disabled(name.isEmpty || group.members.isEmpty)
                }
            }
            .alert("장비를 저장하지 못했어요", isPresented: $showsSaveError) {
                Button("확인", role: .cancel) {}
            }
        }
    }

    private func memberToggle(_ member: BatteryGroup.Member, removed: Bool = false) -> some View {
        Toggle(isOn: Binding(
            get: { group.members.contains { $0.id == member.id } },
            set: { selected in
                if selected {
                    group.members.append(member)
                } else {
                    group.members.removeAll { $0.id == member.id }
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                if removed {
                    Text("등록 삭제됨").font(.caption).foregroundStyle(.secondary)
                } else if let other = groups.groups.first(where: { $0.id != group.id && $0.members.contains { $0.id == member.id } }) {
                    Text("지금은 \(other.name)에 있어요. 선택하면 이 장비로 옮겨요. 건전지가 없어진 장비는 삭제돼요.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func save() {
        group.name = name
        group.members = group.members.map { member in
            guard let battery = batteries.battery(member.id) else { return member }
            return .init(id: battery.id, name: battery.name)
        }
        do {
            try groups.update(group)
            dismiss()
        } catch {
            showsSaveError = true
        }
    }
}

private struct BatteryGroupReplacementEditor: View {
    @Environment(\.dismiss) private var dismiss
    let group: BatteryGroup
    let groups: BatteryGroupStore
    @State private var date = Date.now
    @State private var showsSaveError = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("교체 날짜", selection: $date, in: ...Date.now, displayedComponents: .date)
            }
            .navigationTitle("\(group.name) 교체 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                }
            }
            .alert("교체 기록을 저장하지 못했어요", isPresented: $showsSaveError) {
                Button("확인", role: .cancel) {}
            }
        }
    }

    private func save() {
        var updated = group
        updated.replacements.append(.init(date: date))
        do {
            try groups.update(updated)
            dismiss()
        } catch {
            showsSaveError = true
        }
    }
}
