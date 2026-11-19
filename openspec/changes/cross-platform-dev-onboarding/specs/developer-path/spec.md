# Spec Delta

## Purpose

Find installed tools even when their folder is not on PATH, and add that folder to the user's PATH so a new terminal can run them, without disturbing existing entries.

## ADDED Requirements

### Requirement: Installed tools are found outside PATH
Before reporting Git or a chosen agent (`claude` or `codex`) as missing, the flow MUST check that tool's known install locations on the host. A tool found there MUST be treated as installed, and its folder MUST be added to PATH.

#### Scenario: Claude Code from the native Windows installer
- **WHEN** Claude Code is chosen, `%USERPROFILE%\.local\bin\claude.exe` exists, and that folder is not on PATH
- **THEN** the flow does not reinstall Claude Code
- **AND** it adds `%USERPROFILE%\.local\bin` to the user PATH

#### Scenario: Codex from OpenAI's Windows installer
- **WHEN** Codex is chosen, `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe` exists, and that folder is not on PATH
- **THEN** the flow does not reinstall Codex
- **AND** it adds that folder to the user PATH

#### Scenario: Tool is not found anywhere
- **WHEN** a tool is neither on PATH nor in any known location
- **THEN** the flow reports it missing and runs that tool's install step

### Requirement: "Runnable in a new terminal" is checked against saved settings
The flow MUST verify a tool by running `<tool> --version` with PATH rebuilt from saved settings: on Windows from the machine and user PATH values; on macOS in a new interactive login shell; on Linux in a new interactive shell. Exit status 0 means runnable.

#### Scenario: Windows PowerShell or Command Prompt
- **WHEN** the flow verifies a tool on Windows
- **THEN** it runs `<tool> --version` in a process whose PATH is built from the machine and user PATH values

#### Scenario: Windows Git Bash
- **WHEN** the flow verifies a tool on Windows and Git Bash was resolved
- **THEN** `bash.exe -l -c '<tool> --version'`, started with PATH built from the machine and user PATH values, exits 0

#### Scenario: macOS or Linux
- **WHEN** the flow verifies a tool on macOS or Linux
- **THEN** it runs `<tool> --version` in a new shell of the user's login shell started the way that host's terminal starts it

### Requirement: PATH entries are appended without disturbing existing ones
The flow MUST add a tool folder only when it is not already on PATH, MUST append it at the end, and MUST keep every existing entry unchanged and in order, including unexpanded references such as `%USERPROFILE%`.

#### Scenario: Folder is missing
- **WHEN** a tool folder is not on PATH
- **THEN** the flow appends it
- **AND** every earlier entry is still present in the same order

#### Scenario: Entry with a variable reference
- **WHEN** the Windows user PATH contains `%USERPROFILE%\bin`
- **THEN** after the update it still contains the literal text `%USERPROFILE%\bin`

#### Scenario: Folder is already present
- **WHEN** the folder is already on the Windows machine or user PATH, ignoring case and a trailing `\`
- **THEN** the flow does not add it again

#### Scenario: User PATH is empty
- **WHEN** the Windows user PATH is empty or unset
- **THEN** the flow sets it to the tool folder alone

### Requirement: Windows changes the user PATH only
On Windows the flow MUST update the current user's PATH and MUST NOT modify the machine PATH or Git Bash startup files.

#### Scenario: User PATH is updated
- **WHEN** a tool folder is added on Windows
- **THEN** it appears in the user PATH
- **AND** the machine PATH and `~/.bashrc` are unchanged

### Requirement: macOS and Linux PATH lines go in the file the user's shell reads
On macOS and Linux the flow MUST append one PATH line for the folder to `~/.zshrc` for zsh, `~/.bash_profile` for bash on macOS, or `~/.bashrc` for bash on Linux, and MUST NOT add it when that file already adds the folder.

#### Scenario: zsh
- **WHEN** the login shell is zsh and a tool folder is missing from PATH
- **THEN** the flow appends the line to `~/.zshrc`

#### Scenario: bash on macOS
- **WHEN** the host is macOS, the login shell is bash, and a tool folder is missing from PATH
- **THEN** the flow appends the line to `~/.bash_profile`

#### Scenario: bash on Linux
- **WHEN** the host is Linux, the login shell is bash, and a tool folder is missing from PATH
- **THEN** the flow appends the line to `~/.bashrc`

#### Scenario: File already adds the folder
- **WHEN** the shell startup file already adds the folder, even though the current terminal's PATH does not include it
- **THEN** the flow adds no line

#### Scenario: Unsupported login shell
- **WHEN** the login shell is neither zsh nor bash
- **THEN** that tool's PATH step fails and prints the line for the user to add
- **AND** no shell startup file is modified

#### Scenario: Startup file is not writable
- **WHEN** the shell startup file cannot be written by the user
- **THEN** that tool's PATH step fails
- **AND** the flow does not use sudo
