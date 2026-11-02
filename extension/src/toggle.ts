import {
  LaunchType,
  environment,
  showHUD,
  updateCommandMetadata,
} from "@raycast/api";

import { EngineError, startDaemon, stopDaemon } from "./lib/engine";
import { formatSpeed } from "./lib/format";
import { getDaemonStatus, type DaemonStatus } from "./lib/rpc";

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function subtitleFor(status: DaemonStatus): string {
  if (status.state === "stopped") {
    return "⚪ Stopped · Click to start";
  }
  if (status.state === "error") {
    return "🔴 RPC error";
  }
  const counts = `${status.active} active · ${status.waiting} waiting`;
  if (status.state === "busy") {
    return `🟡 Busy · ${counts} · ${formatSpeed(status.downloadSpeed)}`;
  }
  return `🟢 Running · ${counts}`;
}

async function updateSubtitle(status: DaemonStatus): Promise<void> {
  try {
    await updateCommandMetadata({ subtitle: subtitleFor(status) });
  } catch {
    // Metadata updates are best-effort; the toggle must still work.
  }
}

export default async function Toggle() {
  if (environment.launchType === LaunchType.Background) {
    await updateSubtitle(await getDaemonStatus());
    return;
  }

  const current = await getDaemonStatus();
  try {
    if (current.state === "stopped") {
      await startDaemon();
      await showHUD("aria2 started");
    } else {
      await stopDaemon({ onlyIfIdle: true });
      await showHUD("aria2 stopped");
    }
  } catch (error) {
    const busy = error instanceof EngineError && error.code === 5;
    await showHUD(
      busy ? "aria2 is busy; stop refused" : `aria2: ${messageOf(error)}`,
    );
  }

  await updateSubtitle(await getDaemonStatus());
}
