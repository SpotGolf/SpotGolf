import SwiftUI

/// The round's Developer Mode page: the round records raw sensor data on each green, and the
/// page marks strokes while it does. Shown only in a round with Developer Mode on.
struct DeveloperModeView: View {
    @Environment(WatchServices.self) private var services

    /// The mark just made, shown with Undo until it is accepted or `confirmationTime` passes.
    @State private var lastMark: PuttCapture.MarkLabel?
    @State private var confirmationTask: Task<Void, Never>?

    private static let confirmationTime: Duration = .seconds(4)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Developer Mode")
                    .font(.headline)

                switch services.puttCapture.state {
                case .idle:
                    off
                case .waiting:
                    waiting
                case .recording:
                    if let lastMark {
                        confirmation(lastMark)
                    } else {
                        recording
                    }
                }

                ForEach(services.puttCapture.problems + services.sensors.problems.values.sorted(), id: \.self) { problem in
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    /// Stopped on this page.
    private var off: some View {
        Text("Recording is off for this round. It starts again next round while Developer Mode is on.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    /// Between greens.
    private var waiting: some View {
        VStack(spacing: 8) {
            Text("Hole \(services.roundStore.activeRound?.displayHoleNumber ?? 0)")
                .font(.caption)
                .fontWeight(.semibold)
            Text("Waiting for a green")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("Stop", role: .destructive) { services.puttCapture.stop() }
        }
    }

    /// Buttons only: changing text while the watch is on the wrist makes the screen jump.
    private var recording: some View {
        VStack(spacing: 6) {
            Button(PuttCapture.MarkLabel.putt.title) { mark(.putt) }
                .tint(.green)
            Button(PuttCapture.MarkLabel.practice.title) { mark(.practice) }
                .tint(.orange)
            Button(PuttCapture.MarkLabel.ground.title) { mark(.ground) }
                .tint(.brown)
            Button("Stop", role: .destructive) { services.puttCapture.stop() }
            // Changes only when a contact is found
            Text("\(services.puttCapture.contactCount) contacts")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func confirmation(_ label: PuttCapture.MarkLabel) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
            Text("\(label.title) recorded")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("Undo") {
                services.puttCapture.undoLastMark()
                dismissConfirmation()
            }
            .tint(.red)
            Button("OK") { dismissConfirmation() }
        }
    }

    private func mark(_ label: PuttCapture.MarkLabel) {
        services.puttCapture.mark(label)
        lastMark = label
        confirmationTask?.cancel()
        confirmationTask = Task {
            try? await Task.sleep(for: Self.confirmationTime)
            guard !Task.isCancelled else { return }
            lastMark = nil
        }
    }

    private func dismissConfirmation() {
        confirmationTask?.cancel()
        confirmationTask = nil
        lastMark = nil
    }
}
