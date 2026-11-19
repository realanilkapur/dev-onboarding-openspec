# Spec Delta

## Purpose

Give developers a web page that walks them through installing with the onboarding scripts one step at a time, with Next, Back, and Skip, showing the exact commands without downloading or running anything itself.

## ADDED Requirements

### Requirement: The guide walks through the install process in order
The guide page MUST present these steps one at a time with the current step number and total: choose platform and agent, download the script, verify its checksum, preview the run, run it, and open a new terminal to sign in. Every step after the first MUST offer Back, and every step except the last MUST offer Next.

#### Scenario: Moving forward
- **WHEN** a visitor presses Next on the download step
- **THEN** the page shows the verify step as step 3 of 6

#### Scenario: Going back
- **WHEN** a visitor presses Back on the run step
- **THEN** the page shows the preview step with the same platform and agent choice

### Requirement: Only optional steps can be skipped
The verify and preview steps MUST offer Skip, which moves to the next step. The choose, download, and run steps MUST NOT offer Skip. After verification is skipped, the page MUST note that the download was not checked.

#### Scenario: Skipping the preview
- **WHEN** a visitor presses Skip on the preview step
- **THEN** the page shows the run step

#### Scenario: Skipping verification
- **WHEN** a visitor presses Skip on the verify step
- **THEN** the page notes that the download was not checked
- **AND** shows the preview step

#### Scenario: Required step
- **WHEN** a visitor is on the download step
- **THEN** no Skip control is shown

### Requirement: The visitor chooses the platform and agent
The first step MUST preselect Windows, macOS, or Linux from the browser and let the visitor change it, and MUST require choosing Claude Code, Codex, or both before Next is available. Every later command MUST use that platform and agent choice.

#### Scenario: No agent chosen
- **WHEN** the visitor has not chosen an agent
- **THEN** Next is unavailable on the first step

#### Scenario: macOS visitor
- **WHEN** a visitor on a Mac reaches the verify step
- **THEN** the page shows the `shasum -a 256` command, not the Linux `sha256sum` command

#### Scenario: Windows with both agents
- **WHEN** the visitor chooses Windows and both agents
- **THEN** the run step shows the PowerShell launch command with `-Agent both`
- **AND** the preview step shows the same command with `-WhatIf`

### Requirement: The guide's commands match the README
Every command on the guide page MUST be identical to the README command for the same platform, step, and agent choice, and each MUST have a copy button. CI MUST fail when they differ.

#### Scenario: Commands compared
- **WHEN** CI compares the guide page's commands with the README's
- **THEN** the check passes only when they are identical

### Requirement: The guide only shows commands
The guide page MUST NOT download or run anything, load anything from other sites, set cookies, or collect analytics. Without JavaScript it MUST show every step and its commands on one page.

#### Scenario: Page loads
- **WHEN** the page loads
- **THEN** it makes no requests to other sites and sets no cookies

#### Scenario: JavaScript is off
- **WHEN** the page is opened with JavaScript disabled
- **THEN** every step and its commands are visible on one page

### Requirement: The guide is published with the repository
The guide MUST be published from the repository with GitHub Pages at a public address that needs no sign-in, and the README MUST link to it.

#### Scenario: Visitor is signed out
- **WHEN** a visitor who is not signed in to GitHub opens the guide address
- **THEN** the page loads
