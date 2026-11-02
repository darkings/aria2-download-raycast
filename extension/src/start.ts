import { Toast, showToast } from "@raycast/api";

import { startDaemon } from "./lib/engine";

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default async function Start() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Starting aria2…",
  });
  try {
    await startDaemon();
    toast.style = Toast.Style.Success;
    toast.title = "aria2 RPC is ready";
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could not start aria2";
    toast.message = messageOf(error);
  }
}
