# Engine ⇄ Extension Contract

This file is the interface between the PowerShell engine and the Raycast extension. Both sides must match it exactly.

## Runtime paths

Everything lives under:

```text
%LOCALAPPDATA%\lat3ncy-toolbox\aria2\
  install.json              # { version, sha256, installPath, installedAt }
  settings.json             # canonical aria2 settings (see schema)
  rpc-secret.txt            # raw secret, no "token:" prefix
  aria2.runtime.conf        # generated from aria2.conf + settings + secret
  session.txt
  aria2.log
  rpc.log
  bin\1.37.0\aria2c.exe     # default portable install
```

`settings.json` is the source of truth. The extension reads it directly; the engine writes it through `Set-Aria2Settings.ps1`.

## Engine scripts (called by the extension)

All scripts are Windows PowerShell 5.1, no admin, no console window when invoked hidden.

| Script | Invocation | Behaviour |
| --- | --- | --- |
| `Initialize-Aria2.ps1` | `-NoToast -DownloadDir <dir> -Connections 16 -Port 6800` | Optional fallback: download pinned aria2 1.37.0, verify SHA-256, create settings/secret/runtime conf. Normal installs use the system aria2 detected by Start. |
| `Start-Aria2Rpc.ps1` | `-NoToast` | Idempotent: if RPC already responds, exit 0. Else find system aria2, generate defaults/runtime conf, start `aria2c` hidden, wait for `aria2.getVersion`. |
| `Stop-Aria2Rpc.ps1` | `-OnlyIfIdle -NoToast` | Graceful `aria2.shutdown`; refuse if active/waiting unless `-Force`. |
| `Get-Aria2Settings.ps1` | `-Json` | Print settings JSON to stdout. No secret. |
| `Set-Aria2Settings.ps1` | `-JsonPath <temp.json>` | Validate, atomically write settings, regenerate runtime conf; print result JSON `{ok:true,restartRequired:bool}`. |
| `Watch-Aria2.ps1` | `-IntervalSeconds 3 -NoToast -Once -DryRun` | Hidden completion/error watcher started by Start; polls `tellStopped`, writes dedupe markers, shows Windows Toast. |
| `Notify-Aria2.ps1` | `-Gid <gid> -Event download|bt|error` | Manual/compatibility Toast helper; aria2 hooks are not enabled by default. |
| `Aria2Hook.vbs` | legacy | Optional hidden shim for systems where aria2 hooks work; not referenced by generated runtime conf. |

Exit codes: `0` success, `2` invalid input/config, `3` aria2 missing, `4` RPC/start failure, `5` busy/active downloads (stop refused), `6` download/install failure.

## settings.json schema

```json
{
  "rpcPort": 6800,
  "downloadDir": "C:\\Users\\Jie\\Downloads",
  "connections": 16,
  "split": 16,
  "minSplitSize": "1M",
  "maxConcurrentDownloads": 3,
  "fileAllocation": "none",
  "diskCache": "64M",
  "maxOverallDownloadLimit": "0",
  "maxOverallUploadLimit": "2M",
  "proxyMode": "system",
  "allProxy": "",
  "noProxy": "",
  "checkCertificate": true,
  "connectTimeout": 30,
  "timeout": 60,
  "maxTries": 3,
  "retryWait": 5,
  "lowestSpeedLimit": "0",
  "saveSessionInterval": 30,
  "notifications": true,
  "listenPort": 6881,
  "dhtListenPort": 6881,
  "enableDht": true,
  "enablePeerExchange": true,
  "btEnableLpd": false,
  "btMaxPeers": 55,
  "btRequireCrypto": false,
  "seedTime": 0,
  "seedRatio": 1.0,
  "btSaveMetadata": true,
  "btLoadSavedMetadata": true,
  "rpcSaveUploadMetadata": true,
  "btTracker": ""
}
```

Validation ranges:

- `rpcPort`: 1024–65535
- `connections`, `split`: 1–16
- `minSplitSize`: `1M`–`1024M`
- `maxConcurrentDownloads`: 1–10
- `fileAllocation`: `none` | `prealloc`
- `diskCache`: 16M–1024M
- `proxyMode`: `system` | `direct` | `custom`
- `listenPort`, `dhtListenPort`: 1024–65535
- `seedTime`: 0–100000
- `seedRatio`: 0–100
- `btMaxPeers`: 1–1000
- `saveSessionInterval`: 10–300

`rpcSecret` is NOT in settings.json; it lives in `rpc-secret.txt`. The extension never writes it in phase 1.

## aria2 options mapping

- `dir=downloadDir`
- `split`, `max-connection-per-server` = `split` / `connections` (both 1–16)
- `min-split-size`, `max-concurrent-downloads`, `file-allocation`, `disk-cache`
- `max-overall-download-limit`, `max-overall-upload-limit`
- `connect-timeout`, `timeout`, `max-tries`, `retry-wait`, `lowest-speed-limit`
- `listen-port`, `dht-listen-port`, `enable-dht`, `enable-peer-exchange`, `bt-enable-lpd`, `bt-max-peers`, `bt-require-crypto`, `seed-time`, `seed-ratio`
- `bt-save-metadata`, `bt-load-saved-metadata`, `rpc-save-upload-metadata`
- `bt-tracker` only when non-empty
- `save-session`, `save-session-interval`, `force-save=false`
- `log`, `log-level=warn`, `console-log-level=warn`, `summary-interval=0`
- `enable-rpc=true`, `rpc-listen-all=false`, `rpc-allow-origin-all=true`, `rpc-listen-port`, `rpc-secret`
- `content-disposition-default-utf8=true`, `remote-time=true`, `check-certificate`
- `proxyMode=system`: do not write proxy options (inherit env)
- `proxyMode=direct`: Start adds `--all-proxy=` to the aria2 args
- `proxyMode=custom`: `all-proxy=allProxy`, `no-proxy=noProxy`

## Extension responsibilities

- Reads state paths directly (Node `fs`), secret from `rpc-secret.txt`.
- RPC calls to `http://127.0.0.1:<rpcPort>/jsonrpc` with `token:<secret>`.
- Engine scripts are bundled into `extension/assets/engine` by `scripts/sync-engine.js`.
- Engine path at runtime: `path.join(environment.assetsPath, "engine", "<script>.ps1")`.
- Invoke PowerShell with `windowsHide: true`, `-NoProfile -ExecutionPolicy Bypass -File`.
- Do not log or display the secret.
- No background daemon: Start/Stop are explicit commands.

## BT defaults

- `seed-time=0` (no seeding by default)
- `seed-ratio=1.0` (only relevant if seed-time > 0)
- DHT/PEX on; LPD off
- `listen-port/dht-listen-port=6881`
- `max-overall-upload-limit=2M`
- `rpc-save-upload-metadata=true` so `.torrent` tasks survive session restore

## Completion notifications

- `Start-Aria2Rpc.ps1` starts `Watch-Aria2.ps1` as a hidden process (pid in `watch.pid`).
- Watcher polls `aria2.tellStopped` every 3s; on new `complete` / `error` it shows a Toast and writes a marker under `notified/`.
- `Stop-Aria2Rpc.ps1` stops the watcher; a stale pid file is ignored/removed.
- aria2 `on-download-*` hooks are intentionally not generated on Windows: aria2 1.37.0 x64 can fail `CreateProcess()` for user commands on this host.
- `Notify-Aria2.ps1` / `Aria2Hook.vbs` remain as manual/legacy helpers.

## Chunk visualisation

- Primary: fixed 48×12 PNG heatmap generated by the extension (Node zlib, no native dependency); no window measurement.
- Fallback: Raycast native `Grid` mosaic, 8 columns.
- Bitfield: hex string; highest bit = piece 0; omit when not started.
- Poll `tellStatus` every 1s while the detail view is open; stop on unmount.
- The map is piece completion, not per-connection offsets.
