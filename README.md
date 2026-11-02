# Cursor proxy (PowerShell, Windows laptop)

Format per line: `host:port:username:password`

## Setup

1. Copy this folder to your laptop (or clone repo).
2. Edit `proxies.txt` (already gitignored).

## Commands (PowerShell)

```powershell
cd path\to\cursor-proxy

# Test all proxies (shows exit IP each)
.\cursor-proxy-launch.ps1 -TestAll

# Use proxy #0 — test + set env for this window
.\cursor-proxy-launch.ps1 -Index 0

# Open Edge/Chrome to authenticator (Tampermonkey login)
.\cursor-proxy-launch.ps1 -Index 0 -OpenBrowser

# Start Cursor with HTTP_PROXY in this session
.\cursor-proxy-launch.ps1 -Index 1 -LaunchCursor
```

Rotate index `0..6` for each account in your login queue.

**Security:** Do not commit `proxies.txt`. Rotate passwords if they were shared in chat.
