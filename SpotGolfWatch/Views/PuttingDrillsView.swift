import SwiftUI

/// Putt Data Sharing's drills, on the page after the no-round page. One screen at a time:
/// the start, a paused screen before each drill, and one task. Done shows "Saved…" over the
/// whole page for `savedTime`, so the player knows the tap counted. Nothing plays a haptic,
/// since haptics have caused false contacts. See `plans/2026-10-27-putt-data-sharing.md`,
/// section 2.2.
struct PuttingDrillsView: View {
    @Environment(WatchServices.self) private var services

    /// The dots after "Saved" while it shows, 1 to 3; 0 when it is not showing.
    @State private var savedDots = 0
    @State private var savedTask: Task<Void, Never>?

    /// How long "Saved…" shows after Done.
    static let savedTime: Duration = .seconds(2)

    var body: some View {
        let drills = services.drills
        ScrollView {
            VStack(spacing: 8) {
                switch drills.state {
                case .idle:
                    start
                case .starting:
                    ProgressView()
                    Text("Starting workout…")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    Button("Cancel") { drills.cancelStart() }
                case .recording:
                    switch drills.session.step {
                    case .paused:
                        paused
                    case .task(let drill, let task):
                        taskScreen(drill: drill, task: task)
                    case .finished:
                        EmptyView()
                    }
                case .packing:
                    ProgressView()
                    Text("Sending to your iPhone…")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
                ForEach(drills.problems, id: \.self) { problem in
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)
        }
        .overlay {
            if savedDots > 0 {
                saved
            }
        }
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private var start: some View {
        let drills = services.drills
        Text("Putting Drills")
            .font(.headline)
        if !drills.hasConsent {
            Text("Open Putt Data Sharing on your iPhone to start.")
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        } else {
            if drills.lastSent != nil {
                Text("Sent to your iPhone")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
            Text("You need a putter, 5 balls and a practice green.")
                .font(.footnote)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Button("Start") {
                Task { await drills.start() }
            }
            .tint(.green)
            .disabled(services.roundStore.activeRound != nil || drills.isOutboxFull)
            .accessibilityIdentifier("StartDrills")
        }
    }

    @ViewBuilder
    private var paused: some View {
        let session = services.drills.session
        if session.collectsBalls {
            Text("Collect your balls.")
                .font(.headline)
        }
        if let drill = session.currentDrill, let number = session.drillNumber {
            Text("Drill \(number) of \(session.drills.count)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("Next: \(drill.name)")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(drill.setup)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        Button("Ready") { services.drills.ready() }
            .tint(.green)
            .accessibilityIdentifier("DrillReady")
    }

    @ViewBuilder
    private func taskScreen(drill: Int, task: Int) -> some View {
        let session = services.drills.session
        Text("Drill \(drill + 1) · \(task + 1) of \(Drill.tasks)")
            .font(.headline)
        Text(session.drills[drill].task)
            .font(.body)
            .multilineTextAlignment(.center)
            .frame(minHeight: 60)
        Button("Done") {
            services.drills.done()
            showSaved()
        }
        .tint(.green)
        .accessibilityIdentifier("DrillDone")
    }

    /// Covers the page, so the next task shows only once it is gone.
    private var saved: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
            HStack(spacing: 0) {
                Text("Saved")
                // The dots that are not showing yet keep their space, so "Saved" never moves
                Text(verbatim: String(repeating: ".", count: savedDots))
                Text(verbatim: String(repeating: ".", count: 3 - savedDots))
                    .hidden()
            }
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("DrillSaved")
    }

    /// "Saved." then "Saved.." then "Saved...", over `savedTime`.
    private func showSaved() {
        savedTask?.cancel()
        savedDots = 1
        savedTask = Task {
            let step = Self.savedTime / 3
            for dots in 2...3 {
                try? await Task.sleep(for: step)
                guard !Task.isCancelled else { return }
                savedDots = dots
            }
            try? await Task.sleep(for: step)
            guard !Task.isCancelled else { return }
            savedDots = 0
        }
    }
}

/// The page after the drills while a session records: Skip drill and Stop.
struct DrillControlsView: View {
    @Environment(WatchServices.self) private var services

    var body: some View {
        VStack(spacing: 10) {
            Button("Skip Drill") { services.drills.skipDrill() }
                .accessibilityIdentifier("SkipDrill")
            Button("Stop", role: .destructive) { services.drills.stop() }
                .accessibilityIdentifier("StopDrills")
        }
        .padding()
    }
}
