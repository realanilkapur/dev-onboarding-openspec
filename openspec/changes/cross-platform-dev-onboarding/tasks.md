## 1. Script skeletons and test harness

- [x] 1.1 Create `scripts/onboard.ps1` with `[CmdletBinding(SupportsShouldProcess)]` for `-WhatIf`, a string `-Agent` parameter, a `-NoGuide` switch, and a main routine that runs only when the file isn't dot-sourced
- [x] 1.2 Create `scripts/onboard.sh` for bash 3.2 with `--agent`, `--dry-run`, `--no-guide`, and `--help`, and a main routine guarded by `[[ "${BASH_SOURCE[0]}" == "$0" ]]`
- [x] 1.3 Add the step runner to both scripts: the six outcomes, the dependency table from design.md, and exit codes 0, 1, and 2
- [x] 1.4 Split each step into a read-only detect function and an apply function; the runner prints each step's changes before applying them and never calls apply in a preview, and apply code prints each command as it runs (`Invoke-OnboardChange`, `run_cmd`, `run_sudo`)
- [x] 1.5 Set up Pester 5 under `tests/powershell/` and plain bash tests under `tests/bash/`, with temp folders, mocked registry access, and stubbed package-manager commands
- [x] 1.6 Test argument handling: missing, invalid, and each valid agent choice; usage text; exit code 2 with no step run
- [x] 1.7 Test that a preview changes no file, PATH, policy, or package, and prompts for nothing

## 2. Backups (config-backup)

- [x] 2.1 Implement backup naming (`.bak`, then a timestamp, then `-<n>`) and a never-overwrite copy in both scripts
- [x] 2.2 Keep permissions (`cp -pL`), back up symbolic links by content, save the Windows user PATH to `%LOCALAPPDATA%\onboard` with `CreateNew`, and fail the step before writing when the backup fails
- [x] 2.3 Test: first backup, earlier backup kept, two backups in the same second, missing file not backed up, permissions kept, symbolic link stays a link after the append

## 3. Platform detection (platform-detection)

- [x] 3.1 Implement host detection in both scripts, including WSL reported as Linux and Git Bash, MSYS2, and Cygwin redirected to the PowerShell command
- [x] 3.2 Implement package-manager detection: winget, Homebrew (PATH, `/opt/homebrew/bin/brew`, `/usr/local/bin/brew`), and apt, then dnf, then pacman
- [ ] 3.3 Test each `uname -s` value, the WSL markers, Homebrew present but not on PATH, and each missing-package-manager failure

## 4. Run behavior (onboarding-run)

- [x] 4.1 Read prompts from `/dev/tty` in bash and `$Host.UI.ReadLine()` (or `CONIN$` when input is redirected) in PowerShell; decline without prompting when there's no terminal, `CI` is set, or PowerShell is non-interactive
- [x] 4.2 Implement the `YES` gate for each sudo command, showing the full command and never supplying a password
- [x] 4.3 Implement the summary: each step's outcome, backups, PATH entries and where they went, the Git Bash path, the new-terminal notice, and next steps for each chosen agent
- [x] 4.4 Test: piped `YES` with a terminal attached doesn't approve, no terminal declines, a decline doesn't stop independent steps, and the summary content
- [x] 4.5 Test a second run with the same agent choice: no install, PATH, startup-file, backup, or policy change
- [ ] 4.6 Test that no step starts `claude` or `codex` except with `--version`, that no `Start-Process -Verb RunAs` appears in `onboard.ps1`, and that `git status --porcelain` is unchanged in the start folder
- [x] 4.7 Add guided mode to both scripts: the opening plan, the step screen (number, purpose, found, changes), Next/Skip/Quit read from the terminal, and already-satisfied or not-applicable steps reported without pausing
- [x] 4.8 Add `-NoGuide` / `--no-guide`, and turn guided mode off for previews and when no terminal is available
- [x] 4.9 Add the skipped outcome: steps that depend on a skipped step are skipped, the summary lists them with the rerun note, and skips don't change the exit code
- [x] 4.10 Test: Next runs the step and still asks YES per sudo command, Skip and Quit outcomes and exit codes, unrecognized answers, `--no-guide`, no terminal, and previews without pauses

## 5. Execution policy (powershell-execution-policy)

- [x] 5.1 Implement the policy step: Group Policy reported, effective policy ignoring Process, Restricted or Undefined set to CurrentUser RemoteSigned, AllSigned only after `YES`
- [x] 5.2 Apply the same rules to PowerShell 7 as a separate step through `pwsh.exe` (on PATH or in its default folder), marked not applicable when it isn't installed
- [x] 5.3 Test each policy value, Group Policy, a failed `Set-ExecutionPolicy`, and `pwsh` present and absent, using a fake policy command
- [ ] 5.4 Check on a Windows machine that the documented launch command starts under Restricted and AllSigned, and with a downloaded copy of the script

## 6. PATH discovery and changes (developer-path)

- [x] 6.1 Implement known-location discovery for Git, Claude Code, and Codex, using the table in design.md
- [x] 6.2 Implement the Windows user PATH append: raw read, `REG_EXPAND_SZ` write, duplicate check against machine and user PATH, and the settings-change broadcast
- [x] 6.3 Implement the startup-file append: choose the file by shell and host, skip it if the folder is already mentioned, back it up first, and print the line for other shells
- [x] 6.4 Implement new-terminal verification: rebuilt PATH, plus a Git Bash login shell when Git Bash was found, on Windows; `$SHELL -l -i -c` on macOS; `$SHELL -i -c` on Linux; with standard input from `/dev/null` and no timeout (see design.md)
- [x] 6.5 Test: `%VAR%` entries survive, a duplicate isn't added, the machine PATH is untouched, the right startup file is chosen for each shell and host, and an unknown shell prints the line

## 7. Git and Git Bash (git-environment)

- [x] 7.1 Implement the Git step: find, else install with the host's package manager (winget per-user only, failing with the machine-scope command when no per-user installer applies)
- [x] 7.2 Implement Git Bash resolution from the `git.exe` location, with the fallbacks and the System32/WindowsApps rejection, and run it only when Claude Code is chosen
- [x] 7.3 Print the `CLAUDE_CODE_GIT_BASH_PATH` suggestion without setting it, and never touch `~/.gitconfig`
- [x] 7.4 Test each `git.exe` layout, the fallbacks, rejection, Codex-only runs skipping Git Bash, and `~/.gitconfig` unchanged

## 8. Claude Code (claude-code-environment)

- [x] 8.1 Implement Claude Code install on Windows (winget per-user) and macOS (cask)
- [x] 8.2 Copy Anthropic's apt and dnf repository steps from its setup page, pin them in `onboard.sh`, and verify the key fingerprint before writing any repository file
- [x] 8.3 Fail on pacman and on any missing package with a pointer to Anthropic's docs, without running a downloaded script
- [x] 8.4 Test: already runnable, installed but not on PATH, fingerprint mismatch writes nothing, declined sudo command, repository already set up, pacman stop, `~/.claude/settings.json` unchanged or still absent

## 9. Codex (codex-environment)

- [x] 9.1 Implement Codex install on Windows (winget `OpenAI.Codex` per-user) and macOS (cask)
- [x] 9.2 Implement the Linux order: Homebrew cask, then npm when its global folder is user-writable, then stop and print OpenAI's command without running it
- [x] 9.3 Test: already runnable, installed by OpenAI's installer or npm but not on PATH, each Linux branch, no sudo, no `codex login`, nothing written under `~/.codex`

## 10. Publishing (onboarding-distribution)

- [x] 10.1 Write the README: what the scripts do and don't do, download, verify, and run commands for Windows, macOS, and Linux, each agent choice, preview, and how to undo changes
- [x] 10.2 Build `docs/index.html`: the six-step guide with Next, Back, and Skip on the verify and preview steps, platform preselection, a required agent choice, copy buttons, and an all-steps view without JavaScript
- [x] 10.3 Add a Content Security Policy that blocks requests to other sites, and confirm in a browser that the page makes none and sets no cookies
- [x] 10.4 Mark the commands in the README and the guide page, and add a CI check that fails when they differ
- [x] 10.5 Add a GitHub Actions workflow for pushes and pull requests: Pester on `windows-latest` (Windows PowerShell 5.1), the bash tests with `/bin/bash` on `macos-latest` and `ubuntu-latest`, preview runs, shellcheck, and the guide command check
- [x] 10.6 Add a gitleaks scan (pinned binary, checksum-verified) over every commit and the checked-out files to CI, and make a finding fail the build
- [x] 10.7 Install the local, uncommitted `pre-push` hook with its private denylist on each machine that publishes, and confirm it blocks a test push containing a denylisted term
- [x] 10.8 Add a release workflow for `v*` tags that runs the tests and the scan, writes `SHA256SUMS`, and publishes `onboard.ps1`, `onboard.sh`, and `SHA256SUMS`
- [ ] 10.9 After the specs are reviewed, create the public repository `realanilkapur/dev-onboarding-openspec` with the `realanilkapur` account, and push
- [ ] 10.10 Enable GitHub Pages from `docs/`, link the guide from the README, and walk through every step of the page
- [ ] 10.11 Tag `v0.1.0`, then run the README's commands as written from an empty folder on Windows, macOS, and Linux and confirm the downloads, checksums, and previews work

## 11. End-to-end checks

- [ ] 11.1 On a clean Windows 11 user account, run with `-Agent both` and confirm `git`, `claude`, and `codex` run in a new PowerShell window and in Git Bash
- [ ] 11.2 On Windows 11 with `claude.exe` in `%USERPROFILE%\.local\bin` but not on PATH, confirm the run adds that folder to the user PATH and installs nothing
- [ ] 11.3 On macOS with zsh and with bash as the login shell, run with `--agent both` and confirm all three tools run in a new Terminal window
- [ ] 11.4 On Ubuntu and Fedora, run with `--agent claude` and confirm each sudo command was asked about separately and `claude` runs in a new terminal
- [ ] 11.5 Run every scenario twice on each platform and confirm the second run changes nothing
- [ ] 11.6 On Windows 11, follow the guide page from start to finish in guided mode, skip Codex at its step, and confirm the summary and exit code 0
