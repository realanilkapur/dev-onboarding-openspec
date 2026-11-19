# Spec Delta

## Purpose

Identify the machine as native Windows, macOS, or Linux, refuse shells that would set up the wrong environment, and choose the system package manager before anything is installed.

## ADDED Requirements

### Requirement: Host is identified before platform-specific commands
The flow MUST classify the host as Windows, macOS, or Linux before it runs any package-manager command, and MUST NOT run a package manager that belongs to a different host.

#### Scenario: Windows host
- **WHEN** onboarding starts in PowerShell on Windows
- **THEN** the flow classifies the host as Windows
- **AND** it does not run Homebrew, apt, dnf, or pacman

#### Scenario: macOS host
- **WHEN** onboarding starts on macOS
- **THEN** the flow classifies the host as macOS
- **AND** it does not run winget, apt, dnf, or pacman

#### Scenario: Linux host
- **WHEN** onboarding starts on Linux
- **THEN** the flow classifies the host as Linux
- **AND** it does not run winget

#### Scenario: Unrecognized host
- **WHEN** the host is none of Windows, macOS, or Linux
- **THEN** the flow stops and reports that the host is unsupported
- **AND** it does not run an install command

### Requirement: Unix shells on Windows are sent to the PowerShell entry point
When the macOS/Linux entry point runs in Git Bash, MSYS2, or Cygwin on Windows, the flow MUST stop before installing anything and MUST print the PowerShell command that runs the Windows entry point.

#### Scenario: Run from Git Bash
- **WHEN** the macOS/Linux entry point runs in Git Bash on Windows
- **THEN** the flow stops without installing anything
- **AND** it prints the PowerShell command for the Windows entry point

### Requirement: WSL is set up as Linux and says so
When the host is a WSL distribution, the flow MUST classify it as Linux and MUST report that it is setting up that WSL distribution, not native Windows.

#### Scenario: Run inside WSL
- **WHEN** the macOS/Linux entry point runs inside a WSL distribution
- **THEN** the flow classifies the host as Linux
- **AND** the summary states that tools were set up inside WSL, not for native Windows

### Requirement: Windows uses winget
On Windows the flow MUST select winget. If winget is not available, the flow MUST stop before installing anything, report that winget is missing, and MUST NOT request administrator rights to install it.

#### Scenario: winget is available
- **WHEN** the host is Windows and winget is available
- **THEN** the flow selects winget

#### Scenario: winget is missing
- **WHEN** the host is Windows and winget is not available
- **THEN** the flow stops and reports that winget is missing
- **AND** it does not request administrator rights

### Requirement: macOS uses Homebrew
On macOS the flow MUST select Homebrew when `brew` is on PATH or at `/opt/homebrew/bin/brew` or `/usr/local/bin/brew`. If none exists, the flow MUST stop before installing anything and MUST NOT run sudo to install Homebrew.

#### Scenario: Homebrew is on PATH
- **WHEN** the host is macOS and `brew` is on PATH
- **THEN** the flow selects that Homebrew

#### Scenario: Homebrew is installed but not on PATH
- **WHEN** the host is macOS, `brew` is not on PATH, and `/opt/homebrew/bin/brew` exists
- **THEN** the flow selects `/opt/homebrew/bin/brew`

#### Scenario: Homebrew is missing
- **WHEN** the host is macOS and no Homebrew is found
- **THEN** the flow stops and reports that Homebrew is missing
- **AND** it does not run sudo

### Requirement: Linux uses the first supported system package manager
On Linux the flow MUST select the first available manager in this order: apt, dnf, pacman. If none is available, the flow MUST stop before installing anything and MUST NOT install a package manager.

#### Scenario: apt is available
- **WHEN** the host is Linux and apt is available
- **THEN** the flow selects apt

#### Scenario: dnf is the first available manager
- **WHEN** the host is Linux, apt is not available, and dnf is available
- **THEN** the flow selects dnf

#### Scenario: pacman is the first available manager
- **WHEN** the host is Linux, apt and dnf are not available, and pacman is available
- **THEN** the flow selects pacman

#### Scenario: No supported manager
- **WHEN** the host is Linux and apt, dnf, and pacman are all unavailable
- **THEN** the flow stops and reports that no supported package manager was found
- **AND** it does not install a package manager
