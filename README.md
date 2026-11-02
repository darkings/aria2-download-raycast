# Aria2 Download · Raycast

Raycast 的 aria2 统一入口：直链、种子、BT/磁力、网盘（LinkSwift 推送）共用同一个 aria2 RPC 与任务队列。

> Status: scaffold. 代码尚未落地；本 README 先固定目标、架构和一期范围。

## Goals

- **直链**：HTTP / HTTPS / FTP，支持目录、重命名、16 连接、headers、校验和。
- **种子**：`.torrent` 文件（FilePicker / Finder 选中），多文件列表。
- **磁力 / BT**：`magnet:` 链接、DHT / PEX / LPD、端口、加密、做种策略。
- **网盘**：LinkSwift 油猴脚本把直链和 Cookie / Referer / UA 推送到同一个 RPC。
- **统一体验**：Tasks 看板、Chunk 进度图、aria2 配置、完成/错误 Toast。
- **Windows 优先**：Raycast 2.x（Windows），Node.js >= 22.22.2；不依赖 macOS。

## Architecture

```text
Raycast extension (TypeScript / React)
  ├─ Tasks / Task Detail       进度、Chunk 图、暂停/删除
  ├─ Add Download             URL / magnet / 剪贴板
  ├─ Add Torrent              .torrent / Finder
  ├─ Configuration            aria2 HTTP + BT 参数
  └─ Start / Stop             按需启停
        │ JSON-RPC 127.0.0.1:6800
        ▼
aria2c RPC daemon (PowerShell engine, hidden)
  ├─ HTTP/HTTPS/FTP
  ├─ .torrent / magnet / BT
  └─ LinkSwift netdisk direct links (headers forwarded)
        ▼
C:\Users\Jie\Downloads + session/log
```

一个 RPC、一个任务队列、一套 Chunk 图和完成通知；LinkSwift 只负责网盘取链与 headers。

## Planned layout

```text
engine/
  aria2.conf
  Initialize-Aria2.ps1       # 下载官方 1.37.0 + SHA-256，生成 secret/settings
  Start-Aria2Rpc.ps1
  Stop-Aria2Rpc.ps1
  Get-Aria2Settings.ps1
  Set-Aria2Settings.ps1
  Notify-Aria2.ps1           # hook -> Windows Toast
  Aria2Hook.vbs
  tests/
extension/
  package.json
  src/tasks.tsx
  src/task-detail.tsx
  src/add-download.tsx
  src/add-torrent.tsx
  src/configuration.tsx
  src/start.ts
  src/stop.ts
  src/lib/aria2.ts
  src/lib/bitfield.ts
  src/lib/torrent.ts
  src/lib/netdisk.ts
  src/lib/task-type.ts
  src/lib/engine-settings.ts
  src/lib/format.ts
  scripts/sync-engine.js
```

## Planned commands

| Command | Mode | Description |
| --- | --- | --- |
| Tasks | view | Unified list: HTTP / BT / Magnet / Netdisk, speed, ETA, progress |
| Task Detail | view | Chunk grid, files, pause/resume/remove/open folder |
| Add Download | view | URL / magnet / clipboard, advanced headers, netdisk guard |
| Add Torrent | view | `.torrent` file picker or Finder selection |
| Configuration | view | aria2 HTTP + BT settings, validation, restart |
| Start aria2 | no-view | Hidden start + RPC check |
| Stop aria2 | no-view | Idle-only stop with confirmation |

## Chunk map: adaptive to the Raycast window

Raycast does not expose the Raycast window dimensions to extensions (`environment` only exposes appearance / text size; `MenuBarExtra` is macOS-only; `Grid.columns` is capped at 8). A fixed markdown grid cannot truly reflow.

Planned approach:

1. **Window watcher** (Windows helper): a long-lived PowerShell helper uses Win32 `GetForegroundWindow` / `GetClientRect` (P/Invoke) to report the Raycast client size as JSON lines on change. No admin rights.
2. **Grid sizing**: `columns = clamp(floor((clientWidth - padding) / cellWidth), 16, 64)`, `rows = clamp(floor((clientHeight - header) / cellHeight), 6, 20)`; `cellWidth/cellHeight` depend on `environment.textSize`.
3. **Aggregation**: `aria2.tellStatus` returns `bitfield` (hex; highest bit = piece 0), `numPieces`, `pieceLength`; aggregate pieces into `columns × rows` cells without expanding the full bit array. Cell states: `🟩` complete, `🟨` partial, `⬜` missing.
4. **Rendering**: `Detail` markdown grid with hard line breaks; poll bitfield every 1s while Detail is open; regenerate only when bitfield or window size changes.
5. **Fallback**: if the native watcher fails, use a `chunkColumns` preference (default 40×12) and `environment.textSize`; never block the task detail on window measurement.
6. **Limits**: `numPieces > 200k` → 2s polling; `> 2M` → byte-progress fallback. The map reflects piece completion, not per-connection offsets.

## aria2 configuration

`Configuration` edits aria2 engine settings, not Raycast UI preferences:

- **Download**: dir, split, max-connection-per-server, min-split-size, max-concurrent-downloads, file-allocation, disk-cache.
- **Limits**: max-overall-download-limit, max-overall-upload-limit.
- **Network**: proxy mode (system/direct/custom), all-proxy, no-proxy, check-certificate (default on), timeouts/retries.
- **RPC**: rpc-port; rpc-secret controlled; `rpc-listen-all=false`, `rpc-allow-origin-all=true` fixed.
- **BT**: listen/dht ports, DHT/PEX/LPD, max peers, encryption, seed-time/ratio, upload limit, metadata save/load, tracker list.
- **Session / notifications**: save-session-interval, hook on/off.

Canonical config is `engine/settings.json`; `Start-Aria2Rpc.ps1` generates the runtime conf. Changes that require a restart show a “restart to apply” state; never auto-restart while downloads are active.

## BT defaults

```ini
listen-port=6881
dht-listen-port=6881
enable-dht=true
enable-peer-exchange=true
bt-enable-lpd=false
bt-max-peers=55
seed-time=0
seed-ratio=1.0
max-overall-upload-limit=2M
bt-save-metadata=true
bt-load-saved-metadata=true
rpc-save-upload-metadata=true
```

- Seeding is disabled by default; enabling it is user opt-in.
- BT needs inbound ports for best peer count; firewall/router forwarding is optional and never automatic.
- Only download/share content you have the right to.
- `rpc-listen-all` stays false; never expose the RPC port to LAN/Internet.

## Roadmap

- [ ] P1 engine: init / start / stop / settings (HTTP + BT) / hooks
- [ ] P2 tasks + adaptive chunk detail
- [ ] P3 add download + add torrent
- [ ] P4 aria2 configuration (HTTP + BT)
- [ ] P5 LinkSwift netdisk verification, notifications, docs
- [ ] P6 optional: torrent file selection, tracker update, magnet protocol handler, Store publish

## Development

- Raycast for Windows 2.x; Node.js >= 22.22.2.
- `extension/`: `npm install`, `npm run dev` (`ray develop`), `npm run build`.
- `engine/`: PowerShell 5.1 scripts; offline unit tests must not download aria2 or hit the network.
- No aria2 binary is committed; the engine downloads the official pinned ZIP and verifies SHA-256.

## License

MIT. See [LICENSE](LICENSE).

## Related

- [aria2 manual](https://aria2.github.io/manual/en/html/aria2c.html)
- [LinkSwift](https://github.com/hmjz100/LinkSwift)
- [Raycast API](https://developers.raycast.com/)
