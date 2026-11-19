# dev-onboarding-openspec

Set up a developer machine for AI-assisted coding: Git, plus Claude Code, OpenAI Codex, or both, on Windows, macOS, or Linux.

**Step-by-step guide:** [realanilkapur.github.io/dev-onboarding-openspec](https://realanilkapur.github.io/dev-onboarding-openspec/) walks through the same commands as this README, one step at a time.

Each script:

- finds what is already installed, including tools that are installed but not on `PATH`, and installs only what is missing;
- shows its plan first, then stops before each step that changes something so you can press Enter to run it, `S` to skip it, or `Q` to stop;
- backs up every file it changes before changing it, and never overwrites an earlier backup;
- never reads or stores API keys, never starts `claude` or `codex`, and never pipes a download into a shell.

## Windows

Open PowerShell in an empty folder.

1. Download the script and its checksum file:

<!-- cmd: windows-download -->
```powershell
Invoke-WebRequest -UseBasicParsing https://github.com/realanilkapur/dev-onboarding-openspec/releases/latest/download/onboard.ps1 -OutFile onboard.ps1
Invoke-WebRequest -UseBasicParsing https://github.com/realanilkapur/dev-onboarding-openspec/releases/latest/download/SHA256SUMS -OutFile SHA256SUMS
```

2. Check the download. You should see `OK: checksum matches`:

<!-- cmd: windows-verify -->
```powershell
$expected = ((Get-Content SHA256SUMS) -match 'onboard\.ps1$' -split '\s+')[0]
if ((Get-FileHash onboard.ps1 -Algorithm SHA256).Hash -eq $expected) { 'OK: checksum matches' } else { 'STOP: checksum does not match' }
```

3. Preview what would change. This changes nothing:

<!-- cmd: windows-preview -->
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\onboard.ps1 -Agent both -WhatIf
```

4. Run it:

<!-- cmd: windows-run -->
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\onboard.ps1 -Agent both
```

On Windows the script installs with winget for your user account only. It never asks for administrator rights and never changes the machine-wide `PATH`. If winget has no per-user installer for a tool, the script prints the all-users command for you to run yourself in an administrator window.

## macOS and Linux

Open a terminal in an empty folder.

1. Download the script and its checksum file:

<!-- cmd: unix-download -->
```sh
curl -fsSLO https://github.com/realanilkapur/dev-onboarding-openspec/releases/latest/download/onboard.sh
curl -fsSLO https://github.com/realanilkapur/dev-onboarding-openspec/releases/latest/download/SHA256SUMS
```

2. Check the download. You should see `onboard.sh: OK`.

   On macOS:

<!-- cmd: macos-verify -->
```sh
grep ' onboard.sh$' SHA256SUMS | shasum -a 256 -c -
```

   On Linux:

<!-- cmd: linux-verify -->
```sh
grep ' onboard.sh$' SHA256SUMS | sha256sum -c -
```

3. Preview what would change. This changes nothing:

<!-- cmd: unix-preview -->
```sh
bash onboard.sh --agent both --dry-run
```

4. Run it:

<!-- cmd: unix-run -->
```sh
bash onboard.sh --agent both
```

On macOS the script uses Homebrew. If Homebrew is missing it tells you to install it from [brew.sh](https://brew.sh) and stops. On Linux it uses apt or dnf; every `sudo` command is shown first and runs only after you type `YES`. Claude Code comes from Anthropic's signed package repository, and the script checks the signing key's fingerprint before adding it.

## Choose your agent

Replace `both` in the commands above:

| Choice | Windows | macOS and Linux |
| --- | --- | --- |
| Claude Code | `-Agent claude` | `--agent claude` |
| OpenAI Codex | `-Agent codex` | `--agent codex` |
| Both | `-Agent both` | `--agent both` |

## Sign in

Open a new terminal window so it picks up the updated `PATH`, then run the agent you installed. Each one asks you to sign in the first time.

<!-- cmd: signin-claude -->
```sh
claude
```

<!-- cmd: signin-codex -->
```sh
codex
```

## Options

| Windows | macOS and Linux | What it does |
| --- | --- | --- |
| `-WhatIf` | `--dry-run` | Preview only: shows what is installed and what would change, and changes nothing. |
| `-NoGuide` | `--no-guide` | Runs every step without stopping for Enter / S / Q. On Linux, each `sudo` command still needs `YES`. |

The script also runs every step without stopping when there is no terminal to ask on, for example in CI.

Exit codes: `0` when every step succeeded, was already done, or was skipped; `1` when a step failed or a confirmation was declined; `2` for a usage error such as a missing agent choice. Running the same command again offers anything you skipped.

## What the scripts change

| Change | Windows | macOS | Linux |
| --- | --- | --- | --- |
| Install Git, Claude Code, Codex | winget, per user | Homebrew | apt or dnf (Codex: Homebrew or npm) |
| Add a tool's folder to `PATH` | user `PATH`, old value saved to `%LOCALAPPDATA%\onboard\user-path.txt.bak` | `~/.zshrc` or `~/.bash_profile`, backed up first | `~/.zshrc` or `~/.bashrc`, backed up first |
| PowerShell execution policy | sets `CurrentUser` to `RemoteSigned` only if scripts cannot run; asks for `YES` before replacing `AllSigned`; leaves Group Policy alone | not changed | not changed |

Backups are named `<file>.bak`, or `<file>.<timestamp>.bak` if a backup already exists.

## Development

- `scripts/onboard.ps1`: Windows PowerShell 5.1 and PowerShell 7.
- `scripts/onboard.sh`: bash 3.2 or later.
- `docs/index.html`: the guide page, published with GitHub Pages.
- `openspec/`: the plan and specs for this project.

Run the tests:

```powershell
Invoke-Pester tests/powershell        # Pester 5
bash tests/bash/test_onboard.sh
pwsh tests/check-guide-commands.ps1   # guide page commands match this README
```

The tests stub out every installer, so they change nothing on the machine that runs them.

## License

[MIT](LICENSE)
