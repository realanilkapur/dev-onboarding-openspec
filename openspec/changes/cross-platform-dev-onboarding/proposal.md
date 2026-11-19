# Proposal

## Why

Teams adopting AI coding agents need Claude Code or OpenAI Codex, plus Git, working on every developer's machine before any workflow built on those agents can start. That setup breaks most often on native Windows. In a first-hand setup on Windows 11, Claude Code was installed but not on PATH, Codex was installed in folders Git Bash could not see, the instructions assumed bash while the developer used PowerShell, and an installer auto-launched Claude Code from a pipe and failed with "stdin is not a terminal" after a successful install. macOS and Linux have their own versions of the same problem: which shell startup file a new terminal reads, which package manager to use, and Linux packages that need root.

The developers doing this setup know their own machines and are wary of opaque installers. They want one command they can read, preview, and rerun. This change gives them one command per platform that leaves Git and the coding agent they choose (Claude Code, Codex, or both) installed, on PATH, and runnable in a new terminal on native Windows, macOS, and Linux, without overwriting any existing user configuration.

## What Changes

- Provide one documented command per platform, with the agent choice in the command: `-Agent claude|codex|both` on Windows and `--agent claude|codex|both` on macOS and Linux. Without a valid choice, stop before doing anything and print usage help. Ship no launcher or installer executable.
- Ship each platform's script as a single self-contained file: `onboard.ps1` for Windows and `onboard.sh` for macOS and Linux.
- Publish both scripts and a `SHA256SUMS` checksum file on the GitHub releases of the public repo `realanilkapur/dev-onboarding-openspec`. The README gives download, verify, and run commands, so developers can read a script before running it.
- Add a preview run (`-WhatIf` on Windows, `--dry-run` on macOS and Linux) that reports what is already installed and every change a real run would make, without changing anything.
- Guide the developer step by step by default. Before each step that changes something, show what it found and what it will change, and wait for Next, Skip, or Quit. Skipped steps are listed in the summary and offered again when the command is rerun. `-NoGuide` / `--no-guide` runs straight through.
- Publish a static guide page on GitHub Pages that walks through the install process with Next, Back, and Skip: choose platform and agent, download, verify (skippable), preview (skippable), run, and sign in. The page only shows commands; it never downloads or runs anything.
- Print every install command, PATH change, shell startup file change, and execution policy change before making it.
- Detect native Windows, macOS, or Linux before any install. Send Git Bash, MSYS2, and Cygwin users to the PowerShell command, and say so when the host is WSL.
- Install missing tools with each host's package manager: winget on Windows, Homebrew on macOS, and apt, dnf, or pacman on Linux. Never run a downloaded install script.
- Install Git and, when Claude Code is chosen on Windows, resolve the Git Bash that ships with Git for Windows. Never change the user's Git configuration.
- Install Claude Code with winget, the Homebrew cask, or Anthropic's signed apt/dnf repository after verifying its key. On pacman, stop and point to Anthropic's docs.
- Install Codex with winget on Windows and the Homebrew cask on macOS. On Linux use Homebrew, then npm, then stop and print OpenAI's command.
- Find tools that are already installed, including outside PATH, instead of reinstalling them, and add their folders to the user PATH or to the shell startup file a new terminal reads.
- On Windows, set a current-user PowerShell execution policy only when local scripts are blocked. Ask before weakening AllSigned, and leave Group Policy alone.
- Before modifying any existing file in the home directory, copy it to a backup that never overwrites an earlier backup.
- Make each run predictable:
  - Each step reports its own outcome, and a failure blocks only the steps that depend on it.
  - Every sudo command needs a typed `YES` read from the terminal.
  - Neither `claude` nor `codex` is auto-launched.
  - A second run changes nothing.
  - No API key or token passes through the scripts.
  - The run ends with a summary.

Out of scope:

- Installing or configuring tools and plugins that build on Claude Code or Codex, including their API keys.
- A web page that detects what is installed, or that downloads or runs anything itself.
- Double-click launchers, signed installers, and Microsoft Store packaging.
- Signing in to Claude Code or Codex.
- Pinning minimum versions.
- Git `user.name` and `user.email`.
- Machine-wide PATH or execution policy.
- Unattended elevation.

## Capabilities

### New Capabilities

- `platform-detection`: Identify the host, redirect Windows-hosted Unix shells, and choose the system package manager.
- `onboarding-run`: Agent choice, guided Next/Skip steps, preview runs, showing each change before it is made, step outcomes and dependencies, the per-command `YES` gate, terminal-only prompts, no auto-launch, re-run behavior, secrets, the end-of-run summary, and the Windows launch command.
- `config-backup`: Back up existing home-directory files before modification without overwriting earlier backups.
- `git-environment`: Make Git runnable and, on Windows, resolve Git for Windows' Git Bash.
- `developer-path`: Find tools installed outside PATH, append their folders to PATH, and verify them in a new terminal.
- `powershell-execution-policy`: Let the current user run local scripts on Windows without elevation.
- `claude-code-environment`: Make the Claude Code CLI runnable and leave its settings untouched.
- `codex-environment`: Make the OpenAI Codex CLI runnable and leave its sign-in and configuration to the user.
- `onboarding-distribution`: Publish the two scripts with checksums at one stable download address, and document download-then-run commands.
- `setup-guide`: A static web page that walks through the install process step by step and shows the README's commands.

### Modified Capabilities

- None. This repository has no existing specs.

## Impact

- New onboarding scripts, tests, README, a static guide page published with GitHub Pages, and a release workflow in this repository. There is no application runtime or API to change.
- This repository becomes public on GitHub as `realanilkapur/dev-onboarding-openspec`, including its planning documents. Publishing happens only after the specs are reviewed and the secret scan passes.
- Changes the developer machine at user scope only: the user PATH, the current-user PowerShell execution policy, and shell startup files. Each existing file is backed up first.
- On Linux, installing Git or Claude Code with apt or dnf runs sudo commands, each one confirmed separately.
- Depends on winget (Windows), Homebrew (macOS), and apt, dnf, or pacman (Linux). It also uses Homebrew or npm for Codex on Linux when present. A missing package manager is reported, never installed.
