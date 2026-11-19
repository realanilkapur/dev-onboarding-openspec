# Spec Delta

## Purpose

Define how one onboarding run behaves as a whole: how the developer chooses agents and previews a run, what a failed step blocks, how privileged commands are approved, what a second run does, how secrets are kept out, and what the run reports when it ends.

## ADDED Requirements

### Requirement: The developer chooses which coding agents to set up
The run MUST require a choice of Claude Code, Codex, or both, given as `-Agent claude|codex|both` on Windows or `--agent claude|codex|both` on macOS and Linux. Without a valid choice the run MUST stop before any step runs, print usage help listing the accepted values, and exit non-zero. Steps for an agent not chosen MUST be marked not applicable.

#### Scenario: No choice given
- **WHEN** onboarding starts without an agent choice
- **THEN** no step runs and nothing is installed
- **AND** the run prints the accepted values and exits non-zero

#### Scenario: Invalid choice
- **WHEN** onboarding starts with an agent value other than `claude`, `codex`, or `both`
- **THEN** no step runs
- **AND** the run prints the accepted values and exits non-zero

#### Scenario: Only Claude Code is chosen
- **WHEN** the developer chooses `claude`
- **THEN** the Codex steps are marked not applicable
- **AND** Codex is not installed and no Codex folder is added to PATH

#### Scenario: Only Codex is chosen
- **WHEN** the developer chooses `codex`
- **THEN** the Claude Code and Git Bash steps are marked not applicable
- **AND** Claude Code is not installed and no Claude Code folder is added to PATH

#### Scenario: Both are chosen
- **WHEN** the developer chooses `both`
- **THEN** the Claude Code and Codex steps both run

#### Scenario: A later run adds the other agent
- **WHEN** a run with `claude` succeeded and the developer later runs with `both`
- **THEN** only the Codex steps install or change anything

### Requirement: A preview run shows the plan without changing anything
When started with `-WhatIf` on Windows or `--dry-run` on macOS and Linux, the run MUST report what it found and every action a real run would take, including each sudo command and each file it would back up or modify. It MUST NOT install anything, change any file, PATH, or execution policy, ask for confirmation, or pause for Next or Skip.

#### Scenario: Tool installed but not on PATH
- **WHEN** a preview runs with Claude Code chosen, and `%USERPROFILE%\.local\bin\claude.exe` exists but its folder is not on PATH
- **THEN** the preview reports Claude Code as found at that path and that it would add the folder to the user PATH
- **AND** the user PATH is unchanged

#### Scenario: Linux run that needs sudo
- **WHEN** a preview runs on an apt host where Git and Claude Code are missing
- **THEN** it lists each sudo command a real run would ask about
- **AND** no command runs and no prompt appears

#### Scenario: Nothing to do
- **WHEN** a preview runs on a machine where Git and every chosen agent are runnable in a new terminal
- **THEN** it reports that a real run would change nothing

### Requirement: Every change is shown before it is made
Before each install command, PATH change, shell startup file change, or execution policy change, the run MUST print the exact command or change it is about to make.

#### Scenario: Installing Codex on Windows
- **WHEN** a real run is about to install Codex with winget
- **THEN** it first prints the full winget command it will run

#### Scenario: Appending to a shell startup file
- **WHEN** a real run is about to append a PATH line to `~/.zshrc`
- **THEN** it first prints the file name and the exact line

### Requirement: A guided run pauses before each step that changes something
When a terminal is available and neither a preview nor `-NoGuide`/`--no-guide` was given, the run MUST list its planned steps, then before each step that would change something show its number and total, purpose, what it found, and the exact changes, and wait for Next, Skip, or Quit. Steps already satisfied or not applicable MUST be reported without pausing.

#### Scenario: Next
- **WHEN** the developer presses Enter at the Claude Code step on an apt host
- **THEN** the step runs
- **AND** each sudo command inside it still needs its own typed `YES`

#### Scenario: Skip
- **WHEN** the developer types `s` at the Codex step
- **THEN** Codex is not installed
- **AND** the Codex step and the Codex PATH step are marked skipped

#### Scenario: Quit
- **WHEN** the developer types `q` at a step
- **THEN** no later step runs and the remaining steps are marked skipped
- **AND** the run ends with its summary

#### Scenario: Step already satisfied
- **WHEN** Git is already runnable in a new terminal
- **THEN** the Git step is reported as already satisfied without a pause

#### Scenario: Unrecognized answer
- **WHEN** the developer types anything other than Enter, `s`, or `q` at a step
- **THEN** the options are shown again and nothing runs

#### Scenario: Running straight through
- **WHEN** the run is started with `-NoGuide` or `--no-guide`
- **THEN** no step pauses for Next or Skip
- **AND** each sudo command still needs its own typed `YES`

#### Scenario: No terminal
- **WHEN** no terminal is available or `CI` is set
- **THEN** no step pauses for Next or Skip

### Requirement: A failed or skipped step blocks only the steps that depend on it
Each step MUST end as done, already satisfied, not applicable, skipped, declined, or failed. A skipped, declined, or failed step MUST NOT stop steps that do not depend on it, and steps that depend on a skipped step MUST be marked skipped. Host detection failure MUST stop the run. The run MUST exit non-zero when any step was declined or failed, and MUST NOT exit non-zero only because steps were skipped.

#### Scenario: Developer skips Git
- **WHEN** the developer chose both agents and skips the Git step on Windows
- **THEN** the Git PATH and Git Bash steps are marked skipped and the Claude Code step still runs
- **AND** the run exits 0 when no step was declined or failed

#### Scenario: Host detection fails
- **WHEN** host detection stops the run
- **THEN** no other step runs
- **AND** the run exits non-zero

#### Scenario: Git Bash is not found
- **WHEN** the developer chose both agents and the Git Bash step fails on Windows
- **THEN** the Claude Code and Codex steps still run
- **AND** the run exits non-zero

#### Scenario: A tool install fails
- **WHEN** the developer chose both agents and the Claude Code install fails
- **THEN** no PATH entry is added for Claude Code
- **AND** the Codex step still runs

#### Scenario: Everything succeeds
- **WHEN** every step ends as done, already satisfied, or not applicable
- **THEN** the run exits 0

### Requirement: The run ends with a summary
The run MUST end by printing each step's outcome, every backup file written, every PATH entry added and where it was added, the Git Bash path when it was resolved, and what the user should do next. When PATH changed, it MUST tell the user to open a new terminal. When steps were skipped or declined, it MUST say that rerunning the same command offers them again.

#### Scenario: PATH changed
- **WHEN** the run added a folder to PATH
- **THEN** the summary lists that folder and where it was added
- **AND** it tells the user to open a new terminal

#### Scenario: A backup was written
- **WHEN** the run wrote a backup file
- **THEN** the summary lists the full path of that backup

#### Scenario: A step was skipped
- **WHEN** the developer skipped a step
- **THEN** the summary lists it as skipped
- **AND** says that rerunning the same command offers it again

### Requirement: Onboarding never launches the installed tools
The run MUST NOT start `claude` or `codex` except to check `--version`. It MUST tell the user to run each chosen agent in a new terminal, where they sign in themselves.

#### Scenario: Run finishes with the chosen agents available
- **WHEN** the run finishes and every chosen agent is runnable
- **THEN** no interactive `claude` or `codex` session was started by the run
- **AND** the summary tells the user to run each chosen agent in a new terminal

#### Scenario: Run started with piped input
- **WHEN** the entry point is started with its standard input piped
- **THEN** the run does not start an interactive tool
- **AND** it ends with its summary

### Requirement: Each privileged command needs a typed YES
Before each command that runs with sudo, the flow MUST show the exact command and run it only after the user types `YES`. Any other answer MUST leave that command unrun and mark its step declined. The flow MUST NOT supply a password or approve an elevation prompt itself.

#### Scenario: User approves
- **WHEN** the flow shows a sudo command and the user types `YES`
- **THEN** the flow runs that one command
- **AND** the next sudo command is confirmed separately

#### Scenario: User declines
- **WHEN** the flow shows a sudo command and the user types anything other than `YES`
- **THEN** that command does not run
- **AND** its step is marked declined and steps that do not depend on it still run

#### Scenario: A package manager asks for a password itself
- **WHEN** a package manager prompts for a password during an install
- **THEN** the flow does not supply the password

### Requirement: Windows onboarding never elevates
On Windows the flow MUST NOT start an elevated process. A step that would need administrator rights MUST be marked failed and MUST print the command the user can run themselves.

#### Scenario: A step needs administrator rights
- **WHEN** a Windows step can only complete with administrator rights
- **THEN** that step is marked failed
- **AND** the flow prints the command and does not trigger an elevation prompt

### Requirement: Prompts are read from the terminal, never from piped input
The flow MUST read every confirmation and every Next, Skip, or Quit answer from the controlling terminal, not from standard input. When no terminal is available, when `CI` is set, or when PowerShell runs non-interactively, the flow MUST NOT prompt and MUST treat each confirmation as declined.

#### Scenario: Input is piped but a terminal is attached
- **WHEN** standard input is piped and contains `YES`, and a terminal is attached
- **THEN** the flow reads the answer from the terminal
- **AND** the piped `YES` does not approve anything

#### Scenario: No terminal is available
- **WHEN** a confirmation is needed and no terminal is available or `CI` is set
- **THEN** the flow does not prompt
- **AND** the step is marked declined and no sudo command runs

### Requirement: A second run changes nothing that is already set up
Running onboarding again with the same agent choice after a successful run MUST NOT install any tool, add any PATH entry or shell startup line, write any backup, or change any execution policy.

#### Scenario: Re-run in the same terminal
- **WHEN** onboarding runs a second time in the terminal that ran the first, before that terminal reloads PATH
- **THEN** no tool is installed
- **AND** no PATH entry, shell startup line, backup, or execution policy change is made

### Requirement: Secrets never pass through onboarding
The flow MUST NOT read API keys or tokens from its arguments or environment variables, MUST NOT print them, and MUST NOT create or modify any file in the folder it was started from or the folder that holds the script.

#### Scenario: Run from inside a Git repository
- **WHEN** a run is started from inside a Git repository and finishes
- **THEN** `git status --porcelain` in that repository prints the same output as before the run

#### Scenario: No secret inputs
- **WHEN** the entry points' parameters are listed
- **THEN** none of them accepts an API key or token

### Requirement: The Windows entry point starts under any local execution policy
The documented Windows launch command MUST start onboarding when the effective execution policy is Restricted or AllSigned, or when the script was downloaded from the internet, without administrator rights and without changing a saved policy.

#### Scenario: Policy is Restricted
- **WHEN** the effective policy is Restricted and the user runs the documented launch command
- **THEN** onboarding starts
- **AND** no saved execution policy changed before the execution-policy step runs

#### Scenario: Script was downloaded from the internet
- **WHEN** `onboard.ps1` was downloaded with a browser or `Invoke-WebRequest` and the user runs the documented launch command
- **THEN** onboarding starts
