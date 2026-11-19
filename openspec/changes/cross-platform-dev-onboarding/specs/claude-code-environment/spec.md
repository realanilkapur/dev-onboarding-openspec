# Spec Delta

## Purpose

When the developer chooses Claude Code, make its CLI runnable for the current user through each host's package manager, and leave Claude Code's settings untouched.

## ADDED Requirements

### Requirement: Claude Code is runnable after onboarding
When Claude Code is chosen, `claude --version` MUST exit 0 in a new terminal after its step, as defined in `developer-path`. If Claude Code is already installed, including outside PATH, the flow MUST NOT install it again.

#### Scenario: Claude Code is already runnable
- **WHEN** Claude Code is chosen and `claude --version` already exits 0
- **THEN** the step is marked already satisfied
- **AND** nothing is installed

#### Scenario: Claude Code is installed but not on PATH
- **WHEN** Claude Code is chosen and found in a known install location that is not on PATH
- **THEN** nothing is installed
- **AND** `claude --version` exits 0 in a new terminal after the PATH step

### Requirement: Claude Code installs use the host's package manager
When Claude Code is chosen and missing, the flow MUST install it with winget for the current user on Windows, with the Homebrew `claude-code` cask on macOS, or from Anthropic's package repository with apt or dnf on Linux.

#### Scenario: Missing on Windows
- **WHEN** Claude Code is chosen and missing on Windows
- **THEN** the flow installs the winget `Anthropic.ClaudeCode` package for the current user
- **AND** no elevation prompt appears

#### Scenario: Missing on macOS
- **WHEN** Claude Code is chosen and missing on macOS
- **THEN** the flow installs the Homebrew `claude-code` cask

### Requirement: Anthropic's Linux repository is trusted only after its key is verified
On apt and dnf hosts the flow MUST verify that the downloaded signing key's fingerprint matches the one Anthropic publishes before adding Anthropic's repository, and MUST confirm each sudo command with the user. A repository that is already set up MUST NOT be added again.

#### Scenario: Key matches
- **WHEN** Claude Code is chosen and missing on an apt or dnf host and the key fingerprint matches
- **THEN** the flow adds the repository and installs `claude-code`
- **AND** each sudo command was confirmed separately

#### Scenario: Key does not match
- **WHEN** the downloaded key's fingerprint does not match
- **THEN** the Claude Code step fails
- **AND** no repository file or trusted key is written

#### Scenario: User declines a sudo command
- **WHEN** the user does not type `YES` for one of the repository or install commands
- **THEN** that command and the later Claude Code commands do not run
- **AND** the Claude Code step is marked declined, and the Codex step still runs when Codex was also chosen

#### Scenario: Repository is already set up
- **WHEN** Anthropic's repository is already configured
- **THEN** the flow does not add it again

### Requirement: Without a Claude Code package, nothing is downloaded and run
On pacman hosts, or whenever the package manager cannot install Claude Code, the step MUST fail with a pointer to Anthropic's install documentation and MUST NOT run a downloaded install script.

#### Scenario: pacman host
- **WHEN** Claude Code is chosen and missing on a pacman host
- **THEN** the step fails and points to Anthropic's install documentation
- **AND** no install script is downloaded or run

### Requirement: Claude Code settings are left untouched
The flow MUST NOT create or modify `~/.claude/settings.json`.

#### Scenario: Settings file exists
- **WHEN** a run finishes and `~/.claude/settings.json` existed before
- **THEN** it is byte-for-byte unchanged

#### Scenario: Settings file is absent
- **WHEN** a run finishes and `~/.claude/settings.json` did not exist before
- **THEN** it still does not exist
