import SwiftUI

struct QueueView: View {
    @State private var vm: QueueViewModel

    init(vm: QueueViewModel) {
        self._vm = State(initialValue: vm)
    }

    var body: some View {
        List {
            ForEach(Array(vm.items.enumerated()), id: \.element.id) { index, item in
                queueRow(item: item, index: index)
                    .listRowBackground(index == vm.currentIndex ? Color.accentColor.opacity(0.1) : Color.clear)
            }
            .onDelete { vm.remove(at: $0.first!) }
        }
        .navigationTitle("Queue")
        .onAppear { vm.startObserving() }
        .onDisappear { vm.stopObserving() }
    }

    @ViewBuilder
    private func queueRow(item: PlayableItem, index: Int) -> some View {
        switch item {
        case .track(let track):
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.body)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if index == vm.currentIndex {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.caption)
                }
            }
        case .djSegment(let segment):
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DJ — \(segment.kind.rawValue.capitalized)")
                        .font(.body.italic())
                    Text(segment.script)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    vm.skipSegment(at: index)
                } label: {
                    Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
