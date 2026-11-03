# Aria2 Download · Raycast

Raycast 的 aria2 统一入口：直链、种子、BT/磁力、网盘（LinkSwift 推送）共用同一个 aria2 RPC 与任务队列。

- **Extension**：TypeScript / React，Windows-only，Raycast 2.x。
- **Engine**：PowerShell 5.1，自动发现系统 aria2，自动生成配置、启停与完成通知。
- **状态**：可用；engine 离线测试 45/45 通过；extension 通过 typecheck / lint / build；已完成 Raycast UI 实测（Tasks、详情 PNG 热力图、统一 Add Download、Configuration、Toggle Aria2）及本机直链下载、torrent 添加、watcher 完成/错误通知实测。

## 功能

- **直链**：HTTP / HTTPS / FTP；目录、重命名、16 连接、headers、校验和。
- **种子**：`.torrent` 文件选择器或 Explorer 选中文件；多文件任务。
- **磁力 / BT**：`magnet:` 链接；DHT / PEX / LPD、端口、加密、做种策略。
- **网盘**：LinkSwift 油猴脚本把直链与 Cookie / Referer / UA 推送到同一个 RPC。
- **统一体验**：Tasks 看板、Chunk 热力图、aria2 配置、完成/错误 Toast。
- **按需启停**：不做开机自启；Raycast 根搜索只保留一个 **Toggle Aria2**，subtitle 显示当前 Running/Stopped/Busy 状态。

## 快速开始

### 1. 安装 aria2（唯一前置条件）

```powershell
winget install aria2.aria2
# 或
scoop install aria2
```

也可以从 <https://aria2.github.io/> 下载官方 Windows ZIP，并把 `aria2c.exe` 放进 PATH 或常见安装目录。

Extension 会自动查找已安装的 `aria2c.exe`，首次启动时自动生成 `settings.json`、`rpc-secret.txt` 和 runtime conf，**不需要再运行 Initialize-Aria2.ps1，也不需要额外配置**。

如果找不到 aria2，Raycast 会弹出提示；确认后会打开 aria2 官网。

### 2. 启动 Raycast 扩展

```powershell
cd extension
npm install
npm run dev       # Raycast dev extension；或 npm run build 后导入
```

### 3. Raycast 命令

| 命令 | 作用 |
| --- | --- |
| **Aria2 Tasks** | 统一任务列表；进度、速度、ETA、暂停/删除/打开目录 |
| **Add Download** | 一个入口：URL / magnet / `.torrent` 文件；目录、连接数、headers、做种 |
| **Aria2 Configuration** | aria2 HTTP + BT + RPC + 通知设置 |
| **Toggle Aria2** | Start/Stop 切换；subtitle 显示 `🟢 Running` / `🟡 Busy` / `⚪ Stopped`，后台每分钟刷新 |

### 4. LinkSwift

在 LinkSwift 的 Aria2/RPC 设置中填写：

- domain：`http://127.0.0.1`
- port：`6800`（或 Configuration 里的 RPC 端口）
- path：`/jsonrpc`
- token：`rpc-secret.txt` 里的原始 secret（**不要加 `token:`**）
- dir：留空

网盘直链的 Cookie / Referer / User-Agent 由 LinkSwift 传入；**不要把网盘直链手动粘到 Add Download**，它大概率 403/412。

## Chunk 视图

Raycast 不提供 Raycast 窗口尺寸 API，因此这里采用**固定版式**，不测量窗口：

- **PNG Heatmap（默认）**：48×12 圆角方块，按分片完成度从灰→黄→绿渐变；由 Node `zlib` 直接编码 PNG 写入 `environment.supportPath`，通过 `Detail` markdown 本地图片展示；窗口变宽时图片整体缩放，不重排列数。
- **Native Mosaic（fallback）**：Raycast `Grid` 8 列色块，不依赖运行时图片；在扩展偏好 **Chunk View** 切换。
- **限制**：`bitfield` 表示分片完成度，不是每条连接当前下载偏移；磁力元数据阶段没有 `bitfield`；超大分片数会回退字节进度。

## Engine

```text
engine/
  aria2.conf                 # 运行时 conf 模板（占位符）
  Aria2Common.ps1            # 设置/校验/runtime conf/RPC/日志/Toast
  Initialize-Aria2.ps1       # 可选：下载并安装 pinned aria2（普通用户装好 aria2 后不需要）
  Start-Aria2Rpc.ps1         # 隐藏启动 + RPC 就绪校验
  Stop-Aria2Rpc.ps1          # 空闲检查 + 优雅/强制停止
  Get-Aria2Settings.ps1      # -Json 输出 settings
  Set-Aria2Settings.ps1      # 校验、原子写、重建 runtime conf
  Notify-Aria2.ps1           # 手动/兼容用的 Toast helper
  Watch-Aria2.ps1            # 隐藏完成/错误 watcher（实际通知路径）
  Aria2Hook.vbs              # 旧 hook shim（aria2 1.37 Windows 上不可靠，默认不启用）
  tests/Aria2Common.Tests.ps1
```

运行时状态：

```text
%LOCALAPPDATA%\lat3ncy-toolbox\aria2\
  install.json
  settings.json
  rpc-secret.txt
  aria2.runtime.conf
  session.txt
  watch.pid
  aria2.log
  rpc.log
```

`settings.json` 是 aria2 配置的权威来源；`Configuration` 命令写它，`Toggle Aria2` 启动时生成 runtime conf。RPC 只监听 loopback，`rpc-listen-all=false`。

### BT 默认值

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

- 默认不做种；需要私有 tracker 保种时在 Configuration 里提高 `seed-time`。
- BT 下载过程中仍会上传；只下载/分享有权限的内容。
- 无公网入站端口/NAT 时 peer 较少、速度受限；首次启动 aria2 可能弹 Windows 防火墙，端口转发/放行需手动，engine 不自动提权。

### 完成通知

- `Start-Aria2Rpc.ps1` 同时启动隐藏的 `Watch-Aria2.ps1`，每 3 秒轮询 RPC。
- 任务进入 `complete` / `error` 时发 Windows Toast；`Stop` 会结束 watcher。
- aria2 1.37.0 Windows 的 `on-download-*` hook 在本机实测会 `CreateProcess() failed`，因此默认不写 hook 配置；watcher 是实际通知路径。
- 通知在扩展关闭后仍有效；扩展本身不做后台轮询。

## 开发与验证

```powershell
# engine
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tests\Aria2Common.Tests.ps1

# extension
cd extension
npm run typecheck
npm run lint
npm run build
```

扩展开发模式：

```powershell
cd extension
npm run dev
```

## 结构

```text
engine/       PowerShell 引擎（安装/配置/启停/通知）
extension/    Raycast 扩展（Tasks/Add/Configuration）
docs/         Engine ⇄ Extension contract
```

## 已知限制

- Windows 版 Raycast 不支持 MenuBarExtra；扩展关闭后由隐藏的 `Watch-Aria2.ps1` 轮询 RPC 发送完成/错误 Toast。
- 扩展关闭后不会继续轮询任务；需要看进度时重新打开 Tasks。
- Chunk 热力图是固定版式，不按窗口重排列数；窄窗会整体缩小。
- 网盘 403/412 属于 LinkSwift 的 headers / 直链时效问题，不是 aria2 配置问题。
- 本仓库不提交 aria2 二进制；默认使用用户已安装的 `aria2c.exe`。`Initialize-Aria2.ps1` 仅作为可选的 pinned 下载/离线安装 fallback。

## License

MIT。见 [LICENSE](LICENSE)。

## Related

- [aria2 manual](https://aria2.github.io/manual/en/html/aria2c.html)
- [LinkSwift](https://github.com/hmjz100/LinkSwift)
- [Raycast API](https://developers.raycast.com/)
