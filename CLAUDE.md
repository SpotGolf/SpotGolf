# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SpotGolf - A simple golf ball tracking app for iOS and watchOS. The app guesses when a player takes a swing from their location data and marks the ball location via GPS.

## Status

New project, not yet scaffolded.

## Workflow

- All new features must be developed on a new branch (e.g., `feature/<name>`). Never commit feature work directly to `main`.
- All design specs and implementation plans go in the `plans/` directory (not `docs/`).

## Simulators

- `SpotGolf Phone` (iPhone 17 Pro) and `SpotGolf Watch` (Apple Watch Series 9) are a paired set kept for click testing by hand. `simulate-round.sh` and `update-location.sh` set the location on these two by name, which is why they keep those names. Claude sessions must not build to, install on, run tests on, or move the location of these two.
- Each Claude session uses its own phone and watch pair, so parallel sessions never share a device. Claude Desktop only gives a device to the session that boots it; it does not copy a device asked for by name. So a session makes its own pair by cloning the template pair:

  ```bash
  xcrun simctl clone "SpotGolf Template Phone" "SpotGolf Phone <session>"
  xcrun simctl clone "SpotGolf Template Watch" "SpotGolf Watch <session>"
  xcrun simctl pair "SpotGolf Watch <session>" "SpotGolf Phone <session>"
  ```

  `<session>` is the session's branch name with each `/` replaced by `-`, for example `feature-pin-location`. Use the clones by name or UDID in every `xcodebuild -destination`, `simctl` command and simulator tool call.
- When a branch is completed, the `complete-branch` skill deletes its clones.
- Before making its own clones, a session deletes clones left over from branches that no longer exist, such as abandoned ones. A clone is left over when its `<session>` part matches no local branch, with `/` replaced by `-`. Never delete the template pair or the click-testing pair:

  ```bash
  branches=$(git branch --format='%(refname:short)' | tr / -)
  xcrun simctl list devices | sed -nE 's/^ +SpotGolf (Phone|Watch) (.+) \(([0-9A-F-]+)\) .*/\2 \3/p' \
    | while read -r session udid; do
        [ "$session" = Template ] && continue
        echo "$branches" | grep -qx "$session" || xcrun simctl delete "$udid"
      done
  ```
- The template pair, `SpotGolf Template Phone` and `SpotGolf Template Watch`, is set up once and then left shut down: `simctl clone` refuses a booted source. A clone copies the template's data, including the permissions it was granted, so Health access granted once on the template carries over.
- After booting the clones and installing the apps, run the `simctl privacy` grants below on them again. They are quick, and they make sure location and motion are granted even if the template's grants did not carry over.
- Set the template up with every permission granted to the phone app (`golf.spot.SpotGolf`) and the watch app (`golf.spot.SpotGolf.watchkitapp`):

  | Permission | Phone | Watch | How |
  |---|---|---|---|
  | Location, always | Yes | Yes | `xcrun simctl privacy <device> grant location-always <bundle id>` |
  | Motion | Yes | Yes | `xcrun simctl privacy <device> grant motion <bundle id>` |
  | Health (workouts) | Yes | Yes | Not supported by `simctl privacy`. Install and launch the app, and allow it on the app's permissions screen |

## Project generation

The Xcode project is generated from `project.yml` with XcodeGen. Run `xcodegen generate` after changing `project.yml` or adding files.

## Versioning

- The app uses SemVer (`MAJOR.MINOR.PATCH`), starting at `0.1.0`. The phone app, watch app, and Live Activity share one version.
- The version is `MARKETING_VERSION` under `settings` in `project.yml`. Never set the version anywhere else. There is no separate build number: `CFBundleVersion` is the same version.
- Versions are determined during a release as follows:

  | Change                                                                                     | Before 1.0.0 | From 1.0.0 |
  |--------------------------------------------------------------------------------------------|--------------|------------|
  | Breaking change (for example, saved rounds or watch messages that older builds can't read) | MINOR        | MAJOR      |
  | `feat`                                                                                     | MINOR        | MINOR      |
  | `fix` and anything else                                                                    | PATCH        | PATCH      |

- Each release is a git tag on `main`, pushed to `origin`. Tags follow SemVer and are the version alone, with no prefix (for example `0.1.0`, not `v0.1.0`).
- The phone's Settings screen shows the version, so the installed build can be checked against `main`.
