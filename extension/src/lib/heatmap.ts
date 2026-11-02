import { promises as fs } from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

import { environment } from "@raycast/api";

import type { ChunkGrid } from "./bitfield";
import { renderHeatmapSvg, type Appearance } from "./heatmap-svg";

export interface HeatmapFile {
  filePath: string;
  hash: string;
}

export async function writeHeatmapFile(
  gid: string,
  grid: ChunkGrid,
  hash: string,
  appearance: Appearance,
): Promise<HeatmapFile> {
  const supportPath = environment.supportPath;
  await fs.mkdir(supportPath, { recursive: true });
  const filePath = path.join(supportPath, `chunk-${gid}-${hash}.svg`);
  await fs.writeFile(filePath, renderHeatmapSvg(grid, appearance), "utf8");

  try {
    const files = await fs.readdir(supportPath);
    const mine = files
      .filter(
        (name) => name.startsWith(`chunk-${gid}-`) && name.endsWith(".svg"),
      )
      .sort()
      .reverse();
    for (const old of mine.slice(3)) {
      await fs.rm(path.join(supportPath, old), { force: true });
    }
  } catch {
    // Cleanup is best-effort; a stale image must never break the detail view.
  }

  return { filePath, hash };
}

export function heatmapMarkdown(filePath: string): string {
  return `![Chunk map](${pathToFileURL(filePath).href}?raycast-width=760)`;
}

export function chunkLegend(): string {
  return "🟩 complete · 🟨 partial · ⬜ missing · the map follows aria2 pieces, not per-connection offsets";
}
