# Spec Delta

## Purpose

On Windows, let the current user run local PowerShell scripts after onboarding by setting a current-user policy only when local scripts are blocked, without silently weakening a signed-scripts choice or needing administrator rights.

## ADDED Requirements

### Requirement: Non-Windows hosts skip execution policy
On macOS and Linux the flow MUST NOT change a PowerShell execution policy and MUST mark the step not applicable.

#### Scenario: macOS or Linux
- **WHEN** the host is macOS or Linux
- **THEN** no execution policy changes
- **AND** the step is marked not applicable

### Requirement: An effective policy that allows local scripts is kept
When the effective execution policy, not counting the Process scope set by the launch command, is RemoteSigned, Unrestricted, or Bypass, the flow MUST NOT change any execution policy.

#### Scenario: Machine policy already allows local scripts
- **WHEN** the CurrentUser policy is Undefined and the LocalMachine policy is RemoteSigned
- **THEN** no execution policy changes

#### Scenario: Current user already allows local scripts
- **WHEN** the CurrentUser policy is RemoteSigned
- **THEN** no execution policy changes

### Requirement: A Restricted or Undefined effective policy becomes current-user RemoteSigned
When the effective policy is Restricted or Undefined, the flow MUST set the CurrentUser policy to RemoteSigned without administrator rights and MUST NOT change the LocalMachine policy.

#### Scenario: Local scripts are blocked
- **WHEN** the effective policy is Restricted
- **THEN** the CurrentUser policy becomes RemoteSigned
- **AND** the LocalMachine policy is unchanged and no elevation prompt appears

### Requirement: AllSigned is changed only after the user types YES
When the effective policy is AllSigned, the flow MUST explain that the change would allow unsigned local scripts and set the CurrentUser policy to RemoteSigned only after the user types `YES`. Otherwise it MUST leave the policy unchanged and mark the step declined.

#### Scenario: User keeps AllSigned
- **WHEN** the effective policy is AllSigned and the user does not type `YES`
- **THEN** no execution policy changes
- **AND** the step is marked declined

#### Scenario: User approves the change
- **WHEN** the effective policy is AllSigned and the user types `YES`
- **THEN** the CurrentUser policy becomes RemoteSigned

### Requirement: Group Policy is reported, not overridden
When the MachinePolicy or UserPolicy scope is defined, the flow MUST NOT try to change the execution policy, MUST report that Group Policy controls it, and MUST mark the step not applicable.

#### Scenario: Group Policy sets the policy
- **WHEN** the MachinePolicy scope is defined
- **THEN** the flow does not call any command that changes the execution policy
- **AND** the summary reports that Group Policy controls it

#### Scenario: Change fails for another reason
- **WHEN** setting the CurrentUser policy fails
- **THEN** the step is marked failed
- **AND** the other steps still run

### Requirement: Each installed PowerShell edition is covered
The flow MUST apply these rules to Windows PowerShell 5.1 and, when PowerShell 7 (`pwsh`) is installed, separately to PowerShell 7, because each stores its current-user policy in a different place.

#### Scenario: Both editions are installed
- **WHEN** `pwsh` is installed and both editions block local scripts
- **THEN** the CurrentUser policy becomes RemoteSigned in both editions

#### Scenario: Only Windows PowerShell is installed
- **WHEN** `pwsh` is not installed
- **THEN** the flow applies the rules to Windows PowerShell 5.1 only and reports no error about PowerShell 7
