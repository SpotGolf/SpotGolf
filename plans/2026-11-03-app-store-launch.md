# App Store Launch

## Checklist

### 1. Apple accounts (you)

- [x] Free Apps agreement is Active. [Details](#free-apps-agreement)
- [x] EU trader status is set. [Details](#eu-trader-status)
- [x] App ID capabilities are on. [Details](#app-id-capabilities)

### 2. Code

- [x] Privacy manifests for the phone and watch
- [x] Encryption question answered in the app
- [x] iPhone only
- [x] Motion and microphone permission text mentions Putt Data Sharing
- [x] `SpotGolf App Store` scheme, without Developer Mode
- [x] OpenStreetMap credit on the map and in Settings > About
- [ ] You: confirm the [collected data table](#collected-data) lists everything the app sends you, and nothing more
- [x] You: check the motion and microphone text in `project.yml`
- [x] Commit and merge `feat/app-store-readiness`
- [x] Release version 0.16.0

### 3. Website

- [x] Claude: write the support page
- [x] Claude: write the privacy policy
- [x] You: put both pages live

### 4. CloudKit (you)

- [x] Deploy the schema to Production. [Details](#cloudkit-schema)

### 5. App Store Connect: App Information (you)

- [x] Subtitle (Claude drafts)
- [x] Category: Sports, then Health & Fitness
- [x] Content Rights: Yes and Yes
- [x] Age Rating: No or None to every question (4+)
- [x] Save

### 6. App Store Connect: Pricing and Availability (you)

- [x] Price: Free
- [x] Countries: all except China mainland (needs a Chinese government filing)
- [x] Mac with Apple silicon: Off
- [x] Apple Vision Pro: Off

### 7. App Store Connect: App Privacy (you)

- [x] Privacy Policy URL
- [x] "Yes, we collect data", then tick the 7 boxes in the [collected data table](#collected-data)
- [x] For each one: purposes from the table, linked to the user No, tracking No
- [x] Publish

### 8. Build and TestFlight (you)

- [x] Archive and upload. [Details](#archive-and-upload)
- [x] TestFlight > Internal Testing: add a group with you in it, then add the build
- [x] Play a round with the TestFlight build on your phone and watch

### 9. Screenshots and video

- [x] iPhone screenshots, 6.9" (1320 × 2868)
- [x] Apple Watch screenshots, one size
- [x] Video of a round, for App Review

### 10. App Store Connect: iOS App > 1.0 Prepare for Submission (you)

- [ ] iPhone and Apple Watch screenshots
- [ ] Promotional Text, Description, Keywords (Claude drafts)
- [ ] Support URL
- [ ] Version (under General App Information): the build's version
- [ ] Copyright: 2026 and your name or company
- [ ] Build: pick the TestFlight build
- [ ] App Review Information: Sign-in required Off, your contact info, notes (Claude drafts), the video as the attachment
- [ ] Version Release: Manually release this version
- [ ] Save

### 11. Submit (you)

- [ ] Add for Review, then Submit to App Review
- [ ] After approval: Release This Version

## Details

### Free Apps agreement

App Store Connect > Business > Agreements tab. The Free Apps row should say Active. If not, the account holder accepts it there. A free app needs no tax or bank details.

### EU trader status

App Store Connect > Business > Agreements tab > Compliance > Digital Services Act > Complete Compliance Requirements. Needs the account holder or an admin. Without it, the app is not on the EU App Store.

| Choice | Result |
|---|---|
| Trader (the app is part of a business) | Your address, phone and email show on the EU App Store page |
| Not a trader | No contact info needed |

### App ID capabilities

developer.apple.com > Account > Certificates, Identifiers & Profiles > Identifiers. Open each one and check its Capabilities tab. Xcode usually turned these on already.

| Identifier | Must be on |
|---|---|
| `golf.spot.SpotGolf` | HealthKit, iCloud (CloudKit, container `iCloud.golf.spot.SpotGolf`), Push Notifications |
| `golf.spot.SpotGolf.watchkitapp` | HealthKit |
| `golf.spot.SpotGolf.LiveActivity` | Nothing |

### CloudKit schema

icloud.developer.apple.com > CloudKit Console > container `iCloud.golf.spot.SpotGolf` > Deploy Schema Changes > Deploy. Do it before the TestFlight round: TestFlight and App Store builds use Production.

### Archive and upload

1. Xcode: pick the `SpotGolf App Store` scheme and Any iOS Device.
2. Product > Archive.
3. Organizer window: Distribute App > App Store Connect > Distribute.
4. The build shows in TestFlight once Apple finishes processing it.

Each version can be uploaded once. To upload again (for example after a rejection), release a new PATCH version first.

### Collected data

What the phone sends to CloudKit's public database, which the developers can read. Rounds and settings are not in it: iCloud Sync keeps them in the player's private database, which the developers can't read.

Tick these 7 boxes on the App Privacy form:

| Form section | Box | What SpotGolf sends | Purposes |
|---|---|---|---|
| Health & Fitness | Fitness | Putt Data Sharing: wrist motion | Other Purposes |
| Location | Precise Location | Shared pins; drill start location | App Functionality, Other Purposes |
| User Content | Audio Data | Putt Data Sharing: sound | Other Purposes |
| Identifiers | User ID | Putt Data Sharing: random ID made at consent. CloudKit also adds an ID for the player's iCloud account to every shared pin and putt session | App Functionality, Other Purposes |
| Usage Data | Product Interaction | Putt Data Sharing: drill start times, Done taps | Other Purposes |
| Diagnostics | Other Diagnostic Data | Putt Data Sharing: app version, watch model, watchOS version | Other Purposes |
| Other Data | Other Data | Putt Data Sharing: hand, putter, grip, ball, handicap range | Other Purposes |

Leave these unticked, though they sound close:

| Box | Why not |
|---|---|
| Health | HealthKit data stays on the phone |
| Hands (Body) | For Apple Vision Pro hand tracking. Wrist motion is Fitness |
| Coarse Location | The locations sent are precise |
| Device ID | The watch model is not an ID |
