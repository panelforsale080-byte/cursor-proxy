#Requires -Version 5.1
<#
.SYNOPSIS
  Test FloppyData-style proxies and open browser for Cursor login (PowerShell).

.DESCRIPTION
  Line format: host:port:username:password
  Stores secrets only in proxies.txt (gitignored). Do not commit proxies.txt.

.EXAMPLE
  cd cursor-proxy
  .\cursor-proxy-launch.ps1 -TestAll
  .\cursor-proxy-launch.ps1 -Index 0 -OpenBrowser
  .\cursor-proxy-launch.ps1 -Index 0 -LaunchCursor
#>
param(
    [int]$Index = 0,
    [switch]$TestAll,
    [switch]$OpenBrowser,
    [switch]$LaunchCursor,
    [string]$ProxiesFile = (Join-Path $PSScriptRoot 'proxies.txt'),
    [string]$TestUrl = 'https://api.ipify.org?format=json'
)

function Parse-ProxyLine {
    param([string]$Line)
    $Line = $Line.Trim()
    if (-not $Line -or $Line.StartsWith('#')) { return $null }
    $parts = $Line -split ':', 4
    if ($parts.Count -lt 4) {
        Write-Warning "Skip invalid line (need host:port:user:pass): $Line"
        return $null
    }
    return [pscustomobject]@{
        Host     = $parts[0]
        Port     = $parts[1]
        User     = $parts[2]
        Pass     = $parts[3]
        ProxyUri = "http://$($parts[0]):$($parts[1])"
    }
}

function Get-ProxyList {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Missing $Path - create proxies.txt in the same folder as this script (host:port:user:pass per line)."
    }
    Get-Content -LiteralPath $Path | ForEach-Object { Parse-ProxyLine $_ } | Where-Object { $_ }
}

function Test-ProxyEntry {
    param($Entry)
    $proxy = New-Object System.Net.WebProxy($Entry.ProxyUri, $true)
    $proxy.Credentials = New-Object System.Net.NetworkCredential($Entry.User, $Entry.Pass)
    try {
        $resp = Invoke-WebRequest -Uri $TestUrl -Proxy $proxy -ProxyUseDefaultCredentials:$false -TimeoutSec 25 -UseBasicParsing
        $ip = ($resp.Content | ConvertFrom-Json).ip
        if (-not $ip) { $ip = $resp.Content.Trim() }
        return [pscustomobject]@{ Ok = $true; Ip = $ip; Error = $null }
    } catch {
        return [pscustomobject]@{ Ok = $false; Ip = $null; Error = $_.Exception.Message }
    }
}

function Set-SessionProxyEnv {
    param($Entry)
    $userEnc = [uri]::EscapeDataString($Entry.User)
    $passEnc = [uri]::EscapeDataString($Entry.Pass)
    $url = "http://${userEnc}:${passEnc}@$($Entry.Host):$($Entry.Port)"
    $env:HTTP_PROXY = $url
    $env:HTTPS_PROXY = $url
    $env:http_proxy = $url
    $env:https_proxy = $url
    $env:NO_PROXY = 'localhost,127.0.0.1'
    Write-Host "HTTP_PROXY set for this PowerShell session only."
}

function Find-Edge {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Find-Chrome {
    $candidates = @(
        "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Open-BrowserWithProxy {
    param($Entry)
    $loginUrl = 'https://authenticator.cursor.sh/'
    $server = $Entry.ProxyUri
    $edge = Find-Edge
    $chrome = Find-Chrome
    if ($edge) {
        Write-Host "Opening Edge with proxy $server (auth may prompt once)..."
        Start-Process -FilePath $edge -ArgumentList @(
            "--proxy-server=$server",
            '--new-window',
            $loginUrl
        )
        Write-Host "If login fails, enter proxy user/pass when prompted:"
        Write-Host "  User: $($Entry.User)"
        return
    }
    if ($chrome) {
        Write-Host "Opening Chrome with proxy $server..."
        Start-Process -FilePath $chrome -ArgumentList @(
            "--proxy-server=$server",
            '--new-window',
            $loginUrl
        )
        Write-Host "If prompted for proxy auth: $($Entry.User)"
        return
    }
    throw 'Edge/Chrome not found. Install a Chromium browser or set HTTP_PROXY and open browser manually.'
}

function Launch-CursorWithProxy {
    param($Entry)
    Set-SessionProxyEnv -Entry $Entry
    $cursorPaths = @(
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:LOCALAPPDATA\cursor\Cursor.exe"
    )
    $exe = $cursorPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) { throw 'Cursor.exe not found. Start Cursor from Start menu after running Set-SessionProxyEnv in same shell.' }
    Write-Host "Starting Cursor from this shell (inherits HTTP_PROXY)..."
    Start-Process -FilePath $exe
}

$list = @(Get-ProxyList -Path $ProxiesFile)
if ($list.Count -eq 0) { throw 'No proxies in file.' }

if ($TestAll) {
    $i = 0
    foreach ($p in $list) {
        $r = Test-ProxyEntry -Entry $p
        if ($r.Ok) {
            Write-Host ("[{0}] OK  {1}:{2}  user={3}  IP={4}" -f $i, $p.Host, $p.Port, $p.User, $r.Ip)
        } else {
            Write-Host ("[{0}] FAIL {1}:{2}  user={3}  {4}" -f $i, $p.Host, $p.Port, $p.User, $r.Error) -ForegroundColor Red
        }
        $i++
    }
    exit 0
}

if ($Index -lt 0 -or $Index -ge $list.Count) {
    throw "Index $Index out of range (0..$($list.Count - 1))"
}

$entry = $list[$Index]
Write-Host ("Using proxy [{0}] {1}:{2} user={3}" -f $Index, $entry.Host, $entry.Port, $entry.User)

$r = Test-ProxyEntry -Entry $entry
if ($r.Ok) {
    Write-Host "Proxy test OK - exit IP: $($r.Ip)" -ForegroundColor Green
} else {
    Write-Host "Proxy test FAILED: $($r.Error)" -ForegroundColor Yellow
}

Set-SessionProxyEnv -Entry $entry

if ($OpenBrowser) {
    Open-BrowserWithProxy -Entry $entry
}
if ($LaunchCursor) {
    Launch-CursorWithProxy -Entry $entry
}

if (-not $OpenBrowser -and -not $LaunchCursor) {
    Write-Host @"

Next:
  .\cursor-proxy-launch.ps1 -Index $Index -OpenBrowser     # login in browser (Tampermonkey)
  .\cursor-proxy-launch.ps1 -Index $Index -LaunchCursor   # Cursor IDE via proxy env
  .\cursor-proxy-launch.ps1 -TestAll                      # test every line

Tampermonkey does not set proxy - use this script or VPN for the browser.
"@ 
}
