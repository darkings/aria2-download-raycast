# Aria2 Download · extension

Raycast extension for the local aria2 engine in `../engine`.

## Development

```powershell
cd extension
npm install
npm run dev       # ray develop, dev extension appears in Raycast
npm run typecheck
npm run lint
npm run build
```

`predev` / `prebuild` copy `../engine` into `assets/engine` so the extension is self-contained at runtime. The copied engine is ignored by git.

## Commands

- **Aria2 Tasks** — unified list for direct URLs, torrents, magnet/BT and LinkSwift netdisk tasks.
- **Add Download** — URLs or magnet links, directory, connections, advanced headers.
- **Add Torrent** — local `.torrent` or Explorer-selected torrent file.
- **Aria2 Configuration** — aria2 settings (HTTP + BT), saved to `settings.json`.
- **Start / Stop aria2** — explicit daemon lifecycle; no background daemon.

## Chunk view

- **SVG Heatmap** (default): fixed 48×12 rounded-cell heatmap written to `environment.supportPath`; it scales as a whole with the Raycast window. It does not measure the window or reflow columns.
- **Native Mosaic**: Raycast `Grid` fallback, 8 columns of color blocks; no image dependency.
- Switch with the **Chunk View** preference.

The map is piece completion from aria2's `bitfield`, not per-connection offsets.

## Runtime state

The engine keeps state under `%LOCALAPPDATA%\lat3ncy-toolbox\aria2`:

```text
install.json
settings.json
rpc-secret.txt
aria2.runtime.conf
session.txt
aria2.log
rpc.log
```

The extension reads `settings.json` and `rpc-secret.txt`; connection preferences can override the endpoint/secret for a remote RPC.

## Engine setup

The extension does not download aria2 by itself. Run `engine\Initialize-Aria2.ps1` once from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\engine\Initialize-Aria2.ps1
```

Then start aria2 with the **Start Aria2** command.

## LinkSwift

LinkSwift pushes netdisk direct links to the same RPC endpoint. Do not paste netdisk direct links into Add Download: the missing Cookie/Referer/User-Agent will usually return 403/412. Add Download detects netdisk domains and redirects you to LinkSwift.

## License

MIT. See the repository root `LICENSE`.
