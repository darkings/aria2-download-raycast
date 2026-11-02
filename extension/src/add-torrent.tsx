import {
  Action,
  ActionPanel,
  Form,
  Toast,
  getPreferenceValues,
  getSelectedFinderItems,
  showToast,
  useNavigation,
} from "@raycast/api";
import { useEffect, useState } from "react";

import { addTorrent, ensureDaemon } from "./lib/rpc";
import { loadSettingsOrDefaults } from "./lib/state";
import {
  isTorrentPath,
  readTorrentBase64,
  torrentDisplayName,
} from "./lib/torrent";
import { Aria2Settings, ExtensionPreferences } from "./lib/types";

interface TorrentFormValues {
  torrent: string[];
  directory: string[];
  pause: boolean;
  seed: boolean;
  navigate: boolean;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export default function AddTorrent() {
  const preferences = getPreferenceValues<ExtensionPreferences>();
  const { pop } = useNavigation();
  const [settings, setSettings] = useState<Aria2Settings | null>(null);
  const [torrent, setTorrent] = useState<string[]>([]);
  const [directory, setDirectory] = useState<string[]>([]);
  const [pause, setPause] = useState(false);
  const [seed, setSeed] = useState(false);
  const [navigate, setNavigate] = useState(true);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    async function boot() {
      const loaded = await loadSettingsOrDefaults();
      if (cancelled) return;
      setSettings(loaded);
      setDirectory(loaded.downloadDir ? [loaded.downloadDir] : []);
      setSeed(loaded.seedTime > 0);
      try {
        const items = await getSelectedFinderItems();
        const selected = items.find((item) => isTorrentPath(item.path));
        if (selected) setTorrent([selected.path]);
      } catch {
        // Explorer selection is optional.
      }
      setIsLoading(false);
    }
    boot();
    return () => {
      cancelled = true;
    };
  }, []);

  async function submit(values: TorrentFormValues) {
    values = { ...values, torrent, directory, pause, seed, navigate };
    const filePath = values.torrent[0];
    if (!filePath) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Choose a .torrent file",
      });
      return;
    }
    if (!isTorrentPath(filePath)) {
      await showToast({
        style: Toast.Style.Failure,
        title: "The selected file is not a .torrent",
      });
      return;
    }

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Reading torrent…",
    });
    try {
      const base64 = await readTorrentBase64(filePath);
      const options: Record<string, string | string[]> = {};
      if (values.directory.length > 0) options.dir = values.directory[0];
      if (values.pause) options.pause = "true";
      if (values.seed && settings) {
        options["seed-time"] = String(
          settings.seedTime > 0 ? settings.seedTime : 60,
        );
        options["seed-ratio"] = String(settings.seedRatio);
      } else {
        options["seed-time"] = "0";
      }
      await ensureDaemon();
      toast.title = "Adding torrent…";
      await addTorrent(base64, options);
      toast.style = Toast.Style.Success;
      toast.title = "Torrent added";
      toast.message = torrentDisplayName(filePath);
      if (values.navigate) pop();
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not add torrent";
      toast.message = messageOf(error);
    }
  }

  if (isLoading || !settings) {
    return <Form isLoading={true} />;
  }

  return (
    <Form
      isLoading={isLoading}
      navigationTitle="Add Torrent"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Add Torrent" onSubmit={submit} />
        </ActionPanel>
      }
    >
      <Form.FilePicker
        id="torrent"
        title="Torrent File"
        value={torrent}
        onChange={setTorrent}
        canChooseFiles
        canChooseDirectories={false}
        allowMultipleSelection={false}
      />
      <Form.Description
        text={`RPC: ${preferences.rpcEndpoint || `127.0.0.1:${settings.rpcPort}`} · ${settings.downloadDir}`}
      />
      <Form.FilePicker
        id="directory"
        title="Save Directory"
        value={directory}
        onChange={setDirectory}
        canChooseDirectories
        canChooseFiles={false}
        allowMultipleSelection={false}
      />
      <Form.Checkbox
        id="pause"
        label="Add as paused"
        value={pause}
        onChange={setPause}
      />
      <Form.Checkbox
        id="seed"
        label="Seed after download (respect private tracker rules)"
        value={seed}
        onChange={setSeed}
      />
      <Form.Description text="Seeding is off by default (seed-time=0). BT still uploads while downloading." />
      <Form.Checkbox
        id="navigate"
        label="Return after adding"
        value={navigate}
        onChange={setNavigate}
      />
    </Form>
  );
}
