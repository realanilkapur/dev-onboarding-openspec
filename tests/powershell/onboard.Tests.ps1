#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Every test replaces the functions that touch the registry, winget, or the execution
# policy, so running these tests changes nothing on the machine.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\scripts\onboard.ps1'
    . $scriptPath

    function Reset-OnboardState {
        $script:Lines.Clear()
        $script:Backups.Clear()
        $script:PathAdded.Clear()
        $script:Preview = $false
        $script:Guided = $false
        $script:GitBashPath = $null
        $script:Details = @{}
        $script:BackupDir = $null
        $script:ReadAnswer = $null
        $script:ReadCount = 0
        $script:Applied = New-Object System.Collections.Generic.List[string]
    }

    function Set-Answers {
        param([string[]]$Answers)
        $script:AnswerQueue = New-Object System.Collections.Queue
        foreach ($a in $Answers) { $script:AnswerQueue.Enqueue($a) }
        $script:ReadAnswer = {
            $script:ReadCount++
            if ($script:AnswerQueue.Count -eq 0) { return $null }
            return $script:AnswerQueue.Dequeue()
        }
    }

    function Get-FakeDetection {
        param($Step)
        return New-Detection $script:FakeStatus[$Step.Id] "state of $($Step.Id)" @("change $($Step.Id)")
    }

    function Invoke-FakeApply {
        param($Step, $Detection)
        $script:Applied.Add($Step.Id)
        return $script:FakeResult[$Step.Id]
    }

    function Get-FakeSteps {
        return , @(
            @{ Id = 'a'; Title = 'Tool A'; Detect = 'Get-FakeDetection'; Apply = 'Invoke-FakeApply' },
            @{ Id = 'a-path'; Title = 'Tool A on PATH'; DependsOn = 'a'; Detect = 'Get-FakeDetection'; Apply = 'Invoke-FakeApply' },
            @{ Id = 'b'; Title = 'Tool B'; Detect = 'Get-FakeDetection'; Apply = 'Invoke-FakeApply' },
            @{ Id = 'b-path'; Title = 'Tool B on PATH'; DependsOn = 'b'; Detect = 'Get-FakeDetection'; Apply = 'Invoke-FakeApply' }
        )
    }

    function Set-FakeWorld {
        param([hashtable]$Status, [hashtable]$Result)
        $script:FakeStatus = @{ 'a' = 'change'; 'a-path' = 'change'; 'b' = 'change'; 'b-path' = 'change' }
        $script:FakeResult = @{ 'a' = 'done'; 'a-path' = 'done'; 'b' = 'done'; 'b-path' = 'done' }
        if ($Status) { foreach ($k in $Status.Keys) { $script:FakeStatus[$k] = $Status[$k] } }
        if ($Result) { foreach ($k in $Result.Keys) { $script:FakeResult[$k] = $Result[$k] } }
    }
}

Describe 'Agent choice' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'accepts <Value>' -TestCases @(
        @{ Value = 'claude'; Expected = 'claude' }
        @{ Value = 'CODEX'; Expected = 'codex' }
        @{ Value = ' Both '; Expected = 'both' }
    ) {
        Resolve-AgentChoice $Value | Should -Be $Expected
    }

    It 'rejects <Value>' -TestCases @(@{ Value = '' }, @{ Value = 'gemini' }, @{ Value = $null }) {
        Resolve-AgentChoice $Value | Should -BeNullOrEmpty
    }

    It 'returns 2 and changes nothing when -Agent is missing or invalid' {
        Mock Get-WindowsSteps { throw 'should not be called' }
        Invoke-Onboarding -AgentValue '' -NoGuideValue $false -PreviewValue $false | Should -Be 2
        Invoke-Onboarding -AgentValue 'gemini' -NoGuideValue $false -PreviewValue $false | Should -Be 2
        ($script:Lines -join "`n") | Should -Match 'Nothing was changed'
    }

    It 'lists every step for every choice' {
        foreach ($choice in 'claude', 'codex', 'both') {
            (Get-WindowsSteps $choice).Id | Should -Be @('policy-ps5', 'policy-ps7', 'git', 'git-path', 'git-bash', 'claude', 'claude-path', 'codex', 'codex-path')
        }
    }

    It 'marks the Claude Code and Git Bash steps not applicable when only Codex is chosen' {
        $steps = Get-WindowsSteps 'codex'
        foreach ($s in $steps) { if ($s.Detect) { $s.Detect = 'Get-FakeDetection'; $s.Apply = 'Invoke-FakeApply' } }
        $script:FakeStatus = @{}
        foreach ($s in $steps) { $script:FakeStatus[$s.Id] = 'change' }
        $script:FakeResult = @{}
        foreach ($s in $steps) { $script:FakeResult[$s.Id] = 'done' }
        $o = Invoke-OnboardSteps $steps
        $o['git-bash'] | Should -Be 'not applicable'
        $o['claude'] | Should -Be 'not applicable'
        $o['claude-path'] | Should -Be 'not applicable'
        $o['codex'] | Should -Be 'done'
        $script:Applied | Should -Not -Contain 'claude'
    }

    It 'marks the Codex steps not applicable when only Claude Code is chosen' {
        $steps = Get-WindowsSteps 'claude'
        ($steps | Where-Object { $_.Id -like 'codex*' }).NotApplicable | Should -Be @('Codex was not chosen', 'Codex was not chosen')
        ($steps | Where-Object { $_.Id -eq 'git-bash' }).NotApplicable | Should -BeNullOrEmpty
    }
}

Describe 'Execution policy decision' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'leaves Group Policy alone' {
        $d = Get-PolicyDecision @{ MachinePolicy = 'AllSigned'; UserPolicy = 'Undefined'; CurrentUser = 'Restricted'; LocalMachine = 'Restricted' }
        $d.Status | Should -Be 'na'
    }

    It 'is satisfied by CurrentUser RemoteSigned' {
        (Get-PolicyDecision @{ CurrentUser = 'RemoteSigned'; LocalMachine = 'Restricted' }).Status | Should -Be 'satisfied'
    }

    It 'is satisfied by LocalMachine RemoteSigned when CurrentUser is Undefined' {
        (Get-PolicyDecision @{ CurrentUser = 'Undefined'; LocalMachine = 'RemoteSigned' }).Status | Should -Be 'satisfied'
    }

    It 'treats all-Undefined as Restricted and changes it' {
        $d = Get-PolicyDecision @{}
        $d.Status | Should -Be 'change'
        $d.Found | Should -Match 'effective policy Restricted'
        $d.NeedsYes | Should -BeFalse
    }

    It 'ignores the Process scope' {
        (Get-PolicyDecision @{ Process = 'Bypass'; CurrentUser = 'Restricted' }).Status | Should -Be 'change'
    }

    It 'asks for YES before replacing AllSigned' {
        $d = Get-PolicyDecision @{ CurrentUser = 'AllSigned' }
        $d.Status | Should -Be 'change'
        $d.NeedsYes | Should -BeTrue
    }

    It 'fails the step when the policy does not change' {
        Mock Set-CurrentUserRemoteSigned { $false }
        $detection = New-Detection 'change' 'x' @() @{ Exe = 'powershell.exe'; NeedsYes = $false }
        Invoke-PolicyApply @{ Edition = 'Windows PowerShell' } $detection | Should -Be 'failed'
    }

    It 'marks PowerShell 7 not applicable when it is not installed' {
        Mock Get-PowerShellExe { $null }
        (Get-PolicyDetection @{ Edition = 'PowerShell 7' }).Status | Should -Be 'na'
    }

    It 'counts anything but exactly YES as declined, and does not change the policy' {
        Mock Set-CurrentUserRemoteSigned { $true }
        $detection = New-Detection 'change' 'x' @() @{ Exe = 'powershell.exe'; NeedsYes = $true }
        foreach ($answer in 'yes', 'Y', '', $null) {
            Set-Answers @($answer)
            Invoke-PolicyApply @{ Edition = 'Windows PowerShell' } $detection | Should -Be 'declined'
        }
        Should -Invoke Set-CurrentUserRemoteSigned -Times 0
        Set-Answers @('YES')
        Invoke-PolicyApply @{ Edition = 'Windows PowerShell' } $detection | Should -Be 'done'
        Should -Invoke Set-CurrentUserRemoteSigned -Times 1
    }
}

Describe 'User PATH' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'matches PATH entries regardless of case, quotes, trailing backslash, and variables' {
        Test-PathListContains 'C:\A;"C:\Tools\Bin\";D:\x' 'c:\tools\bin' | Should -BeTrue
        Test-PathListContains "%USERPROFILE%\.local\bin" "$env:USERPROFILE\.local\bin" | Should -BeTrue
        Test-PathListContains 'C:\A;C:\B' 'C:\C' | Should -BeFalse
    }

    It 'stores per-user folders with a variable' {
        ConvertTo-PortablePath "$env:LOCALAPPDATA\Programs\OpenAI\Codex\bin" | Should -Be '%LOCALAPPDATA%\Programs\OpenAI\Codex\bin'
        ConvertTo-PortablePath "$env:USERPROFILE\.local\bin" | Should -Be '%USERPROFILE%\.local\bin'
        ConvertTo-PortablePath 'D:\Tools' | Should -Be 'D:\Tools'
    }

    It 'appends without touching existing entries' {
        Get-NewUserPathValue '%USERPROFILE%\a;C:\b;' '%LOCALAPPDATA%\c' | Should -Be '%USERPROFILE%\a;C:\b;%LOCALAPPDATA%\c'
        Get-NewUserPathValue '' 'C:\c' | Should -Be 'C:\c'
    }

    It 'backs up the raw user PATH, then appends the folder' {
        $script:BackupDir = Join-Path $TestDrive 'backup'
        Mock Get-UserPathRaw { '%USERPROFILE%\old;C:\keep' }
        Mock Set-UserPathRaw { $script:Written = $Value }
        Mock Test-ToolInNewTerminal { $true }
        $detection = New-Detection 'change' 'x' @() @{ Dir = "$env:USERPROFILE\.local\bin" }
        Invoke-PathApply @{ Tool = 'claude' } $detection | Should -Be 'done'
        $script:Written | Should -Be '%USERPROFILE%\old;C:\keep;%USERPROFILE%\.local\bin'
        $script:Backups.Count | Should -Be 1
        Get-Content -LiteralPath $script:Backups[0] -Raw | Should -Be '%USERPROFILE%\old;C:\keep'
    }

    It 'does not change PATH when the backup cannot be written' {
        Mock Get-UserPathRaw { 'C:\keep' }
        Mock Save-UserPathBackup { throw 'disk full' }
        Mock Set-UserPathRaw {}
        $detection = New-Detection 'change' 'x' @() @{ Dir = 'C:\new' }
        Invoke-PathApply @{ Tool = 'git' } $detection | Should -Be 'failed'
        Should -Invoke Set-UserPathRaw -Times 0
    }

    It 'fails when the tool still does not run with the new PATH' {
        $script:BackupDir = Join-Path $TestDrive 'backup2'
        Mock Get-UserPathRaw { '' }
        Mock Set-UserPathRaw {}
        Mock Test-ToolInNewTerminal { $false }
        $detection = New-Detection 'change' 'x' @() @{ Dir = 'C:\new' }
        Invoke-PathApply @{ Tool = 'git' } $detection | Should -Be 'failed'
    }
}

Describe 'Backups' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'never overwrites an existing backup' {
        $file = Join-Path $TestDrive 'user-path.txt'
        $now = [datetime]'2026-11-16T10:20:30'
        Get-BackupPath $file $now | Should -Be "$file.bak"
        Set-Content -LiteralPath "$file.bak" 'one'
        Get-BackupPath $file $now | Should -Be "$file.20261116102030.bak"
        Set-Content -LiteralPath "$file.20261116102030.bak" 'two'
        Get-BackupPath $file $now | Should -Be "$file.20261116102030-1.bak"
    }

    It 'writes a new file for every backup' {
        $script:BackupDir = Join-Path $TestDrive 'many'
        $first = Save-UserPathBackup 'first'
        $second = Save-UserPathBackup 'second'
        $first | Should -Not -Be $second
        Get-Content -LiteralPath $first -Raw | Should -Be 'first'
        Get-Content -LiteralPath $second -Raw | Should -Be 'second'
    }
}

Describe 'Git Bash' {
    BeforeEach {
        Reset-OnboardState
        Mock Write-Host {}
        $script:SavedProgramFiles = $env:ProgramFiles
        $script:SavedLocalAppData = $env:LOCALAPPDATA
        $unique = [guid]::NewGuid().ToString('N')
        $env:ProgramFiles = Join-Path $TestDrive "pf-$unique"
        $env:LOCALAPPDATA = Join-Path $TestDrive "lad-$unique"
    }
    AfterEach {
        $env:ProgramFiles = $script:SavedProgramFiles
        $env:LOCALAPPDATA = $script:SavedLocalAppData
    }

    It 'finds bin\bash.exe next to cmd\git.exe' {
        $root = Join-Path $TestDrive 'Git'
        New-Item -ItemType Directory -Force "$root\cmd", "$root\bin" | Out-Null
        New-Item -ItemType File "$root\bin\bash.exe" | Out-Null
        Resolve-GitBash "$root\cmd\git.exe" | Should -Be "$root\bin\bash.exe"
    }

    It 'finds bin\bash.exe from mingw64\bin\git.exe' {
        $root = Join-Path $TestDrive 'Git2'
        New-Item -ItemType Directory -Force "$root\mingw64\bin", "$root\bin" | Out-Null
        New-Item -ItemType File "$root\bin\bash.exe" | Out-Null
        Resolve-GitBash "$root\mingw64\bin\git.exe" | Should -Be "$root\bin\bash.exe"
    }

    It 'finds bash.exe next to bin\git.exe' {
        $root = Join-Path $TestDrive 'Git3'
        New-Item -ItemType Directory -Force "$root\bin" | Out-Null
        New-Item -ItemType File "$root\bin\bash.exe" | Out-Null
        Resolve-GitBash "$root\bin\git.exe" | Should -Be "$root\bin\bash.exe"
    }

    It 'falls back to the per-user Git for Windows folder' {
        New-Item -ItemType Directory -Force "$env:LOCALAPPDATA\Programs\Git\bin" | Out-Null
        New-Item -ItemType File "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe" | Out-Null
        Resolve-GitBash $null | Should -Be "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
    }

    It 'rejects the WSL bash in System32' {
        Resolve-GitBash 'C:\Windows\System32\git.exe' | Should -BeNullOrEmpty
    }

    It 'suggests CLAUDE_CODE_GIT_BASH_PATH only when Git Bash is not in its default folder' {
        $script:GitBashPath = Join-Path $env:ProgramFiles 'Git\bin\bash.exe'
        Write-OnboardSummary @(@{ Id = 'x'; Title = 'X' }) @{ x = 'done' } 'claude'
        ($script:Lines -join "`n") | Should -Not -Match 'CLAUDE_CODE_GIT_BASH_PATH'
        $script:Lines.Clear()
        $script:GitBashPath = 'D:\Tools\Git\bin\bash.exe'
        Write-OnboardSummary @(@{ Id = 'x'; Title = 'X' }) @{ x = 'done' } 'claude'
        ($script:Lines -join "`n") | Should -Match 'CLAUDE_CODE_GIT_BASH_PATH to D:\\Tools\\Git\\bin\\bash.exe'
    }

    It 'requires the tool to run in Git Bash as well, when Git Bash was found' {
        $bin = Join-Path $TestDrive 'bin'
        New-Item -ItemType Directory -Force $bin | Out-Null
        Set-Content -LiteralPath "$bin\faketool.cmd" '@exit /b 0'
        Set-Content -LiteralPath "$bin\goodbash.cmd" '@exit /b 0'
        Set-Content -LiteralPath "$bin\badbash.cmd" '@exit /b 1'
        Mock Get-NewTerminalPath { "$bin;$env:SystemRoot\System32" }
        Test-ToolInNewTerminal 'faketool' | Should -BeTrue
        $script:GitBashPath = "$bin\goodbash.cmd"
        Test-ToolInNewTerminal 'faketool' | Should -BeTrue
        $script:GitBashPath = "$bin\badbash.cmd"
        Test-ToolInNewTerminal 'faketool' | Should -BeFalse
    }
}

Describe 'winget' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'installs for the current user only' {
        $wingetArgs = Get-WingetArgs 'Git.Git'
        ($wingetArgs -join ' ') | Should -Match '--scope user'
        $wingetArgs | Should -Not -Contain 'machine'
        $wingetArgs | Should -Contain '--disable-interactivity'
    }

    It 'prints the all-users command instead of running it when there is no per-user installer' {
        Mock Invoke-NativeCommand { -1978335216 }
        Install-WingetPackage 'Git.Git' | Should -BeFalse
        ($script:Lines -join "`n") | Should -Match 'winget install -e --id Git.Git --source winget --scope machine'
        Should -Invoke Invoke-NativeCommand -Times 1
    }

    It 'reports a missing winget as a failure with a next step' {
        Mock Find-Tool { $null }
        Mock Test-WingetAvailable { $false }
        $d = Get-InstallDetection @{ Tool = 'git'; Title = 'Git'; WingetId = 'Git.Git' }
        $d.Status | Should -Be 'fail'
        $d.Found | Should -Match 'App Installer'
    }

    It 'plans a per-user winget install when the tool is missing' {
        Mock Find-Tool { $null }
        Mock Test-WingetAvailable { $true }
        $d = Get-InstallDetection @{ Tool = 'codex'; Title = 'Codex'; WingetId = 'OpenAI.Codex' }
        $d.Status | Should -Be 'change'
        $d.Changes[0] | Should -Match '^winget install -e --id OpenAI.Codex .*--scope user'
    }

    It 'counts a tool that is installed but not on PATH as installed' {
        Mock Find-Tool { @{ Path = 'C:\x\codex.exe'; Dir = 'C:\x' } }
        Mock Get-NewTerminalPath { 'C:\Windows' }
        $d = Get-InstallDetection @{ Tool = 'codex'; Title = 'Codex'; WingetId = 'OpenAI.Codex' }
        $d.Status | Should -Be 'satisfied'
        $d.Found | Should -Match 'not on PATH'
        (Get-PathDetection @{ Tool = 'codex' }).Status | Should -Be 'change'
    }
}

Describe 'Guided run' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'applies a step on Next' {
        Set-FakeWorld
        $script:Guided = $true
        Set-Answers @('', '', '', '', '')
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $script:Applied | Should -Be @('a', 'a-path', 'b', 'b-path')
        Get-OnboardExitCode $o | Should -Be 0
    }

    It 'skips a step and the steps that depend on it, and exits 0' {
        Set-FakeWorld
        $script:Guided = $true
        Set-Answers @('', 's', '', '')
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $o['a'] | Should -Be 'skipped'
        $o['a-path'] | Should -Be 'skipped'
        $script:Applied | Should -Be @('b', 'b-path')
        Get-OnboardExitCode $o | Should -Be 0
    }

    It 'stops on Quit and marks the rest skipped' {
        Set-FakeWorld
        $script:Guided = $true
        Set-Answers @('', '', 'Q')
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $script:Applied | Should -Be @('a')
        $o['a-path'] | Should -Be 'skipped'
        $o['b'] | Should -Be 'skipped'
        $o['b-path'] | Should -Be 'skipped'
        Get-OnboardExitCode $o | Should -Be 0
    }

    It 'quits before any step when Q is pressed at the start' {
        Set-FakeWorld
        $script:Guided = $true
        Set-Answers @('q')
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $script:Applied.Count | Should -Be 0
        @($o.Values | Select-Object -Unique) | Should -Be @('skipped')
    }

    It 'treats the end of input as Quit' {
        Set-FakeWorld
        $script:Guided = $true
        Set-Answers @('')
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $script:Applied.Count | Should -Be 0
        $o['a'] | Should -Be 'skipped'
    }

    It 'asks again after an unrecognized answer' {
        Set-FakeWorld @{ 'b' = 'satisfied'; 'b-path' = 'satisfied' }
        $script:Guided = $true
        Set-Answers @('', 'maybe', '', '')
        Invoke-OnboardSteps (Get-FakeSteps) | Out-Null
        $script:Applied | Should -Be @('a', 'a-path')
        ($script:Lines -join "`n") | Should -Match 'Press Enter for Next, or type S to skip or Q to quit'
    }

    It 'does not pause at steps that are already satisfied' {
        Set-FakeWorld @{ 'a' = 'satisfied'; 'a-path' = 'satisfied'; 'b' = 'satisfied'; 'b-path' = 'na' }
        $script:Guided = $true
        Set-Answers @('')
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $script:ReadCount | Should -Be 1
        $o['b-path'] | Should -Be 'not applicable'
        Get-OnboardExitCode $o | Should -Be 0
    }

    It 'runs straight through without reading answers when not guided' {
        Set-FakeWorld
        Set-Answers @()
        Invoke-OnboardSteps (Get-FakeSteps) | Out-Null
        $script:ReadCount | Should -Be 0
        $script:Applied.Count | Should -Be 4
    }

    It 'skips only the dependents of a failed step and exits 1' {
        Set-FakeWorld -Result @{ 'a' = 'failed' }
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $o['a'] | Should -Be 'failed'
        $o['a-path'] | Should -Be 'skipped'
        $o['b'] | Should -Be 'done'
        $o['b-path'] | Should -Be 'done'
        Get-OnboardExitCode $o | Should -Be 1
    }

    It 'exits 1 when a step is declined' {
        Set-FakeWorld -Result @{ 'b' = 'declined' }
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $o['b-path'] | Should -Be 'skipped'
        Get-OnboardExitCode $o | Should -Be 1
    }

    It 'reports a step that cannot be done as failed without applying it' {
        Set-FakeWorld @{ 'a' = 'fail' }
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $o['a'] | Should -Be 'failed'
        $script:Applied | Should -Not -Contain 'a'
    }
}

Describe 'Preview' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'applies nothing and does not pause' {
        Set-FakeWorld
        $script:Preview = $true
        $script:Guided = $false
        Set-Answers @()
        $o = Invoke-OnboardSteps (Get-FakeSteps)
        $script:Applied.Count | Should -Be 0
        $script:ReadCount | Should -Be 0
        $o['a'] | Should -Be 'would change'
        $o['a-path'] | Should -Be 'checked after Tool A'
        Get-OnboardExitCode $o | Should -Be 0
    }

    It 'never installs, changes PATH, or sets the policy on a machine with nothing installed' {
        Mock Test-IsWindows { $true }
        Mock Test-CanPrompt { $true }
        Mock Get-PowerShellExe { 'powershell.exe' }
        Mock Get-PolicyList { @{ CurrentUser = 'Undefined'; LocalMachine = 'Undefined' } }
        Mock Find-Tool { $null }
        Mock Test-WingetAvailable { $true }
        Mock Install-WingetPackage { throw 'must not install' }
        Mock Set-UserPathRaw { throw 'must not write PATH' }
        Mock Set-CurrentUserRemoteSigned { throw 'must not set policy' }
        Mock Save-UserPathBackup { throw 'must not back up' }
        Set-Answers @()
        Invoke-Onboarding -AgentValue 'both' -NoGuideValue $false -PreviewValue $true | Should -Be 0
        $script:ReadCount | Should -Be 0
        $text = $script:Lines -join "`n"
        $text | Should -Match 'Would do: winget install -e --id Git.Git'
        $text | Should -Match 'Would do: winget install -e --id Anthropic.ClaudeCode'
        $text | Should -Match 'Would do: winget install -e --id OpenAI.Codex'
        $text | Should -Match 'Preview only: nothing was changed.'
        $text | Should -Not -Match 'A real run would change nothing'
    }

    It 'says a real run would change nothing when everything is set up' {
        Set-FakeWorld @{ 'a' = 'satisfied'; 'a-path' = 'satisfied'; 'b' = 'satisfied'; 'b-path' = 'satisfied' }
        $script:Preview = $true
        $steps = Get-FakeSteps
        $o = Invoke-OnboardSteps $steps
        Write-OnboardSummary $steps $o 'both'
        ($script:Lines -join "`n") | Should -Match 'A real run would change nothing.'
    }

    It 'reports Group Policy control in the summary' {
        Mock Get-PowerShellExe { 'powershell.exe' }
        Mock Get-PolicyList { @{ MachinePolicy = 'AllSigned' } }
        $steps = @((Get-WindowsSteps 'both')[0])
        $o = Invoke-OnboardSteps $steps
        Write-OnboardSummary $steps $o 'both'
        $o['policy-ps5'] | Should -Be 'not applicable'
        ($script:Lines | Select-Object -Last 8) -join "`n" | Should -Match 'controlled by Group Policy'
    }
}

Describe 'Second run' {
    BeforeEach { Reset-OnboardState; Mock Write-Host {} }

    It 'changes nothing when everything is already set up' {
        Mock Test-IsWindows { $true }
        Mock Get-PowerShellExe { 'powershell.exe' }
        Mock Get-PolicyList { @{ CurrentUser = 'RemoteSigned' } }
        Mock Find-Tool { @{ Path = "C:\tools\$Tool.exe"; Dir = 'C:\tools' } }
        Mock Get-NewTerminalPath { 'C:\Windows;C:\tools' }
        Mock Resolve-GitBash { 'C:\Program Files\Git\bin\bash.exe' }
        Mock Install-WingetPackage { throw 'must not install' }
        Mock Set-UserPathRaw { throw 'must not write PATH' }
        Mock Set-CurrentUserRemoteSigned { throw 'must not set policy' }
        Mock Save-UserPathBackup { throw 'must not back up' }
        Invoke-Onboarding -AgentValue 'both' -NoGuideValue $true -PreviewValue $false | Should -Be 0
        $script:Backups.Count | Should -Be 0
        $script:PathAdded.Count | Should -Be 0
    }
}

Describe 'Script safety' {
    BeforeAll {
        $script:Source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\scripts\onboard.ps1') -Raw
    }

    It 'never asks for administrator rights' {
        $script:Source | Should -Not -Match '-Verb\s+RunAs'
    }

    It 'never writes the machine-wide PATH' {
        $script:Source | Should -Not -Match "SetEnvironmentVariable\([^)]*Machine"
        $script:Source | Should -Not -Match 'LocalMachine\.(Open|Create)SubKey'
    }

    It 'never runs downloaded code' {
        $script:Source | Should -Not -Match '(?i)Invoke-Expression|\biex\b|irm\s+[^|]*\|'
    }

    It 'never touches Git config, Claude Code settings, or Codex sign-in' {
        $script:Source | Should -Not -Match '(?i)git\s+config|\.gitconfig|settings\.json|codex\s+login|CLAUDE_CODE_GIT_BASH_PATH\s*='
    }

    It 'only runs tools to check --version' {
        $script:Source | Should -Not -Match '(?i)Start-Process'
        $script:Source | Should -Not -Match "&\s*['""]?(claude|codex)"
    }

    It 'takes no key or token parameter' {
        (Get-Command (Join-Path $PSScriptRoot '..\..\scripts\onboard.ps1')).Parameters.Keys | Should -Not -Match '(?i)key|token|secret|password'
    }

    It 'is plain ASCII so Windows PowerShell 5.1 reads it correctly' {
        $script:Source | Should -Not -Match '[^\x00-\x7F]'
    }
}
