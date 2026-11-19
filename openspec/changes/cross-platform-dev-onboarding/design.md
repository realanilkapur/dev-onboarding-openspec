# Design

## Context

See proposal.md for why. The repository has OpenSpec setup, agent skills, and the always-on guardrail in `.cursor/rules/onboarding-guardrails.mdc`. It has no scripts, tests, README, or remote yet. The guardrail requires a backup before editing `~/.gitconfig`, `~/.zshrc`, `~/.bashrc`, or `~/.claude/settings.json`, a pause before `sudo` or Windows elevation, no API keys in tracked files, and an OS check before `winget` or `brew`.

External facts this design relies on:

- Claude Code's setup docs (https://code.claude.com/docs/en/setup): winget `Anthropic.ClaudeCode`, Homebrew cask `claude-code`, and signed apt/dnf/apk repositories. Anthropic's published signing key fingerprint is `31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`. The native Windows installer puts `claude.exe` in `%USERPROFILE%\.local\bin`. On macOS and Linux it uses `~/.local/bin/claude`. Claude Code reads `CLAUDE_CODE_GIT_BASH_PATH` when it cannot find Git Bash.
- Codex CLI docs (https://learn.chatgpt.com/docs/codex/cli) and its README: Homebrew cask `codex`, npm `@openai/codex`, and `install.sh`/`install.ps1` scripts. winget carries `OpenAI.Codex`, which can trail npm by a few releases. OpenAI's Windows script exposes `codex.exe` in `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin` and keeps releases under `%USERPROFILE%\.codex\packages\standalone`. On macOS and Linux it links `~/.local/bin/codex`.
- Git for Windows is winget `Git.Git`, whose manifest has per-user installers for x64 and arm64.

## Goals / Non-Goals

**Goals:**

- Two single-file entry scripts, `scripts/onboard.ps1` and `scripts/onboard.sh`, that implement the nine specs.
- Every step is testable without touching the real profile, PATH, registry, or package managers.
- Releases reproducible from a tag, with checksums.

**Non-Goals:**

- A shared runtime such as Node or Python, or PowerShell on macOS and Linux.
- Upgrading tools that are already installed.
- Any content about products built on top of Claude Code or Codex. Planning for those lives outside this repository.

## Decisions

### Two single-file scripts with a test hook

`onboard.ps1` targets Windows PowerShell 5.1 and later. `onboard.sh` targets bash 3.2, the bash that ships with macOS. Each file holds all of its functions, so a downloaded copy runs alone.

The main routine runs only when the file is executed directly:
- In PowerShell, when it isn't dot-sourced (`$MyInvocation.InvocationName -ne '.'`).
- In bash, when `[[ "${BASH_SOURCE[0]}" == "$0" ]]`.

Tests dot-source or `source` the file and replace the functions that touch the system (registry, winget, package managers, sudo, prompts) with stubs: Pester `Mock` in PowerShell, redefined shell functions in bash.

Alternative considered: a `lib/` folder of helpers. Rejected because a single downloaded file would then fail.

### Parameters, usage, and exit codes

- PowerShell: `[CmdletBinding(SupportsShouldProcess)]` with a string `-Agent`. It's validated by hand, so a bad value prints our usage text instead of a PowerShell error. `SupportsShouldProcess` provides the standard `-WhatIf` switch; the script reads `$WhatIfPreference` once at startup and runs the whole flow in preview mode.
- PowerShell also takes a `-NoGuide` switch to run without pausing at each step.
- bash: `--agent`, `--dry-run`, `--no-guide`, and `--help`.
- Exit codes: 0 when every step is done, already satisfied, or not applicable; 1 when any step was declined or failed; 2 for a usage error, with no step run.

### Steps and dependencies

| Step | Runs when | Depends on |
| --- | --- | --- |
| Arguments | always | none |
| Host and package manager | always | arguments |
| Execution policy | Windows | host |
| Git (find or install) | always | host |
| Git PATH | Git found or installed | Git |
| Git Bash | Windows and Claude Code chosen | Git |
| Claude Code (find or install) | Claude Code chosen | host |
| Claude Code PATH | Claude Code found or installed | Claude Code |
| Codex (find or install) | Codex chosen | host |
| Codex PATH | Codex found or installed | Codex |
| Summary | always | none |

Each step returns one of: done, already satisfied, not applicable, skipped, declined, or failed. A step runs only when every step it depends on ended as done or already satisfied. Otherwise it's marked skipped, with the step it needed. Skipped steps don't affect the exit code; declined and failed steps make it 1.

### Guided mode

Guided mode is on when prompts are possible (the same terminal check as the YES gate), the run isn't a preview, and `-NoGuide` / `--no-guide` wasn't given. The switch isn't named `-Yes`, because it doesn't answer the sudo or AllSigned questions. A `--yes` flag would suggest that it does.

1. After detection, the run prints its plan: every step for this host and agent choice, with what detection found.
2. Steps that are already satisfied or not applicable print one line and don't pause.
3. A step that would change something prints a screen and waits:
   ```
   Step 6 of 8: Claude Code on PATH
   Lets new terminals find claude.
   Found:    C:\Users\dev\.local\bin is not on your user PATH
   Will do:  Append to your user PATH: %USERPROFILE%\.local\bin
   [Enter] Next   [S] Skip   [Q] Quit
   ```
4. The answer is read as a whole line from the terminal: empty means Next, `s` Skip, `q` Quit, case-insensitive. Single-key reading isn't reliable across bash 3.2 and Windows PowerShell 5.1.
5. Next approves the step, never a sudo command inside it.
6. Skip marks the step skipped. Quit marks it and every later step skipped, then prints the summary.

The screens are plain text. Color is used only when the output is a terminal and `NO_COLOR` is unset.

### Showing and previewing changes

Each step is a detect function, which only reads, and an apply function, which makes the change. Detection returns what it found and the exact list of changes it would make. The step runner prints that list as "Will do:" before a real change, or "Would do:" in a preview, and in a preview it never calls an apply function. Steps that depend on a step that would change print "checked after <step>", because what they would find depends on that change.

Inside an apply function, each change is printed as `Running: <command or edit>` just before it runs: `Invoke-OnboardChange` in PowerShell, `run_cmd` and `run_sudo` in bash. Keeping the preview decision in the runner, instead of in each wrapper call, means no apply code can run in a preview by mistake.

### Host detection

- PowerShell: Windows when `$IsWindows` is true or, on 5.1 where that variable doesn't exist, when `$env:OS -eq 'Windows_NT'`.
- bash, using `uname -s`:
  - `Darwin` is macOS.
  - `Linux` is Linux, reported as WSL when `WSL_DISTRO_NAME` is set or `/proc/sys/fs/binfmt_misc/WSLInterop` exists.
  - `MINGW*`, `MSYS*`, and `CYGWIN*` stop the run and print the PowerShell command.
  - Anything else is unsupported.
- Homebrew on macOS is `command -v brew`, then `/opt/homebrew/bin/brew`, then `/usr/local/bin/brew`.

### Package commands

| Host | Git | Claude Code | Codex |
| --- | --- | --- | --- |
| Windows | winget `Git.Git` | winget `Anthropic.ClaudeCode` | winget `OpenAI.Codex` |
| macOS | `brew install git` | `brew install --cask claude-code` | `brew install --cask codex` |
| Linux apt | `sudo apt-get install -y git` | Anthropic apt repository, then `sudo apt-get install -y claude-code` | Homebrew cask, then npm, then stop |
| Linux dnf | `sudo dnf install -y git` | Anthropic dnf repository, then `sudo dnf install -y claude-code` | Homebrew cask, then npm, then stop |
| Linux pacman | `sudo pacman -S --noconfirm git` | stop and point to Anthropic's docs | Homebrew cask, then npm, then stop |

Every winget install is `winget install -e --id <id> --source winget --scope user --disable-interactivity --accept-package-agreements --accept-source-agreements`. The script never passes `--scope machine`. When winget reports no applicable per-user installer, the step fails and prints the same command with `--scope machine` for the user to run themselves.

Anthropic's Linux repository steps are copied from Anthropic's setup page and pinned in the script:
- Key: `https://downloads.claude.ai/keys/claude-code.asc`.
- apt: the key goes to `/etc/apt/keyrings/claude-code.asc`, and `/etc/apt/sources.list.d/claude-code.list` holds `deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main`.
- dnf: the key is imported with `rpm --import`, and `/etc/yum.repos.d/claude-code.repo` points to `https://downloads.claude.ai/claude-code/rpm/stable` with `gpgcheck=1`.
- The package is `claude-code`.

The key is downloaded to a temp folder as the user. Before any repository file is written, `gpg --batch --show-keys --with-colons` must show exactly one primary key whose fingerprint equals the pinned one; otherwise the step fails and nothing is written. Files are put in place with `sudo install -m 0644`, and each `sudo` command goes through the `YES` gate on its own. If the repository file already exists, those steps are skipped.

Codex on Linux:
- Homebrew is `command -v brew`, then `/home/linuxbrew/.linuxbrew/bin/brew`.
- npm is used only when `npm prefix -g` points to a folder the user can write.
- Otherwise the step prints `curl -fsSL https://chatgpt.com/codex/install.sh | sh` as OpenAI's command, without running it.

### Known install locations

| Tool | Windows | macOS and Linux |
| --- | --- | --- |
| Git | `C:\Program Files\Git\cmd`, `%LOCALAPPDATA%\Programs\Git\cmd` | `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` |
| Claude Code | `%USERPROFILE%\.local\bin`, `%LOCALAPPDATA%\Microsoft\WinGet\Links` | `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin` |
| Codex | `%CODEX_INSTALL_DIR%` if set, `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin`, `%CODEX_HOME%` or `%USERPROFILE%\.codex` + `\packages\standalone\current\bin`, `%APPDATA%\npm`, `%LOCALAPPDATA%\Microsoft\WinGet\Links` | `~/.local/bin`, `~/.codex/packages/standalone/current/bin`, `$(npm prefix -g)/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/home/linuxbrew/.linuxbrew/bin` |

A tool counts as installed only when `<tool> --version` exits 0 from that location.

On macOS, `/usr/bin/git` is a placeholder until Apple's Command Line Tools are installed, and running it opens an install dialog. The script runs it only when `xcode-select -p` succeeds. Otherwise it treats Git as missing and installs it with Homebrew.

### "Runnable in a new terminal"

Right after a winget install, the running process still has the old PATH, so the script never trusts its own `$env:Path`.

- **Windows:** it builds a fresh PATH from the raw machine and user values in the registry, expands them, resolves `<tool>` against that PATH, and runs `<tool> --version`. Git Bash is located and reported, with the `CLAUDE_CODE_GIT_BASH_PATH` hint, but tools aren't run through it.
- **macOS:** `"$SHELL" -l -i -c '<tool> --version' </dev/null`, because Terminal opens login shells.
- **Linux:** `"$SHELL" -i -c '<tool> --version' </dev/null`, because terminal emulators open interactive non-login shells.

To read a new terminal's PATH on macOS and Linux, the same shell prints `$PATH` between two marker strings, and only the text between the markers is used, so anything a startup file prints is ignored.

### Windows PATH writes

The script reads `HKCU\Environment\Path` raw, with `DoNotExpandEnvironmentNames`, so `%VAR%` entries survive, and writes it back as `REG_EXPAND_SZ`. It then broadcasts `WM_SETTINGCHANGE` so newly started terminals see the change. It never uses `setx`, which can cut PATH off at 1024 characters, and never writes the machine PATH.

To check for duplicates, it expands both the machine and user values, trims trailing `\`, and compares without regard to case.

### macOS and Linux PATH lines

The file is `~/.zshrc` for zsh, `~/.bash_profile` for bash on macOS, and `~/.bashrc` for bash on Linux, taken from `basename "$SHELL"`. The appended line is `export PATH="$PATH:<dir>"` with a trailing `# added by onboard.sh` comment. If the file already mentions `<dir>`, nothing is added. Appending with `>>` writes through a symbolic link and leaves it a link. Any other shell fails that PATH step and prints the line for the user to add.

### Backups

The script picks the first free name among `<file>.bak`, `<file>.<yyyyMMddHHmmss>.bak`, and `<file>.<yyyyMMddHHmmss>-<n>.bak`.

- **macOS and Linux:** the copy is `cp -pL`, which follows links and keeps permissions. It fails if the target already exists; that check runs just before the copy, and the copy is verified afterwards with `cmp`.
- **Windows:** the only thing the script changes outside package installs is the user PATH, which lives in the registry, not a file. Before writing it, the script saves the raw value to `%LOCALAPPDATA%\onboard\user-path.txt.bak`, using the same naming rule, and opens the backup with `FileMode.CreateNew` so it can never overwrite.

A failed backup fails the step before the original is opened for writing.

### Execution policy

The script reads `Get-ExecutionPolicy -List` in a child `powershell.exe` (and `pwsh.exe`, if installed) started with `-NoProfile -NonInteractive -EncodedCommand`, so the result reflects that edition's own settings, not the running session's.

- MachinePolicy or UserPolicy defined: report "controlled by Group Policy" and mark the step not applicable.
- The effective policy is the first defined value among CurrentUser and LocalMachine, ignoring Process, because the launch command sets Process to Bypass. Undefined everywhere means Restricted.
  - RemoteSigned, Unrestricted, or Bypass: keep it.
  - Restricted: run `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force`.
  - AllSigned: ask for `YES` first.
- PowerShell 7 stores its policy in its own config file, so the same rules run as a separate step through `pwsh.exe`, found on PATH or in `C:\Program Files\PowerShell\7`. That step is not applicable when PowerShell 7 isn't installed.
- The child process that sets the policy runs with `PSExecutionPolicyPreference` cleared, and the step reads the policy again afterwards to confirm it changed.

The documented launch command is `powershell -NoProfile -ExecutionPolicy Bypass -File .\onboard.ps1 -Agent <choice>`. `Bypass` also skips the downloaded-from-the-internet check, so the README doesn't need an `Unblock-File` step.

### Prompts and the YES gate

- **bash:** prompts are read with `read -r answer </dev/tty`, after confirming `/dev/tty` can be opened. When it can't, or `CI` is set, no prompt appears and the step is declined. Each `sudo` command is printed in full, then run with `sudo` only after the answer is exactly `YES`. The script never pipes a password to `sudo`; sudo asks for it on the terminal itself.
- **PowerShell:** the only `YES` confirmation is for AllSigned. Next / Skip / Quit and `YES` answers use `$Host.UI.ReadLine()`, or the console (`CONIN$`) when standard input is redirected, so piped input can't answer them. Prompts are off, and confirmations count as declined, under `-NonInteractive`, when `[Environment]::UserInteractive` is false, or when `CI` is set. The script has no code path that calls `Start-Process -Verb RunAs`.

### Git Bash resolution

The script starts from the `git.exe` on the rebuilt PATH:
- `...\cmd\git.exe` maps to `..\bin\bash.exe`.
- `...\mingw64\bin\git.exe` maps to `..\..\bin\bash.exe`.
- `...\bin\git.exe` maps to `bash.exe` in the same folder.

If that doesn't exist, it tries `C:\Program Files\Git\bin\bash.exe`, then `%LOCALAPPDATA%\Programs\Git\bin\bash.exe`. Any candidate under `System32` or `WindowsApps` is rejected.

### No auto-launch, no secrets

The only `claude` and `codex` commands the scripts run are `--version`. Neither script takes a token parameter or reads a key variable, and neither writes anywhere except the user PATH, shell startup files, backups, and the files the package managers install.

### Publishing

- The repository is public: `realanilkapur/dev-onboarding-openspec`.
- `ci.yml` runs on pushes to `main`, pull requests, and when called by the release workflow:
  - Pester tests on Windows PowerShell 5.1 (`windows-latest`), and the bash tests with `/bin/bash` on `ubuntu-latest` and `macos-latest` (bash 3.2).
  - A preview run of each script, and a usage-error check.
  - shellcheck, and the guide command check.
  - gitleaks, a pinned release binary checked against its published checksum, over every commit and over the checked-out files.
- `release.yml` runs on tags matching `v*`. It calls `ci.yml`, and only if that passes, writes `SHA256SUMS` with `sha256sum onboard.ps1 onboard.sh` and creates the release with the three files.
- The stable address is `https://github.com/realanilkapur/dev-onboarding-openspec/releases/latest/download/<file>`.
- The README shows how to verify the download:
  - Windows: the hash from `Get-FileHash` compared with the `onboard.ps1` line of `SHA256SUMS`, printing `OK` or `STOP`.
  - Linux: `grep ' onboard.sh$' SHA256SUMS | sha256sum -c -`.
  - macOS: `grep ' onboard.sh$' SHA256SUMS | shasum -a 256 -c -`.

The GitHub command-line tool on the development machine is signed in as a different account. Repository creation and pushes use the `realanilkapur` credential already stored in Git Credential Manager, passed to the tool only for the commands that need it, without changing its signed-in account or the global Git config.

### Guide page

The page is one file, `docs/index.html`, with inline CSS and JavaScript and no build step. GitHub Pages serves `docs/` from the default branch at `https://realanilkapur.github.io/dev-onboarding-openspec/`.

- A Content Security Policy meta tag (`default-src 'none'`, with the inline script and style allowed by their SHA-256 hashes) blocks every request to other sites.
- The platform (Windows, macOS, or Linux) is preselected from `navigator.userAgentData`, `navigator.platform`, or `navigator.userAgent`. macOS and Linux share the download, preview, and run commands, but the verify command differs.
- Without JavaScript, every step shows as a section on one page, with commands for the `both` agent choice.
- Each command has an ID naming its platform and step (`data-cmd` on the page, a `<!-- cmd: id -->` marker in the README). The page shows the agent inside the command as `both` and replaces it with the visitor's choice. `tests/check-guide-commands.ps1` extracts the commands from both files and fails when any differ, when a command has no copy button, when the page loads anything, or when the CSP hashes don't match the inline code. `-UpdateCsp` rewrites the hashes after an edit.

### Pre-push content check

A local `pre-push` hook in `.git/hooks/` is installed by hand on each machine that publishes, and is never committed. It blocks a push when any outgoing commit's files, commit message, or tag message contain a term from a private denylist stored outside the repository, and it also blocks when the denylist is missing or a scan fails. Text is lowercased before matching because the GNU grep 3.0 in Git for Windows aborts on `-i` with `-F -f`. The hook and denylist stay out of the repository on purpose: a committed denylist would itself publish the terms. This complements the gitleaks key scan in CI.

### Tests

- PowerShell uses Pester 5, installed for the current user (`Install-Module Pester -Scope CurrentUser`) on development machines and in CI.
- bash uses plain test scripts with no framework, so `onboard.sh` stays dependency-free.
- Tests use temp folders as `HOME` and for backups, mocked registry reads and writes, and stubbed package-manager, `sudo`, `curl`, and `gpg` commands that record their calls.
- No test calls winget, brew, apt-get, dnf, pacman, npm, sudo, or `Set-ExecutionPolicy`.

## Risks / Trade-offs

- [Linux apt and dnf installs need several sudo commands] → Each command has its own `YES`. A preview lists them all first, so the developer can decide before a real run.
- [Anthropic changes its repository layout or key] → The script fails on a fingerprint mismatch instead of trusting a new key. Updating the pinned values is a release.
- [winget `OpenAI.Codex` trails OpenAI's releases] → The README says so and shows `winget upgrade OpenAI.Codex`. OpenAI's own script isn't run, by design.
- [The Homebrew `codex` cask may not install on Linux] → It falls back to npm, then stops with OpenAI's command.
- [User PATH changes apply only to new processes] → The summary says to open a new terminal, and verification uses a rebuilt PATH instead of the current window.
- [Interactive shell startup files can print output or prompt during verification] → Standard input is `/dev/null`, standard error is discarded, PATH is read only between markers, and for `--version` only the exit status counts. There is no timeout: bash 3.2 has no portable one, and running the shell in the background to time it can stop it with SIGTTOU. A startup file that waits for input reads end-of-file instead.
- [The guide page drifts from the README] → The CI command comparison fails the build.
- [Developers skip checksum verification on the guide page] → The page notes that the download wasn't checked, on every later step.
- [The repository is public, planning documents included] → Publishing waits for review, the gitleaks scan, and the private pre-push content check.

## Migration Plan

There's no earlier onboarding flow to replace. Each release is a new tag. To roll back on a machine:
- Restore a file from the backup path printed in the summary.
- Remove the PATH entry or startup-file line the summary lists.
- Uninstall a tool with the same package manager that installed it.

The scripts never uninstall anything themselves.

## Open Questions

None. The Anthropic apt and dnf repository details were copied from Anthropic's setup page and are listed under Package commands.
