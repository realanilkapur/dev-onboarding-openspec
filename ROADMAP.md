# Roadmap

Planned work for the onboarding scripts. Each item becomes an OpenSpec change under `openspec/changes/` when work on it starts.

## Now

- **Cross-platform developer onboarding** (`cross-platform-dev-onboarding`): single-file scripts for Windows, macOS, and Linux that set up Git and the developer's choice of Claude Code, OpenAI Codex, or both, with a guided step-by-step run, a guide page, a preview run, `.bak` backups, and published checksums.

## Later

- Minimum-version checks, and optional upgrades of tools that are already installed.
- Alpine (`apk`) support, and Claude Code on Arch-based (`pacman`) systems.
- Support for other coding agents.
- A signed installer or Microsoft Store package, only if developers ask for one.
