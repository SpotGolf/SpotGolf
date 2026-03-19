---
name: install-on-phone
description: Use when the user wants to build and install the app on their physical iPhone or Apple Watch, create an .ipa file, or deploy to a connected device
---

# Install on Phone

Build the SpotGolf .ipa and install it on a connected iOS device.

## Prerequisites

- iPhone connected via USB or WiFi (Xcode > Window > Devices and Simulators > "Connect via network")
- Valid provisioning profile (auto-managed signing is configured)

## Steps

### 0. Generate ExportOptions.plist (if missing)

If `ExportOptions.plist` does not exist in the project root, create it from the template:

```bash
cd /Users/bpontarelli/dev/SpotGolf/SpotGolf

TEAM_ID=$(security find-identity -v -p codesigning | head -1 | sed 's/.*(\(.*\))/\1/')
sed "s/YOUR_TEAM_ID/$TEAM_ID/" ExportOptions.template.plist > ExportOptions.plist
```

This reads the signing team ID from your keychain and renders the template. The generated `ExportOptions.plist` is gitignored.

### 1. Find the connected device

```bash
xcrun devicectl list devices
```

Note the device UDID from the output.

### 2. Archive

```bash
cd /Users/bpontarelli/dev/SpotGolf/SpotGolf

xcodebuild archive \
  -scheme SpotGolf \
  -archivePath build/SpotGolf.xcarchive \
  -destination 'generic/platform=iOS'
```

### 3. Export .ipa

```bash
xcodebuild -exportArchive \
  -archivePath build/SpotGolf.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

### 4. Install on device

```bash
xcrun devicectl device install app \
  --device <DEVICE_UDID> \
  build/ipa/SpotGolf.ipa
```

### 5. Watch app

The watch app is embedded in the iOS app. Once the .ipa is installed on the iPhone, the watch app should automatically install on the paired Apple Watch. If it doesn't, the user can open the Watch app on their iPhone and install it manually.

## Troubleshooting

- **"Device not found"**: Ensure the device is unlocked and connected. Re-run `xcrun devicectl list devices`.
- **Signing error**: Open the project in Xcode and let it resolve signing automatically, then retry.
- **Watch app not installing**: On the iPhone, go to Watch app > My Watch > Installed on Apple Watch, and toggle SpotGolf on.
