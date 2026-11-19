<#
.SYNOPSIS
    Sets up Git and Claude Code, OpenAI Codex, or both for the current Windows user.

.DESCRIPTION
    Finds what is already installed, including tools that are installed but not on PATH,
    and installs only what is missing, with winget, for the current user. Before each step
    that changes something it shows what it found and what it will change, and waits for
    Next, Skip, or Quit. It never asks for administrator rights, never changes the
    machine-wide PATH, never reads or stores API keys, and never starts claude or codex.

.PARAMETER Agent
    Which coding agent to set up: claude, codex, or both. Required.

.PARAMETER NoGuide
    Run every step without pausing for Next / Skip / Quit.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\onboard.ps1 -Agent both -WhatIf

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\onboard.ps1 -Agent claude
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Agent,
    [switch]$NoGuide
)

$script:OnboardVersion = '0.1.0'
$script:Lines = New-Object System.Collections.Generic.List[string]
$script:Preview = $false
$script:Guided = $false
$script:ReadAnswer = $null
$script:BackupDir = $null
$script:Backups = New-Object System.Collections.Generic.List[string]
$script:PathAdded = New-Object System.Collections.Generic.List[string]
$script:GitBashPath = $null
$script:Details = @{}

$script:Usage = @'
Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\onboard.ps1 -Agent claude|codex|both [-WhatIf] [-NoGuide]

  -Agent    Which coding agent to set up: claude, codex, or both (required)
  -WhatIf   Preview: show what is installed and what would change, and change nothing
  -NoGuide  Run every step without pausing for Next / Skip / Quit
'@

# ---------------------------------------------------------------------------
# Output and prompts
# ---------------------------------------------------------------------------

function Test-UseColor {
    return (-not $env:NO_COLOR) -and (-not [Console]::IsOutputRedirected)
}

function Write-OnboardLine {
    param([string]$Text = '', [string]$Color)
    $script:Lines.Add($Text)
    if ($Color -and (Test-UseColor)) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
}

function Test-CanPrompt {
    if ($env:CI) { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    foreach ($arg in [Environment]::GetCommandLineArgs()) {
        if ($arg -match '^-noni') { return $false }
    }
    return $true
}

function Test-PromptAvailable {
    if ($script:ReadAnswer) { return $true }
    return (Test-CanPrompt)
}

function Read-TerminalLine {
    if ($script:ReadAnswer) { return (& $script:ReadAnswer) }
    if ([Console]::IsInputRedirected) {
        try {
            $stream = [System.IO.File]::Open('CONIN$', [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($stream)
            try { return $reader.ReadLine() } finally { $reader.Dispose() }
        } catch {
            return $null
        }
    }
    return $Host.UI.ReadLine()
}

function Read-StepAnswer {
    while ($true) {
        Write-OnboardLine '[Enter] Next   [S] Skip   [Q] Quit' 'Cyan'
        $answer = Read-TerminalLine
        if ($null -eq $answer) { return 'quit' }
        $answer = $answer.Trim().ToLowerInvariant()
        if ($answer -eq '') { return 'next' }
        if ($answer -eq 's' -or $answer -eq 'skip') { return 'skip' }
        if ($answer -eq 'q' -or $answer -eq 'quit') { return 'quit' }
        Write-OnboardLine 'Press Enter for Next, or type S to skip or Q to quit.'
    }
}

function Confirm-Yes {
    param([string]$Question)
    if (-not (Test-PromptAvailable)) {
        Write-OnboardLine '  No terminal to ask on, so this counts as No.'
        return $false
    }
    Write-OnboardLine "  $Question" 'Yellow'
    Write-OnboardLine '  Type YES to continue, or anything else to skip:' 'Yellow'
    $answer = Read-TerminalLine
    return ($answer -ceq 'YES')
}

function Invoke-OnboardChange {
    param([string]$Description, [scriptblock]$Action)
    Write-OnboardLine "  Running: $Description"
    & $Action
}

function Invoke-NativeCommand {
    param([string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments 2>&1 | ForEach-Object { Write-OnboardLine ('    ' + $_) }
    return $LASTEXITCODE
}

function ConvertTo-EncodedCommand {
    param([string]$Command)
    return [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Command))
}

# ---------------------------------------------------------------------------
# Arguments and host
# ---------------------------------------------------------------------------

function Resolve-AgentChoice {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $v = $Value.Trim().ToLowerInvariant()
    if (@('claude', 'codex', 'both') -contains $v) { return $v }
    return $null
}

function Get-AgentTools {
    param([string]$Choice)
    if ($Choice -eq 'both') { return @('claude', 'codex') }
    return @($Choice)
}

function Test-IsWindows {
    if (Test-Path variable:IsWindows) { return [bool]$IsWindows }
    return ($env:OS -eq 'Windows_NT')
}

# ---------------------------------------------------------------------------
# PATH
# ---------------------------------------------------------------------------

function Get-UserPathRaw {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if (-not $key) { return '' }
    try {
        $value = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) { return '' }
        return [string]$value
    } finally {
        $key.Close()
    }
}

function Set-UserPathRaw {
    param([string]$Value)
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        $key.SetValue('Path', $Value, [Microsoft.Win32.RegistryValueKind]::ExpandString)
    } finally {
        $key.Close()
    }
    Send-EnvironmentChange
}

function Send-EnvironmentChange {
    if (-not ('Onboard.NativeMethods' -as [type])) {
        Add-Type -Namespace Onboard -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
    }
    $result = [UIntPtr]::Zero
    [void][Onboard.NativeMethods]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
}

function Get-MachinePathExpanded {
    return [Environment]::ExpandEnvironmentVariables([string][Environment]::GetEnvironmentVariable('Path', 'Machine'))
}

function Get-UserPathExpanded {
    return [Environment]::ExpandEnvironmentVariables((Get-UserPathRaw))
}

function Get-NewTerminalPath {
    return (@((Get-MachinePathExpanded), (Get-UserPathExpanded)) -join ';')
}

function ConvertTo-PathKey {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return '' }
    $d = [Environment]::ExpandEnvironmentVariables($Dir.Trim().Trim('"'))
    return $d.TrimEnd('\').ToLowerInvariant()
}

function Test-PathListContains {
    param([string]$PathList, [string]$Dir)
    $key = ConvertTo-PathKey $Dir
    if (-not $key) { return $false }
    foreach ($entry in ($PathList -split ';')) {
        if ((ConvertTo-PathKey $entry) -eq $key) { return $true }
    }
    return $false
}

function ConvertTo-PortablePath {
    param([string]$Dir)
    foreach ($name in 'LOCALAPPDATA', 'APPDATA', 'USERPROFILE') {
        $base = [Environment]::GetEnvironmentVariable($name)
        if (-not $base) { continue }
        $base = $base.TrimEnd('\')
        if ($Dir.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return "%$name%" + $Dir.Substring($base.Length)
        }
    }
    return $Dir
}

function Get-NewUserPathValue {
    param([string]$Raw, [string]$Entry)
    if ([string]::IsNullOrEmpty($Raw)) { return $Entry }
    return $Raw.TrimEnd(';') + ';' + $Entry
}

function Test-ToolInNewTerminal {
    param([string]$Tool)
    $saved = $env:Path
    try {
        $env:Path = Get-NewTerminalPath
        $cmd = Get-Command $Tool -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $cmd) { return $false }
        & $cmd.Source --version 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        if ($script:GitBashPath) {
            & $script:GitBashPath -l -c "$Tool --version" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-OnboardLine "  $Tool runs in PowerShell but not in Git Bash ($script:GitBashPath)."
                return $false
            }
        }
        return $true
    } finally {
        $env:Path = $saved
    }
}

# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------

function Get-BackupPath {
    param([string]$File, [datetime]$Now = (Get-Date))
    $candidate = "$File.bak"
    if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    $stamp = $Now.ToString('yyyyMMddHHmmss')
    $candidate = "$File.$stamp.bak"
    $n = 1
    while (Test-Path -LiteralPath $candidate) {
        $candidate = "$File.$stamp-$n.bak"
        $n++
    }
    return $candidate
}

function Save-UserPathBackup {
    param([string]$Raw)
    $dir = $script:BackupDir
    if (-not $dir) { $dir = Join-Path $env:LOCALAPPDATA 'onboard' }
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force -WhatIf:$false | Out-Null }
    $target = Get-BackupPath (Join-Path $dir 'user-path.txt')
    $stream = [System.IO.File]::Open($target, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    $writer = New-Object System.IO.StreamWriter($stream, (New-Object System.Text.UTF8Encoding($false)))
    try { $writer.Write($Raw) } finally { $writer.Dispose() }
    $script:Backups.Add($target)
    return $target
}

# ---------------------------------------------------------------------------
# Finding tools
# ---------------------------------------------------------------------------

function Get-KnownToolDirs {
    param([string]$Tool)
    $u = $env:USERPROFILE
    $l = $env:LOCALAPPDATA
    $a = $env:APPDATA
    if ($Tool -eq 'git') {
        return @((Join-Path $env:ProgramFiles 'Git\cmd'), "$l\Programs\Git\cmd")
    }
    if ($Tool -eq 'claude') {
        return @("$u\.local\bin", "$l\Microsoft\WinGet\Links")
    }
    if ($Tool -eq 'codex') {
        $dirs = @()
        if ($env:CODEX_INSTALL_DIR) { $dirs += $env:CODEX_INSTALL_DIR }
        $dirs += "$l\Programs\OpenAI\Codex\bin"
        $codexHome = $env:CODEX_HOME
        if (-not $codexHome) { $codexHome = "$u\.codex" }
        $dirs += "$codexHome\packages\standalone\current\bin"
        $dirs += "$a\npm"
        $dirs += "$l\Microsoft\WinGet\Links"
        return $dirs
    }
    return @()
}

function Test-ToolVersion {
    param([string]$File)
    try {
        & $File --version 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Find-Tool {
    param([string]$Tool)
    $dirs = New-Object System.Collections.Generic.List[string]
    foreach ($d in ((@((Get-NewTerminalPath), $env:Path) -join ';') -split ';')) {
        if ($d) { $dirs.Add([Environment]::ExpandEnvironmentVariables($d.Trim().Trim('"'))) }
    }
    foreach ($d in (Get-KnownToolDirs $Tool)) {
        if ($d) { $dirs.Add($d) }
    }
    $seen = @{}
    foreach ($dir in $dirs) {
        $key = ConvertTo-PathKey $dir
        if (-not $key -or $seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if ($key -match '\\windowsapps$') { continue }
        foreach ($ext in '.exe', '.cmd') {
            try { $file = Join-Path $dir ($Tool + $ext) } catch { continue }
            if ((Test-Path -LiteralPath $file -PathType Leaf) -and (Test-ToolVersion $file)) {
                return @{ Path = $file; Dir = $dir.TrimEnd('\') }
            }
        }
    }
    return $null
}

function Resolve-GitBash {
    param([string]$GitExe)
    $candidates = @()
    if ($GitExe) {
        $dir = Split-Path -Parent $GitExe
        $leaf = Split-Path -Leaf $dir
        $parent = Split-Path -Parent $dir
        if ($leaf -ieq 'cmd') {
            $candidates += (Join-Path $parent 'bin\bash.exe')
        } elseif ($leaf -ieq 'bin' -and (Split-Path -Leaf $parent) -match '^(mingw64|mingw32|clangarm64|ucrt64)$') {
            $candidates += (Join-Path (Split-Path -Parent $parent) 'bin\bash.exe')
        } elseif ($leaf -ieq 'bin') {
            $candidates += (Join-Path $dir 'bash.exe')
        }
    }
    if ($env:ProgramFiles) { $candidates += (Join-Path $env:ProgramFiles 'Git\bin\bash.exe') }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe') }
    foreach ($c in $candidates) {
        if ($c -match '\\(System32|WindowsApps)\\') { continue }
        if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
    }
    return $null
}

# ---------------------------------------------------------------------------
# winget
# ---------------------------------------------------------------------------

$script:WingetNoApplicableInstaller = -1978335216

function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Get-WingetArgs {
    param([string]$Id)
    return @('install', '-e', '--id', $Id, '--source', 'winget', '--scope', 'user',
        '--disable-interactivity', '--accept-package-agreements', '--accept-source-agreements')
}

function Install-WingetPackage {
    param([string]$Id)
    $code = Invoke-NativeCommand 'winget' (Get-WingetArgs $Id)
    if ($code -eq 0) { return $true }
    if ($code -eq $script:WingetNoApplicableInstaller) {
        Write-OnboardLine "  winget has no per-user installer for $Id. onboard.ps1 never asks for administrator rights."
        Write-OnboardLine '  To install it for all users yourself, run this in an administrator PowerShell window:'
        Write-OnboardLine "    winget install -e --id $Id --source winget --scope machine"
    } else {
        Write-OnboardLine "  winget exited with code $code."
    }
    return $false
}

# ---------------------------------------------------------------------------
# Execution policy
# ---------------------------------------------------------------------------

function Get-PowerShellExe {
    param([string]$Edition)
    if ($Edition -eq 'Windows PowerShell') {
        $p = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (Test-Path -LiteralPath $p) { return $p }
        return $null
    }
    $cmd = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($env:ProgramFiles) {
        $default = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
        if (Test-Path -LiteralPath $default) { return $default }
    }
    return $null
}

function Get-PolicyList {
    param([string]$Exe)
    $command = 'Get-ExecutionPolicy -List | ForEach-Object { "{0}={1}" -f $_.Scope, $_.ExecutionPolicy }'
    $out = & $Exe -NoProfile -NonInteractive -EncodedCommand (ConvertTo-EncodedCommand $command) 2>$null
    $map = @{}
    foreach ($line in $out) {
        if ("$line" -match '^(\w+)=(\w+)$') { $map[$Matches[1]] = $Matches[2] }
    }
    return $map
}

function Get-PolicyDecision {
    param([hashtable]$Policies)
    $value = @{}
    foreach ($scope in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
        $v = $Policies[$scope]
        if (-not $v) { $v = 'Undefined' }
        $value[$scope] = [string]$v
    }
    if ($value.MachinePolicy -ne 'Undefined' -or $value.UserPolicy -ne 'Undefined') {
        return @{
            Status   = 'na'
            Found    = "controlled by Group Policy (MachinePolicy $($value.MachinePolicy), UserPolicy $($value.UserPolicy)); onboard.ps1 leaves it alone"
            NeedsYes = $false
        }
    }
    $effective = 'Restricted'
    if ($value.CurrentUser -ne 'Undefined') { $effective = $value.CurrentUser }
    elseif ($value.LocalMachine -ne 'Undefined') { $effective = $value.LocalMachine }
    $found = "effective policy $effective (CurrentUser $($value.CurrentUser), LocalMachine $($value.LocalMachine))"
    if (@('RemoteSigned', 'Unrestricted', 'Bypass') -contains $effective) {
        return @{ Status = 'satisfied'; Found = $found; NeedsYes = $false }
    }
    if ($effective -eq 'AllSigned') {
        return @{ Status = 'change'; Found = $found; NeedsYes = $true }
    }
    return @{ Status = 'change'; Found = $found; NeedsYes = $false }
}

function Set-CurrentUserRemoteSigned {
    param([string]$Exe)
    $saved = $env:PSExecutionPolicyPreference
    Remove-Item Env:PSExecutionPolicyPreference -ErrorAction SilentlyContinue -WhatIf:$false
    try {
        $command = 'Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force'
        & $Exe -NoProfile -NonInteractive -EncodedCommand (ConvertTo-EncodedCommand $command) 2>&1 |
            ForEach-Object { Write-OnboardLine ('    ' + $_) }
    } finally {
        if ($null -ne $saved) { $env:PSExecutionPolicyPreference = $saved }
    }
    $after = Get-PolicyList $Exe
    return ($after['CurrentUser'] -eq 'RemoteSigned')
}

# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

function New-Detection {
    param([string]$Status, [string]$Found, [string[]]$Changes = @(), $Data = $null)
    return @{ Status = $Status; Found = $Found; Changes = $Changes; Data = $Data }
}

function Get-PolicyDetection {
    param($Step)
    $exe = Get-PowerShellExe $Step.Edition
    if (-not $exe) { return New-Detection 'na' "$($Step.Edition) is not installed" }
    $decision = Get-PolicyDecision (Get-PolicyList $exe)
    $changes = @("Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned ($($Step.Edition))")
    if ($decision.NeedsYes) { $changes += 'You will be asked to type YES first, because this replaces AllSigned' }
    return New-Detection $decision.Status $decision.Found $changes @{ Exe = $exe; NeedsYes = $decision.NeedsYes }
}

function Invoke-PolicyApply {
    param($Step, $Detection)
    if ($Detection.Data.NeedsYes) {
        Write-OnboardLine '  AllSigned requires every script, including your own, to be signed.'
        Write-OnboardLine '  RemoteSigned for your account lets local scripts run; downloaded scripts still need a signature.'
        if (-not (Confirm-Yes 'Change your execution policy from AllSigned to RemoteSigned?')) { return 'declined' }
    }
    $exe = $Detection.Data.Exe
    $ok = @(Invoke-OnboardChange "Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned ($($Step.Edition))" {
            Set-CurrentUserRemoteSigned $exe
        })[-1]
    if ($ok) {
        Write-OnboardLine '  Your CurrentUser execution policy is now RemoteSigned.'
        return 'done'
    }
    Write-OnboardLine '  The execution policy did not change.'
    return 'failed'
}

function Get-InstallDetection {
    param($Step)
    $tool = Find-Tool $Step.Tool
    if ($tool) {
        $note = ''
        if (-not (Test-PathListContains (Get-NewTerminalPath) $tool.Dir)) { $note = ' (not on PATH)' }
        return New-Detection 'satisfied' "$($Step.Tool) at $($tool.Path)$note"
    }
    if (-not (Test-WingetAvailable)) {
        return New-Detection 'fail' "$($Step.Title) is not installed, and winget is not available. Install App Installer from the Microsoft Store, then run this again."
    }
    $command = 'winget ' + ((Get-WingetArgs $Step.WingetId) -join ' ')
    return New-Detection 'change' 'not installed' @($command)
}

function Invoke-InstallApply {
    param($Step, $Detection)
    $id = $Step.WingetId
    [void](Invoke-OnboardChange ('winget ' + ((Get-WingetArgs $id) -join ' ')) { Install-WingetPackage $id })
    $tool = Find-Tool $Step.Tool
    if ($tool) {
        Write-OnboardLine "  Installed: $($tool.Path)"
        return 'done'
    }
    Write-OnboardLine "  $($Step.Tool) still could not be found after the install."
    return 'failed'
}

function Get-PathDetection {
    param($Step)
    $tool = Find-Tool $Step.Tool
    if (-not $tool) { return New-Detection 'fail' "$($Step.Tool) was not found" }
    if (Test-PathListContains (Get-NewTerminalPath) $tool.Dir) {
        return New-Detection 'satisfied' "$($tool.Dir) is on PATH for new terminals"
    }
    $entry = ConvertTo-PortablePath $tool.Dir
    return New-Detection 'change' "$($tool.Dir) is not on your user PATH" @("Append to your user PATH: $entry") @{ Dir = $tool.Dir }
}

function Invoke-PathApply {
    param($Step, $Detection)
    $dir = $Detection.Data.Dir
    $entry = ConvertTo-PortablePath $dir
    $raw = Get-UserPathRaw
    try {
        $backup = Save-UserPathBackup $raw
    } catch {
        Write-OnboardLine "  Could not save a backup of your user PATH, so it was not changed: $($_.Exception.Message)"
        return 'failed'
    }
    Write-OnboardLine "  Saved your current user PATH to $backup"
    $newValue = Get-NewUserPathValue $raw $entry
    Invoke-OnboardChange "Append to your user PATH: $entry" { Set-UserPathRaw $newValue }
    $script:PathAdded.Add("$entry (user PATH)")
    if (Test-ToolInNewTerminal $Step.Tool) {
        Write-OnboardLine "  Checked with the PATH a new terminal gets: $($Step.Tool) --version works."
        return 'done'
    }
    Write-OnboardLine "  $($Step.Tool) still does not run with the new PATH."
    return 'failed'
}

function Get-GitBashDetection {
    param($Step)
    $git = Find-Tool 'git'
    $gitPath = $null
    if ($git) { $gitPath = $git.Path }
    $bash = Resolve-GitBash $gitPath
    if (-not $bash) {
        return New-Detection 'fail' 'Git Bash was not found next to git.exe or in the usual Git for Windows folders. Claude Code needs it on Windows.'
    }
    $script:GitBashPath = $bash
    return New-Detection 'info' "found $bash"
}

function Test-DefaultGitBash {
    param([string]$Path)
    if (-not $env:ProgramFiles) { return $false }
    return ($Path -ieq (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'))
}

function Get-WindowsSteps {
    param([string]$Choice)
    $steps = @(
        @{ Id = 'policy-ps5'; Title = 'Execution policy (Windows PowerShell)'; Edition = 'Windows PowerShell'
            Purpose = 'Lets your user account run local PowerShell scripts.'; Detect = 'Get-PolicyDetection'; Apply = 'Invoke-PolicyApply' },
        @{ Id = 'policy-ps7'; Title = 'Execution policy (PowerShell 7)'; Edition = 'PowerShell 7'
            Purpose = 'Lets your user account run local PowerShell 7 scripts.'; Detect = 'Get-PolicyDetection'; Apply = 'Invoke-PolicyApply' },
        @{ Id = 'git'; Title = 'Git'; Tool = 'git'; WingetId = 'Git.Git'
            Purpose = 'Installs Git for your user account.'; Detect = 'Get-InstallDetection'; Apply = 'Invoke-InstallApply' },
        @{ Id = 'git-path'; Title = 'Git on PATH'; Tool = 'git'; DependsOn = 'git'
            Purpose = 'Lets new terminals find git.'; Detect = 'Get-PathDetection'; Apply = 'Invoke-PathApply' }
    )
    $claude = @(
        @{ Id = 'git-bash'; Title = 'Git Bash'; DependsOn = 'git'; Detect = 'Get-GitBashDetection' },
        @{ Id = 'claude'; Title = 'Claude Code'; Tool = 'claude'; WingetId = 'Anthropic.ClaudeCode'
            Purpose = 'Installs the Claude Code CLI for your user account.'; Detect = 'Get-InstallDetection'; Apply = 'Invoke-InstallApply' },
        @{ Id = 'claude-path'; Title = 'Claude Code on PATH'; Tool = 'claude'; DependsOn = 'claude'
            Purpose = 'Lets new terminals find claude.'; Detect = 'Get-PathDetection'; Apply = 'Invoke-PathApply' }
    )
    $codex = @(
        @{ Id = 'codex'; Title = 'Codex'; Tool = 'codex'; WingetId = 'OpenAI.Codex'
            Purpose = 'Installs the OpenAI Codex CLI for your user account.'; Detect = 'Get-InstallDetection'; Apply = 'Invoke-InstallApply' },
        @{ Id = 'codex-path'; Title = 'Codex on PATH'; Tool = 'codex'; DependsOn = 'codex'
            Purpose = 'Lets new terminals find codex.'; Detect = 'Get-PathDetection'; Apply = 'Invoke-PathApply' }
    )
    if ($Choice -eq 'codex') { foreach ($s in $claude) { $s.NotApplicable = 'Claude Code was not chosen' } }
    if ($Choice -eq 'claude') { foreach ($s in $codex) { $s.NotApplicable = 'Codex was not chosen' } }
    return , ($steps + $claude + $codex)
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

function Get-PlanText {
    param($Detection)
    switch ($Detection.Status) {
        'satisfied' { return 'already set up' }
        'change' { return 'will change' }
        'na' { return 'not applicable' }
        'info' { return 'will check' }
        default { return 'cannot be done (details below)' }
    }
}

function Get-StepTitle {
    param([object[]]$Steps, [string]$Id)
    foreach ($s in $Steps) { if ($s.Id -eq $Id) { return $s.Title } }
    return $Id
}

function Invoke-OnboardSteps {
    param([object[]]$Steps)
    $outcomes = [ordered]@{}
    $total = $Steps.Count
    $width = ($Steps | ForEach-Object { $_.Title.Length } | Measure-Object -Maximum).Maximum + 3

    Write-OnboardLine 'Plan' 'Cyan'
    $planStatus = @{}
    $n = 0
    foreach ($s in $Steps) {
        $n++
        if ($s.NotApplicable) {
            $text = 'not applicable'
            $planStatus[$s.Id] = 'na'
        } elseif ($s.DependsOn -and $planStatus[$s.DependsOn] -ne 'satisfied') {
            $text = 'checked after ' + (Get-StepTitle $Steps $s.DependsOn)
            $planStatus[$s.Id] = 'pending'
        } else {
            $d = & $s.Detect $s
            $text = Get-PlanText $d
            $planStatus[$s.Id] = $d.Status
        }
        Write-OnboardLine ('  {0,2}. {1}{2}' -f $n, $s.Title.PadRight($width), $text)
    }
    Write-OnboardLine ''

    $quit = $false
    if ($script:Guided) {
        Write-OnboardLine 'Nothing changes until you choose Next at a step.'
        Write-OnboardLine 'Press Enter to start, or Q to quit.' 'Cyan'
        $start = Read-TerminalLine
        if ($null -eq $start -or @('q', 'quit') -contains $start.Trim().ToLowerInvariant()) { $quit = $true }
    }

    $n = 0
    foreach ($s in $Steps) {
        $n++
        $tag = "[$n/$total] $($s.Title)"
        if ($s.NotApplicable) {
            $outcomes[$s.Id] = 'not applicable'
            $script:Details[$s.Id] = $s.NotApplicable
            Write-OnboardLine "${tag}: not applicable. $($s.NotApplicable)" 'DarkGray'
            continue
        }
        if ($quit) { $outcomes[$s.Id] = 'skipped'; continue }
        if ($s.DependsOn) {
            $dep = $outcomes[$s.DependsOn]
            $depTitle = Get-StepTitle $Steps $s.DependsOn
            if ($script:Preview -and $dep -eq 'would change') {
                $outcomes[$s.Id] = "checked after $depTitle"
                Write-OnboardLine "${tag}: checked after $depTitle" 'DarkGray'
                continue
            }
            if (@('done', 'already satisfied') -notcontains $dep) {
                $outcomes[$s.Id] = 'skipped'
                Write-OnboardLine "${tag}: skipped, needs $depTitle" 'DarkGray'
                continue
            }
        }

        $d = & $s.Detect $s
        if ($d.Status -eq 'satisfied') {
            $outcomes[$s.Id] = 'already satisfied'
            Write-OnboardLine "${tag}: already satisfied. $($d.Found)" 'DarkGray'
            continue
        }
        if ($d.Status -eq 'na') {
            $outcomes[$s.Id] = 'not applicable'
            $script:Details[$s.Id] = $d.Found
            Write-OnboardLine "${tag}: not applicable. $($d.Found)" 'DarkGray'
            continue
        }
        if ($d.Status -eq 'info') {
            $outcomes[$s.Id] = 'already satisfied'
            Write-OnboardLine "${tag}: $($d.Found)" 'DarkGray'
            continue
        }
        if ($d.Status -ne 'change') {
            $outcomes[$s.Id] = 'failed'
            Write-OnboardLine "${tag}: failed. $($d.Found)" 'Yellow'
            continue
        }

        Write-OnboardLine ''
        Write-OnboardLine "Step $n of ${total}: $($s.Title)" 'Cyan'
        if ($s.Purpose) { Write-OnboardLine $s.Purpose }
        Write-OnboardLine "Found:    $($d.Found)"
        $first = $true
        foreach ($c in $d.Changes) {
            if ($first) {
                if ($script:Preview) { $prefix = 'Would do: ' } else { $prefix = 'Will do:  ' }
                $first = $false
            } else {
                $prefix = '          '
            }
            Write-OnboardLine ($prefix + $c)
        }
        if ($script:Preview) {
            $outcomes[$s.Id] = 'would change'
            continue
        }

        $answer = 'next'
        if ($script:Guided) { $answer = Read-StepAnswer }
        if ($answer -eq 'skip') {
            $outcomes[$s.Id] = 'skipped'
            Write-OnboardLine "$($s.Title): skipped."
            continue
        }
        if ($answer -eq 'quit') {
            $outcomes[$s.Id] = 'skipped'
            $quit = $true
            continue
        }

        $result = @(& $s.Apply $s $d)
        $outcome = 'failed'
        if ($result.Count -gt 0) { $outcome = [string]$result[-1] }
        $outcomes[$s.Id] = $outcome
        if ($outcome -ne 'done') { Write-OnboardLine "$($s.Title): $outcome." 'Yellow' }
    }
    return $outcomes
}

function Get-OnboardExitCode {
    param($Outcomes)
    foreach ($value in $Outcomes.Values) {
        if ($value -eq 'failed' -or $value -eq 'declined') { return 1 }
    }
    return 0
}

function Write-OnboardSummary {
    param([object[]]$Steps, $Outcomes, [string]$Choice)
    $width = ($Steps | ForEach-Object { $_.Title.Length } | Measure-Object -Maximum).Maximum + 3
    Write-OnboardLine ''
    Write-OnboardLine 'Summary' 'Cyan'
    foreach ($s in $Steps) {
        $text = $Outcomes[$s.Id]
        if ($text -eq 'not applicable' -and $script:Details[$s.Id]) { $text += " ($($script:Details[$s.Id]))" }
        Write-OnboardLine ('  {0}{1}' -f $s.Title.PadRight($width), $text)
    }
    Write-OnboardLine ''
    if ($script:Backups.Count -gt 0) {
        Write-OnboardLine 'Backups written:'
        foreach ($b in $script:Backups) { Write-OnboardLine "  $b" }
    }
    if ($script:PathAdded.Count -gt 0) {
        Write-OnboardLine 'Added to PATH:'
        foreach ($p in $script:PathAdded) { Write-OnboardLine "  $p" }
    }
    if ($script:GitBashPath) {
        Write-OnboardLine "Git Bash: $script:GitBashPath"
        if (-not (Test-DefaultGitBash $script:GitBashPath)) {
            Write-OnboardLine "  Git Bash is not in its default folder. If Claude Code cannot find it, set CLAUDE_CODE_GIT_BASH_PATH to $script:GitBashPath"
        }
    }
    $values = @($Outcomes.Values)
    if ($values -contains 'skipped' -or $values -contains 'declined') {
        Write-OnboardLine 'Skipped or declined steps are offered again when you run the same command again.'
    }
    if ($script:Preview) {
        if ($values -notcontains 'would change' -and $values -notcontains 'failed') {
            Write-OnboardLine 'A real run would change nothing.'
        }
        Write-OnboardLine 'Preview only: nothing was changed.'
        return
    }
    $tools = (Get-AgentTools $Choice) -join ', then '
    Write-OnboardLine "Next: open a new PowerShell window and run $tools to sign in."
}

function Invoke-Onboarding {
    param([string]$AgentValue, [bool]$NoGuideValue, [bool]$PreviewValue)
    $choice = Resolve-AgentChoice $AgentValue
    if (-not $choice) {
        if ($AgentValue) {
            Write-OnboardLine "onboard.ps1: '$AgentValue' is not a valid -Agent value."
        } else {
            Write-OnboardLine 'onboard.ps1: choose which coding agent to set up with -Agent.'
        }
        Write-OnboardLine $script:Usage
        Write-OnboardLine 'Nothing was changed.'
        return 2
    }
    if (-not (Test-IsWindows)) {
        Write-OnboardLine 'onboard.ps1 sets up Windows. On macOS or Linux, run onboard.sh instead.'
        return 1
    }

    $script:Preview = $PreviewValue
    $script:Guided = (-not $PreviewValue) -and (-not $NoGuideValue) -and (Test-CanPrompt)

    $edition = 'PowerShell ' + $PSVersionTable.PSVersion.ToString()
    Write-OnboardLine ("onboard.ps1 {0} | Windows {1} | {2} | agent: {3}" -f $script:OnboardVersion, [Environment]::OSVersion.Version, $edition, $choice)
    if ($PreviewValue) { Write-OnboardLine 'Preview: nothing will be changed.' }
    if ($NoGuideValue -and -not $PreviewValue) { Write-OnboardLine 'Running every step without pausing.' }
    Write-OnboardLine ''

    $steps = Get-WindowsSteps $choice
    $outcomes = Invoke-OnboardSteps $steps
    Write-OnboardSummary $steps $outcomes $choice
    $code = Get-OnboardExitCode $outcomes
    Write-OnboardLine "Exit code: $code"
    return $code
}

if ($MyInvocation.InvocationName -ne '.') {
    $exitCode = @(Invoke-Onboarding -AgentValue $Agent -NoGuideValue $NoGuide.IsPresent -PreviewValue ([bool]$WhatIfPreference))[-1]
    exit $exitCode
}
