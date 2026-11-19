# Spec Delta

## Purpose

Make Git runnable for the current user and, when Claude Code is chosen on Windows, find the Git Bash that ships with Git for Windows, without changing the user's Git configuration.

## ADDED Requirements

### Requirement: Git is runnable after onboarding
After the Git step, `git --version` MUST exit 0 in a new terminal, as defined in `developer-path`, whichever agent was chosen. If it already does, the flow MUST NOT install Git again.

#### Scenario: Git is already runnable
- **WHEN** `git --version` already exits 0
- **THEN** the flow reports Git as already satisfied
- **AND** it installs nothing

#### Scenario: Git is missing on Windows
- **WHEN** the host is Windows and Git is not installed
- **THEN** the flow installs Git for Windows with winget for the current user
- **AND** `git --version` exits 0 in a new terminal

#### Scenario: Git is missing on macOS
- **WHEN** the host is macOS and `git --version` does not exit 0
- **THEN** the flow installs Git with Homebrew

#### Scenario: Git is missing on Linux
- **WHEN** the host is Linux and Git is not installed
- **THEN** the flow installs the selected package manager's `git` package after the user confirms each sudo command

#### Scenario: macOS placeholder git
- **WHEN** `/usr/bin/git` exists on macOS but `git --version` does not exit 0
- **THEN** the flow treats Git as missing

### Requirement: Windows Git installs are per-user only
On Windows the flow MUST install Git for Windows for the current user only. If no per-user install is available, the Git step MUST fail and print the machine-wide command, and the flow MUST NOT install Git machine-wide itself.

#### Scenario: Per-user install is unavailable
- **WHEN** winget cannot install Git for Windows for the current user only
- **THEN** the Git step is marked failed
- **AND** the flow prints the machine-wide install command and does not run it

### Requirement: Windows Git Bash is resolved from Git for Windows
When Claude Code is chosen on Windows, the flow MUST resolve the absolute path of the `bash.exe` that belongs to Git for Windows, preferring the installation that provides the `git` on PATH. It MUST NOT accept a `bash.exe` from `System32`, `WindowsApps`, or a WSL distribution.

#### Scenario: Default install location
- **WHEN** Git for Windows is installed at `C:\Program Files\Git`
- **THEN** the flow reports `C:\Program Files\Git\bin\bash.exe`

#### Scenario: Per-user install location
- **WHEN** Git for Windows is installed at `%LOCALAPPDATA%\Programs\Git`
- **THEN** the flow reports `%LOCALAPPDATA%\Programs\Git\bin\bash.exe` as an absolute path

#### Scenario: Custom install location
- **WHEN** the `git` on PATH is `D:\Tools\Git\cmd\git.exe`
- **THEN** the flow reports `D:\Tools\Git\bin\bash.exe`

#### Scenario: Only a WSL bash exists
- **WHEN** Git is runnable and the only `bash.exe` found is the WSL launcher in `System32` or `WindowsApps`
- **THEN** the Git Bash step fails with "Git Bash was not found"

#### Scenario: Claude Code not chosen
- **WHEN** the developer chose only Codex
- **THEN** the Git Bash step is marked not applicable

#### Scenario: Non-Windows host
- **WHEN** the host is macOS or Linux
- **THEN** the Git Bash step is marked not applicable

### Requirement: Claude Code's Git Bash setting is suggested, not written
When the resolved Git Bash path is not `C:\Program Files\Git\bin\bash.exe`, the summary MUST show that path with the `CLAUDE_CODE_GIT_BASH_PATH` setting name. The flow MUST NOT write that setting.

#### Scenario: Git Bash is in a non-default location
- **WHEN** Git Bash resolves to `D:\Tools\Git\bin\bash.exe`
- **THEN** the summary shows `CLAUDE_CODE_GIT_BASH_PATH` with that path
- **AND** no Claude Code settings file is created or modified

### Requirement: Git configuration is left unchanged
The flow MUST NOT create or modify `~/.gitconfig` or the system Git configuration, and MUST NOT set `user.name` or `user.email`.

#### Scenario: Run finishes
- **WHEN** a run finishes
- **THEN** `~/.gitconfig` is byte-for-byte the same as before the run, or still absent
