import SwiftUI

/// Putt Data Sharing: what it is, consent, the equipment profile, and the sessions shared.
/// The drills themselves run on the watch only, so the phone stays in a pocket. See
/// `plans/2026-10-27-putt-data-sharing.md`, section 1.
struct PuttDataSharingView: View {
    @Environment(PhoneServices.self) private var services
    @Environment(\.dismiss) private var dismiss

    @State private var confirmsDeleteAll = false

    var body: some View {
        @Bindable var sharing = services.puttSharing
        NavigationStack {
            Form {
                Section("About") {
                    Text("Help make putt detection work for every golfer. Your watch records wrist motion and sound while you do a set of putting drills, and one location when you start, to check you were on a putting green. The recordings are shared with the SpotGolf developers to improve putt detection and are not linked to your name or Apple Account.")
                }
                Section("What You Need") {
                    Text("You need a putter, 5 balls and an outdoor practice green. Each drill is 5 repeats of the same task, such as \"Hit a 3 foot putt\". After you complete the 5 tasks, the drill ends. Between drills you collect your balls and set up for the next drill.")
                }
                Section("How It Works") {
                    Text("Start on your watch, on the Putting Drills page. Read the instructions for each task on your watch, do the task, then tap Done.")
                }
                Section {
                    if sharing.hasConsent {
                        Label("You agreed to share", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityIdentifier("PuttSharingAgreed")
                    } else {
                        Button("I Agree") { sharing.agree() }
                            .accessibilityIdentifier("PuttSharingAgree")
                    }
                } header: {
                    Text("Consent")
                } footer: {
                    Text("The watch's microphone records during the drills, so speech nearby may be recorded. You can delete what you shared at any time.")
                }
                Group {
                    equipment(sharing)
                    Section {
                        Toggle("Upload on Cellular", isOn: $sharing.uploadsOnCellular)
                            .accessibilityIdentifier("PuttSharingCellular")
                    } footer: {
                        Text("A session is about 45 MB. Without this, sessions upload on Wi-Fi.")
                    }
                    sessions(sharing)
                }
                .disabled(!sharing.hasConsent)
            }
            .navigationTitle("Putt Data Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Delete All My Data", isPresented: $confirmsDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) { sharing.deleteAll() }
            } message: {
                Text("Deletes every session on this iPhone and in iCloud, and asks the developers to delete the ones they have.")
            }
        }
    }

    private func equipment(_ sharing: PuttSharingStore) -> some View {
        @Bindable var sharing = sharing
        return Section("My Setup") {
            Picker("Hand", selection: $sharing.equipment.hand) {
                Text("Right").tag(PuttSharing.Equipment.Hand.right)
                Text("Left").tag(PuttSharing.Equipment.Hand.left)
            }
            Picker("Putter Head", selection: $sharing.equipment.putterHead) {
                Text("Blade").tag(PuttSharing.Equipment.PutterHead.blade)
                Text("Mallet").tag(PuttSharing.Equipment.PutterHead.mallet)
            }
            Picker("Putter Face", selection: $sharing.equipment.putterFace) {
                Text("Insert").tag(PuttSharing.Equipment.PutterFace.insert)
                Text("Milled or Metal").tag(PuttSharing.Equipment.PutterFace.milled)
            }
            Picker("Putter Length", selection: $sharing.equipment.putterLength) {
                Text("Standard").tag(PuttSharing.Equipment.PutterLength.standard)
                Text("Arm-Lock").tag(PuttSharing.Equipment.PutterLength.armLock)
                Text("Long or Broomstick").tag(PuttSharing.Equipment.PutterLength.long)
            }
            Picker("Grip", selection: $sharing.equipment.grip) {
                Text("Standard").tag(PuttSharing.Equipment.Grip.standard)
                Text("Cross-Handed").tag(PuttSharing.Equipment.Grip.crossHanded)
                Text("Claw").tag(PuttSharing.Equipment.Grip.claw)
                Text("Other").tag(PuttSharing.Equipment.Grip.other)
            }
            Picker("Ball", selection: $sharing.equipment.ball) {
                Text("Soft (Urethane)").tag(PuttSharing.Equipment.Ball.soft)
                Text("Firm (Two-Piece)").tag(PuttSharing.Equipment.Ball.firm)
                Text("Don't Know").tag(PuttSharing.Equipment.Ball.unknown)
            }
            Picker("Handicap", selection: $sharing.equipment.handicap) {
                Text("Under 10").tag(PuttSharing.Equipment.Handicap.under10)
                Text("10 to 20").tag(PuttSharing.Equipment.Handicap.from10To20)
                Text("Over 20").tag(PuttSharing.Equipment.Handicap.over20)
                Text("No Handicap").tag(PuttSharing.Equipment.Handicap.none)
            }
        }
    }

    private func sessions(_ sharing: PuttSharingStore) -> some View {
        Section {
            if sharing.sessions.isEmpty {
                Text("No sessions yet")
                    .foregroundStyle(.secondary)
            }
            ForEach(sharing.sessions) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    Text("\(session.drillsFinished) drills · \(session.size, format: .byteCount(style: .file)) · \(session.hasLocation ? String(localized: "Location: yes") : String(localized: "Location: no"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(Self.stateText(session.state))
                        .font(.caption)
                        .foregroundStyle(session.state == .failed ? .red : .secondary)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { sharing.delete(session.id) }
                }
            }
            if !sharing.sessions.isEmpty || sharing.sharerID != nil {
                Button("Delete All My Data", role: .destructive) { confirmsDeleteAll = true }
                    .accessibilityIdentifier("PuttSharingDeleteAll")
            }
        } header: {
            Text("Sessions")
        } footer: {
            if sharing.noAccount {
                Text("Sign in to iCloud in the Settings app to upload sessions.")
            }
        }
    }

    private static func stateText(_ state: PuttSharingStore.Session.State) -> String {
        switch state {
        case .onWatch: String(localized: "On your watch")
        case .onPhone: String(localized: "On this iPhone")
        case .uploading: String(localized: "Uploading…")
        case .uploaded: String(localized: "Uploaded")
        case .waitingToUpload: String(localized: "Waiting to upload")
        case .failed: String(localized: "Upload failed; trying again")
        }
    }
}
