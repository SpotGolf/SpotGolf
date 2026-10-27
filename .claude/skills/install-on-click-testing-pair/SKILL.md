---
name: install-on-click-testing-pair
description: Use when the user asks to install the current branch on the click-testing pair (the SpotGolf Phone and SpotGolf Watch simulators), so they can test it by hand. Builds the phone and watch apps from the current checkout and installs them on that pair.
---

# Install on Click-Testing Pair

Build the phone and watch apps from the current checkout and install them on `SpotGolf Phone` and `SpotGolf Watch`.

The project's instructions forbid Claude sessions from touching the click-testing pair. Running this skill because the user asked is the one exception. It covers building, installing and launching only. Never run tests on the pair or move its location.

## Flow

```
xcodegen ──▶ boot pair ──▶ build both ──▶ install watch app ──▶ install phone app ──▶ grant permissions ──▶ launch both ──▶ check link
```

## Steps

### 1. Prepare

Run every command from the repository root:

```bash
cd "$(git rev-parse --show-toplevel)"
git branch --show-current
xcodegen generate
```

- The build uses the checkout as it is, including uncommitted changes. Do not pull, commit or switch branches.

### 2. Boot the pair

```bash
xcrun simctl list devices | grep -E "SpotGolf (Phone|Watch) \("
```

- Stop if either simulator is missing. Do not create it or clone the template.
- Boot any that is shut down: `xcrun simctl boot "SpotGolf Phone"` and `xcrun simctl boot "SpotGolf Watch"`.
- Use the UDIDs from the list as `<phone>` and `<watch>` in every later step.

### 3. Build

```bash
xcodebuild -scheme SpotGolf -destination id=<phone> -derivedDataPath build/dd-click-testing build -quiet
xcodebuild -scheme SpotGolfWatch -destination id=<watch> -derivedDataPath build/dd-click-testing build -quiet
```

Stop and report the errors if either build fails. Do not install a partial build.

### 4. Install, watch first

Install the watch app first. Wait until the phone has heard about it, then install the phone app:

```bash
products=build/dd-click-testing/Build/Products
xcrun simctl install <watch> $products/Debug-watchsimulator/SpotGolfWatch.app
for i in $(seq 30); do
  xcrun simctl spawn <phone> log show --last 15s --style compact \
    --predicate 'process == "appconduitd" AND eventMessage CONTAINS "Setting state to installed for golf.spot.SpotGolf.watchkitapp"' \
    | grep -q "Setting state" && break
  sleep 1
done
xcrun simctl install <phone> $products/Debug-iphonesimulator/SpotGolf.app
```

Why the order matters:

- The phone app has the watch app inside it. When the phone app is installed, the phone pushes that watch app to the watch, unless the exact same watch app is already there.
- The watch simulator reports 0 bytes free, so the push always fails.
- When the push fails, the phone marks the watch app as not installed. WCSession then reports `appInstalled: NO`, and the phone and watch stop talking. A restart of both simulators repairs this.
- With the watch app already installed, the phone logs "Skipping install … exact same app is already installed on watch" and makes no push.

Check that the phone skipped its push:

```bash
xcrun simctl spawn <phone> log show --last 1m --style compact \
  --predicate 'process == "appconduitd" AND (eventMessage CONTAINS "Skipping install" OR eventMessage CONTAINS "Failed to install app")'
```

If it logged "Failed to install app" instead, install the watch app again. That sets the phone's record back to installed.

Installing over the existing apps keeps their data and Health access.

### 5. Grant permissions

```bash
for service in location-always motion; do
  xcrun simctl privacy <phone> grant $service golf.spot.SpotGolf
  xcrun simctl privacy <watch> grant $service golf.spot.SpotGolf.watchkitapp
done
```

### 6. Launch

```bash
xcrun simctl launch <watch> golf.spot.SpotGolf.watchkitapp
xcrun simctl launch <phone> golf.spot.SpotGolf
```

- A watch that has just booted can refuse the launch with "Scene activation failed". Retry every 2 seconds, up to 10 times.

Then check the link. Find this in the phone app's log:

```bash
sleep 5
xcrun simctl spawn <phone> log show --last 10s --style compact \
  --predicate 'process == "SpotGolf" AND eventMessage CONTAINS "handleSessionStateChanged"' \
  | grep -o "paired: [A-Z]*, appInstalled: [A-Z]*" | tail -1
```

It must print `paired: YES, appInstalled: YES`. If it prints `appInstalled: NO`, install the watch app again, then terminate and launch the phone app, and check again.

### 7. Report

State the branch, the commit (`git rev-parse --short HEAD`), whether there were uncommitted changes, and the version (`MARKETING_VERSION` in `project.yml`). Nothing else.
