import { execFile } from "node:child_process";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";

import { environment } from "@raycast/api";

import { Aria2Settings } from "./types";

const POWERSHELL =
  process.env.SystemRoot !== undefined
    ? path.join(
        process.env.SystemRoot,
        "System32",
        "WindowsPowerShell",
        "v1.0",
        "powershell.exe",
      )
    : "powershell.exe";

export interface EngineRunResult {
  code: number;
  stdout: string;
  stderr: string;
}

export class EngineError extends Error {
  readonly code: number;

  constructor(message: string, code: number) {
    super(message);
    this.name = "EngineError";
    this.code = code;
  }
}

export function engineScriptPath(name: string): string {
  const scriptPath = path.join(environment.assetsPath, "engine", name);
  return scriptPath;
}

async function assertEngineScript(name: string): Promise<string> {
  const scriptPath = engineScriptPath(name);
  try {
    await fs.access(scriptPath);
  } catch {
    throw new EngineError(
      `Engine asset missing: ${path.basename(scriptPath)}. Run npm run sync-engine from extension/.`,
      3,
    );
  }
  return scriptPath;
}

export async function runEngine(
  name: string,
  args: string[] = [],
  timeoutMs = 120_000,
): Promise<EngineRunResult> {
  const scriptPath = await assertEngineScript(name);

  return new Promise((resolve, reject) => {
    execFile(
      POWERSHELL,
      [
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        scriptPath,
        ...args,
      ],
      {
        cwd: os.homedir(),
        windowsHide: true,
        timeout: timeoutMs,
        maxBuffer: 8 * 1024 * 1024,
      },
      (error, stdout, stderr) => {
        const code =
          typeof error === "object" && error && "code" in error
            ? Number(error.code ?? 1)
            : 0;
        if (error && code === 0) {
          reject(error);
          return;
        }
        resolve({
          code,
          stdout: String(stdout ?? ""),
          stderr: String(stderr ?? ""),
        });
      },
    );
  });
}

export async function runEngineOrThrow(
  name: string,
  args: string[] = [],
  timeoutMs = 120_000,
): Promise<EngineRunResult> {
  const result = await runEngine(name, args, timeoutMs);
  if (result.code !== 0) {
    const detail = (result.stderr || result.stdout || "").trim();
    throw new EngineError(
      detail || `${name} failed with exit code ${result.code}`,
      result.code,
    );
  }
  return result;
}

export async function startDaemon(): Promise<void> {
  await runEngineOrThrow("Start-Aria2Rpc.ps1", ["-NoToast"], 90_000);
}

export async function stopDaemon(
  options: { onlyIfIdle: boolean; force?: boolean } = { onlyIfIdle: true },
): Promise<void> {
  const args = ["-NoToast"];
  if (options.onlyIfIdle) args.push("-OnlyIfIdle");
  if (options.force) args.push("-Force");
  const result = await runEngine("Stop-Aria2Rpc.ps1", args, 90_000);
  if (result.code === 5) {
    throw new EngineError(
      "aria2 is busy: active or waiting downloads are using it.",
      5,
    );
  }
  if (result.code !== 0) {
    throw new EngineError(
      (result.stderr || result.stdout || "Stop failed").trim(),
      result.code,
    );
  }
}

export async function restartDaemon(): Promise<void> {
  await stopDaemon({ onlyIfIdle: true });
  await startDaemon();
}

export async function saveSettings(
  settings: Aria2Settings,
): Promise<{ restartRequired: boolean }> {
  const tempPath = path.join(
    os.tmpdir(),
    `aria2-raycast-settings-${Date.now()}-${Math.random().toString(16).slice(2)}.json`,
  );
  await fs.writeFile(tempPath, JSON.stringify(settings, null, 2), "utf8");

  try {
    const result = await runEngineOrThrow(
      "Set-Aria2Settings.ps1",
      ["-JsonPath", tempPath],
      60_000,
    );
    const output = result.stdout.trim();
    const lastLine = output.split(/\r?\n/).filter(Boolean).pop();
    if (!lastLine) return { restartRequired: true };
    try {
      const parsed = JSON.parse(lastLine) as { restartRequired?: boolean };
      return { restartRequired: parsed.restartRequired !== false };
    } catch {
      return { restartRequired: true };
    }
  } finally {
    await fs.rm(tempPath, { force: true }).catch(() => undefined);
  }
}

export async function simulateRun(
  name: string,
  args: string[] = [],
): Promise<EngineRunResult> {
  return runEngine(name, [...args, "-DryRun"], 60_000);
}
