# Spec Delta

## Purpose

Preserve any existing file in the user's home directory by copying it to a backup that never overwrites an earlier backup, before onboarding modifies that file.

## ADDED Requirements

### Requirement: Existing home files are backed up before modification
Before the flow modifies an existing file in the user's home directory, including `~/.gitconfig`, `~/.zshrc`, `~/.bashrc`, `~/.bash_profile`, and `~/.claude/settings.json`, it MUST write a complete backup. It MUST NOT modify the original until the backup is written, or at all if the backup fails.

#### Scenario: Shell startup file is modified
- **WHEN** the flow is about to modify an existing `~/.zshrc`, `~/.bashrc`, or `~/.bash_profile`
- **THEN** it writes a complete backup of that file first

#### Scenario: Guarded config is modified
- **WHEN** any step is about to modify an existing `~/.gitconfig` or `~/.claude/settings.json`
- **THEN** it writes a complete backup of that file first

#### Scenario: Backup fails
- **WHEN** writing the backup fails
- **THEN** the original file is unchanged
- **AND** the step that needed the change is marked failed

### Requirement: A missing file is not backed up
The flow MUST NOT create a backup for a home file that does not exist yet.

#### Scenario: File is absent
- **WHEN** the flow is about to write a home file that does not exist
- **THEN** it creates no backup file for it

### Requirement: Backups never overwrite an earlier backup
The backup MUST be `<file>.bak`. If that exists, it MUST be `<file>.<yyyyMMddHHmmss>.bak`. If that also exists, it MUST be `<file>.<yyyyMMddHHmmss>-<n>.bak` with the lowest free `n` starting at 1. Writing a backup MUST NOT overwrite any existing file.

#### Scenario: First backup
- **WHEN** the flow backs up `~/.zshrc` and `~/.zshrc.bak` does not exist
- **THEN** it writes `~/.zshrc.bak`

#### Scenario: A .bak already exists
- **WHEN** the flow backs up `~/.zshrc` and `~/.zshrc.bak` exists
- **THEN** it writes `~/.zshrc.<yyyyMMddHHmmss>.bak`
- **AND** `~/.zshrc.bak` is unchanged

#### Scenario: Timestamped name is also taken
- **WHEN** `~/.zshrc.bak` and `~/.zshrc.<yyyyMMddHHmmss>.bak` both exist for the current second
- **THEN** it writes `~/.zshrc.<yyyyMMddHHmmss>-1.bak`
- **AND** both existing backups are unchanged

### Requirement: Backups are no more readable than the original
On macOS and Linux the backup MUST have the same permission mode as the original. On Windows the backup MUST NOT be readable by any account that cannot read the original.

#### Scenario: Private original on macOS or Linux
- **WHEN** the original file has mode `600`
- **THEN** its backup has mode `600`

#### Scenario: Original on Windows
- **WHEN** the flow backs up a file on Windows
- **THEN** every account that can read the backup can also read the original

### Requirement: A symlinked file is backed up by content and stays a link
When the file to modify is a symbolic link, the backup MUST be a regular file holding the link target's contents, and the change MUST be written through the link so it stays a link.

#### Scenario: Shell startup file is a symlink
- **WHEN** `~/.zshrc` is a symbolic link managed by a dotfiles tool and the flow modifies it
- **THEN** the backup is a regular file with the target's previous contents
- **AND** `~/.zshrc` is still a symbolic link to the same target
