# Spec Delta

## Purpose

Publish the two onboarding scripts at one stable download address with checksums, and document download-then-run commands so developers can read a script before running it.

## ADDED Requirements

### Requirement: Each release publishes both scripts with checksums
Each release MUST publish `onboard.ps1`, `onboard.sh`, and a `SHA256SUMS` file listing each script's SHA-256 checksum, at a stable address that always serves the latest release and needs no sign-in.

#### Scenario: Release is published
- **WHEN** a release is published
- **THEN** all three files download without signing in
- **AND** each script's SHA-256 checksum matches its line in `SHA256SUMS`

### Requirement: Each script works as a single downloaded file
`onboard.ps1` and `onboard.sh` MUST each run correctly when downloaded alone, without any other file from the repository.

#### Scenario: Only the Windows script is downloaded
- **WHEN** only `onboard.ps1` is downloaded into an empty folder and run with `-Agent both -WhatIf`
- **THEN** the preview completes and reports its plan

#### Scenario: Only the macOS/Linux script is downloaded
- **WHEN** only `onboard.sh` is downloaded into an empty folder and run with `--agent both --dry-run`
- **THEN** the preview completes and reports its plan

### Requirement: The README documents download-then-run commands
For Windows, macOS, and Linux, the README MUST give a command to download the script, one to verify its checksum, and one to run it with each agent choice and as a preview. It MUST NOT present piping a download into a shell as the main method.

#### Scenario: README commands run as written
- **WHEN** a developer runs the README's Windows commands, as written, in an empty folder
- **THEN** the script downloads, its checksum verifies, and the preview runs

#### Scenario: No pipe-to-shell as the main method
- **WHEN** a reader follows the README's main instructions
- **THEN** no step pipes a downloaded file directly into PowerShell or a shell

### Requirement: Published files contain no secrets
Release files and the files in the published repository MUST NOT contain an API key, token, or password. Every release MUST pass a secret scan before it is published.

#### Scenario: Secret scan blocks a release
- **WHEN** the secret scan finds a key or token in the repository or a release file
- **THEN** the release is not published
