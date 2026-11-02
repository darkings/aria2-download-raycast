import { Toast, showToast } from "@raycast/api";

import { EngineError, stopDaemon } from "./lib/engine";

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default async function Stop() {
  const toast = await showToast({
    style: Toast.Style.Animated,
    title: "Stopping aria2…",
  });
  try {
    await stopDaemon({ onlyIfIdle: true });
    toast.style = Toast.Style.Success;
    toast.title = "aria2 stopped";
    toast.message = "Unfinished downloads are saved in the aria2 session file.";
  } catch (error) {
    toast.style = Toast.Style.Failure;
    toast.title = "Could not stop aria2";
    toast.message =
      error instanceof EngineError && error.code === 5
        ? "There are active or waiting downloads. Wait for them to finish, or stop from aria2 with Force."
        : messageOf(error);
  }
}
