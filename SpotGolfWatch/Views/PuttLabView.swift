import SwiftUI

/// Records raw sensor data for putting detection work. Outside a round a capture is started by
/// hand; in a round the round starts it, and the page records on each green.
struct PuttLabView: View {
    @Environment(WatchServices.self) private var services

    /// The mark just made, shown with Undo until it is accepted or `confirmationTime` passes.
    @State private var lastMark: PuttCapture.MarkLabel?
    @State private var confirmationTask: Task<Void, Never>?
    @State private var showsCaptures = false

    private static let confirmationTime: Duration = .seconds(4)

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Putt Lab")
                    .font(.headline)

                switch services.puttCapture.state {
                case .idle:
                    if services.roundStore.activeRound != nil {
                        offForRound
                    } else {
                        idle
                    }
                case .waiting:
                    waiting
                case .starting:
                    ProgressView()
                    Text("Starting workout…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(verbatim: services.workoutManager.stateText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Cancel") { services.puttCapture.stop() }
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

    @ViewBuilder
    private var idle: some View {
        @Bindable var recorder = services.puttCapture
        VStack(spacing: 8) {
            Text("Records wrist motion and sound while you putt. Tap a button after each stroke.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start Capture") {
                Task { await services.puttCapture.start() }
            }
            .tint(.green)
            Toggle("Microphone", isOn: $recorder.microphone)
                .font(.caption2)
            Toggle("Save data", isOn: $recorder.savesData)
                .font(.caption2)
            if !services.puttCapture.savesData {
                Text("Battery test: the sensors run and nothing is saved. Leave the watch alone for 20 minutes or more, then stop.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if services.puttCapture.micPermission == .denied {
                Text("Microphone off: allow it in Settings")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Button("Captures") { showsCaptures = true }
                .sheet(isPresented: $showsCaptures) {
                    NavigationStack { CapturesView() }
                }
        }
    }

    /// In a round with Putt Lab off, or stopped on this page.
    private var offForRound: some View {
        Text("Putt Lab is off for this round. Turn on Putt Lab During Rounds in Settings on your iPhone before the next round.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    /// In a round, between greens.
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
            // Changes only when a contact is found, with a haptic
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
