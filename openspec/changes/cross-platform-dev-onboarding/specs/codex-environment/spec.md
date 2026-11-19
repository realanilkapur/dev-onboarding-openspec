# Spec Delta

## Purpose

When the developer chooses Codex, make the OpenAI Codex CLI runnable for the current user through a package manager, find copies installed outside PATH, and leave Codex sign-in and configuration to the user.

## ADDED Requirements

### Requirement: Codex is runnable after onboarding
When Codex is chosen, `codex --version` MUST exit 0 in a new terminal after its step, as defined in `developer-path`. If Codex is already installed, including outside PATH, the flow MUST NOT install it again.

#### Scenario: Codex is already runnable
- **WHEN** Codex is chosen and `codex --version` already exits 0
- **THEN** the step is marked already satisfied
- **AND** nothing is installed

#### Scenario: Installed by OpenAI's installer but not on PATH
- **WHEN** Codex is chosen, was installed by OpenAI's installer, and its folder is not on PATH
- **THEN** nothing is installed
- **AND** `codex --version` exits 0 in a new terminal after the PATH step

#### Scenario: Installed with npm but not on PATH
- **WHEN** Codex is chosen and is in npm's global folder, and that folder is not on PATH
- **THEN** nothing is installed
- **AND** `codex --version` exits 0 in a new terminal after the PATH step

### Requirement: Windows installs Codex with winget
When Codex is chosen and missing on Windows, the flow MUST install the winget `OpenAI.Codex` package for the current user only, without administrator rights.

#### Scenario: Missing on Windows
- **WHEN** Codex is chosen and missing on Windows
- **THEN** the flow installs `OpenAI.Codex` with winget for the current user
- **AND** no elevation prompt appears

### Requirement: macOS installs Codex with Homebrew
When Codex is chosen and missing on macOS, the flow MUST install the Homebrew `codex` cask.

#### Scenario: Missing on macOS
- **WHEN** Codex is chosen and missing on macOS
- **THEN** the flow installs the Homebrew `codex` cask

### Requirement: Linux tries Homebrew, then npm, then stops
When Codex is chosen and missing on Linux, the flow MUST install the Homebrew `codex` cask if Homebrew is present, otherwise `@openai/codex` with npm if npm is present and its global folder is writable by the user, otherwise fail the step and print OpenAI's install command without running it.

#### Scenario: Homebrew is present
- **WHEN** Codex is chosen and missing on Linux, and Homebrew is present
- **THEN** the flow installs the Homebrew `codex` cask

#### Scenario: Only npm is present
- **WHEN** Codex is chosen and missing on Linux, Homebrew is absent, and npm's global folder is writable by the user
- **THEN** the flow installs `@openai/codex` with npm
- **AND** it does not use sudo

#### Scenario: npm needs root
- **WHEN** Homebrew is absent and npm's global folder is not writable by the user
- **THEN** the Codex step fails and explains how to use a per-user npm folder
- **AND** the flow does not use sudo

#### Scenario: Neither is present
- **WHEN** Codex is chosen and missing on Linux, and neither Homebrew nor npm is present
- **THEN** the Codex step fails and prints OpenAI's install command
- **AND** nothing is downloaded or run

### Requirement: Codex installs never run a downloaded script
The flow MUST NOT run OpenAI's `install.sh` or `install.ps1`, or any other downloaded install script.

#### Scenario: Any host
- **WHEN** the Codex step runs on any host
- **THEN** no downloaded install script is run

### Requirement: Codex sign-in and configuration are left to the user
The flow MUST NOT run `codex login` and MUST NOT itself create or modify files under `~/.codex`. The summary MUST tell the user to run `codex` to sign in.

#### Scenario: Run finishes
- **WHEN** a run that chose Codex finishes with Codex available
- **THEN** `codex login` was not run and the flow wrote nothing under `~/.codex`
- **AND** the summary tells the user to run `codex` to sign in
