<#
.SYNOPSIS
    Checks that the guide page's commands match the README, and that the page's
    Content-Security-Policy hashes match its inline script and style.

.PARAMETER UpdateCsp
    Rewrite the page's CSP hashes to match its current inline script and style.
#>
param([switch]$UpdateCsp)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pagePath = Join-Path $root 'docs\index.html'
$readmePath = Join-Path $root 'README.md'
$problems = New-Object System.Collections.Generic.List[string]

function Get-Normalized {
    param([string]$Text)
    return (($Text -replace "`r`n", "`n").Trim("`n") -split "`n" | ForEach-Object { $_.TrimEnd() }) -join "`n"
}

function Get-InlineHash {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [Convert]::ToBase64String($sha.ComputeHash($bytes)) } finally { $sha.Dispose() }
}

$page = [System.IO.File]::ReadAllText($pagePath) -replace "`r`n", "`n"
$readme = [System.IO.File]::ReadAllText($readmePath) -replace "`r`n", "`n"

$pageCmds = @{}
foreach ($m in [regex]::Matches($page, '(?s)<pre data-cmd="([^"]+)">(.*?)</pre>(\s*<button class="copy")?')) {
    $id = $m.Groups[1].Value
    $text = [System.Net.WebUtility]::HtmlDecode(($m.Groups[2].Value -replace '<[^>]+>', ''))
    if ($pageCmds.ContainsKey($id)) { $problems.Add("The page has more than one command with id '$id'.") }
    $pageCmds[$id] = Get-Normalized $text
    if (-not $m.Groups[3].Success) { $problems.Add("The page's '$id' command has no copy button.") }
}
if ($pageCmds.Count -eq 0) { $problems.Add('No commands were found on the page.') }

$readmeCmds = @{}
foreach ($m in [regex]::Matches($readme, '(?s)<!-- cmd: ([\w-]+) -->\s*\n```[\w-]*\n(.*?)\n```')) {
    $id = $m.Groups[1].Value
    if ($readmeCmds.ContainsKey($id)) { $problems.Add("The README has more than one command marked '$id'.") }
    $readmeCmds[$id] = Get-Normalized $m.Groups[2].Value
}

foreach ($id in $pageCmds.Keys) {
    if (-not $readmeCmds.ContainsKey($id)) {
        $problems.Add("The page's '$id' command is missing from the README.")
    } elseif ($readmeCmds[$id] -cne $pageCmds[$id]) {
        $problems.Add("The '$id' command differs.`n  page:   $($pageCmds[$id])`n  README: $($readmeCmds[$id])")
    }
}
foreach ($id in $readmeCmds.Keys) {
    if (-not $pageCmds.ContainsKey($id)) { $problems.Add("The README's '$id' command is missing from the page.") }
}

if ($page -match '(?i)<(script|link|img|iframe|object|embed|source|video|audio)\b[^>]*\b(src|href)=') {
    $problems.Add('The page loads a resource. It must not load anything.')
}
if ($page -match '(?i)\b(fetch|XMLHttpRequest|sendBeacon|document\.cookie|localStorage|sessionStorage)\b') {
    $problems.Add('The page makes requests or stores data. It must only show commands.')
}

$script = [regex]::Match($page, '(?s)<script>(.*?)</script>')
$style = [regex]::Match($page, '(?s)<style>(.*?)</style>')
if (([regex]::Matches($page, '<script')).Count -ne 1 -or ([regex]::Matches($page, '<style')).Count -ne 1) {
    $problems.Add('The page must have exactly one inline script and one inline style.')
}
if ($page -match '(?i)\sstyle="|\son\w+="') {
    $problems.Add('The page uses inline style or event attributes, which its CSP blocks.')
}
$scriptHash = Get-InlineHash $script.Groups[1].Value
$styleHash = Get-InlineHash $style.Groups[1].Value
$csp = [regex]::Match($page, '<meta http-equiv="Content-Security-Policy" content="([^"]+)">')
$wantCsp = "default-src 'none'; script-src 'sha256-$scriptHash'; style-src 'sha256-$styleHash'; base-uri 'none'; form-action 'none'"

if ($UpdateCsp) {
    $updated = $page.Replace($csp.Groups[1].Value, $wantCsp)
    [System.IO.File]::WriteAllText($pagePath, $updated, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Updated the CSP hashes.'
} elseif ($csp.Groups[1].Value -ne $wantCsp) {
    $problems.Add("The page's CSP does not match its inline code. Run: tests\check-guide-commands.ps1 -UpdateCsp")
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "FAIL: $p" }
    exit 1
}
Write-Host "OK: $($pageCmds.Count) guide commands match the README, and the CSP matches the page."
exit 0
