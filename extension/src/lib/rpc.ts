import { getPreferenceValues } from "@raycast/api";

import {
  Aria2Settings,
  Aria2Task,
  Aria2Version,
  ExtensionPreferences,
  GlobalStat,
} from "./types";
import { loadSettings, readSecret } from "./state";
import { startDaemon } from "./engine";

export class RpcError extends Error {
  readonly code?: number;

  constructor(message: string, code?: number) {
    super(message);
    this.name = "RpcError";
    this.code = code;
  }
}

interface RpcResponse<T> {
  jsonrpc?: string;
  id?: string | number;
  result?: T;
  error?: { code?: number; message?: string };
}

export interface Aria2Connection {
  endpoint: string;
  secret: string | null;
  settings: Aria2Settings;
}

function getPreferences(): ExtensionPreferences {
  return getPreferenceValues<ExtensionPreferences>();
}

export async function getConnection(): Promise<Aria2Connection> {
  const preferences = getPreferences();
  const settings = await loadSettings();
  if (!settings) {
    throw new RpcError(
      "aria2 engine is not initialized. Run the engine Initialize-Aria2.ps1 first.",
      2,
    );
  }
  const endpoint =
    preferences.rpcEndpoint?.trim() ||
    `http://127.0.0.1:${settings.rpcPort}/jsonrpc`;
  const secret = preferences.rpcSecret?.trim() || (await readSecret());
  return { endpoint, secret, settings };
}

async function rpc<T>(method: string, params: unknown[] = []): Promise<T> {
  const { endpoint, secret } = await getConnection();
  const requestParams = secret ? [`token:${secret}`, ...params] : params;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5_000);

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        jsonrpc: "2.0",
        id: `aria2-raycast-${Date.now()}-${Math.random().toString(16).slice(2)}`,
        method,
        params: requestParams,
      }),
      signal: controller.signal,
    });

    if (response.status === 401) {
      throw new RpcError(
        "aria2 RPC unauthorized: the secret does not match.",
        401,
      );
    }
    if (!response.ok) {
      throw new RpcError(`aria2 RPC HTTP ${response.status}`, response.status);
    }

    const payload = (await response.json()) as RpcResponse<T>;
    if (payload.error) {
      throw new RpcError(
        payload.error.message ??
          `aria2 RPC error ${payload.error.code ?? ""}`.trim(),
        payload.error.code,
      );
    }
    if (payload.result === undefined) {
      throw new RpcError("aria2 RPC returned no result");
    }
    return payload.result;
  } catch (error) {
    if (error instanceof RpcError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new RpcError("aria2 RPC timed out");
    }
    throw new RpcError(
      error instanceof Error ? error.message : "aria2 RPC failed",
    );
  } finally {
    clearTimeout(timeout);
  }
}

export async function getVersion(): Promise<Aria2Version> {
  return rpc<Aria2Version>("aria2.getVersion");
}

export async function isDaemonRunning(): Promise<boolean> {
  try {
    await getVersion();
    return true;
  } catch {
    return false;
  }
}

export async function ensureDaemon(): Promise<void> {
  const preferences = getPreferences();
  if (await isDaemonRunning()) return;
  if (!preferences.autoStartDaemon) {
    throw new RpcError(
      "aria2 RPC is not running. Start it with the Start Aria2 command.",
      4,
    );
  }
  await startDaemon();
  for (let attempt = 0; attempt < 15; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 300));
    if (await isDaemonRunning()) return;
  }
  throw new RpcError("aria2 RPC did not become ready after starting.", 4);
}

export async function getGlobalStat(): Promise<GlobalStat> {
  return rpc<GlobalStat>("aria2.getGlobalStat");
}

export async function tellActive(): Promise<Aria2Task[]> {
  return rpc<Aria2Task[]>("aria2.tellActive");
}

export async function tellWaiting(
  offset = 0,
  num = 1000,
): Promise<Aria2Task[]> {
  return rpc<Aria2Task[]>("aria2.tellWaiting", [offset, num]);
}

export async function tellStopped(
  offset = 0,
  num = 1000,
): Promise<Aria2Task[]> {
  return rpc<Aria2Task[]>("aria2.tellStopped", [offset, num]);
}

export async function tellStatus(
  gid: string,
  keys?: string[],
): Promise<Aria2Task> {
  if (keys && keys.length > 0) {
    return rpc<Aria2Task>("aria2.tellStatus", [gid, keys]);
  }
  return rpc<Aria2Task>("aria2.tellStatus", [gid]);
}

export async function getAllTasks(): Promise<Aria2Task[]> {
  const [active, waiting, stopped] = await Promise.all([
    tellActive(),
    tellWaiting(),
    tellStopped(),
  ]);
  const seen = new Set<string>();
  return [...active, ...waiting, ...stopped].filter((task) => {
    if (seen.has(task.gid)) return false;
    seen.add(task.gid);
    return true;
  });
}

export async function addUri(
  uris: string[],
  options: Record<string, string | string[]> = {},
): Promise<string> {
  return rpc<string>("aria2.addUri", [uris, options]);
}

export async function addTorrent(
  torrentBase64: string,
  options: Record<string, string | string[]> = {},
): Promise<string> {
  return rpc<string>("aria2.addTorrent", [torrentBase64, [], options]);
}

export async function pauseTask(gid: string): Promise<string> {
  return rpc<string>("aria2.pause", [gid]);
}

export async function resumeTask(gid: string): Promise<string> {
  return rpc<string>("aria2.unpause", [gid]);
}

export async function removeTask(gid: string): Promise<string> {
  return rpc<string>("aria2.remove", [gid]);
}

export async function removeTaskResult(gid: string): Promise<string> {
  return rpc<string>("aria2.removeDownloadResult", [gid]);
}

export async function pauseAll(): Promise<string> {
  return rpc<string>("aria2.pauseAll");
}

export async function unpauseAll(): Promise<string> {
  return rpc<string>("aria2.unpauseAll");
}

export async function purgeDownloadResult(): Promise<string> {
  return rpc<string>("aria2.purgeDownloadResult");
}

export async function changeGlobalOption(
  options: Record<string, string>,
): Promise<string> {
  return rpc<string>("aria2.changeGlobalOption", [options]);
}

export async function shutdown(): Promise<string> {
  return rpc<string>("aria2.shutdown");
}

export async function forceShutdown(): Promise<string> {
  return rpc<string>("aria2.forceShutdown");
}
