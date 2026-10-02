# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SpotGolf - A simple golf ball tracking app for iOS and watchOS. The app guesses when a player takes a swing from their location data and marks the ball location via GPS.

## Status

New project, not yet scaffolded.

## Workflow

- All new features must be developed on a new branch (e.g., `feature/<name>`). Never commit feature work directly to `main`.
- All design specs and implementation plans go in the `plans/` directory (not `docs/`).

## Versioning

- The app uses SemVer (`MAJOR.MINOR.PATCH`), starting at `0.1.0`. The phone app, watch app, and Live Activity share one version.
- The version is `MARKETING_VERSION` under `settings` in `project.yml`. Never set the version anywhere else. There is no separate build number: `CFBundleVersion` is the same version.
- Every squash merge to `main` changes the version in that commit:

  | Change | Before 1.0.0 | From 1.0.0 |
  |---|---|---|
  | Breaking change (for example, saved rounds or watch messages that older builds can't read) | MINOR | MAJOR |
  | `feat` | MINOR | MINOR |
  | `fix` and anything else | PATCH | PATCH |

- Each release is a git tag on `main`, pushed to `origin`. Tags follow SemVer and are the version alone, with no prefix (for example `0.1.0`, not `v0.1.0`).
- The phone's Settings screen shows the version, so the installed build can be checked against `main`.
