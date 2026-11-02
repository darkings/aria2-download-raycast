import {
  Action,
  ActionPanel,
  Clipboard,
  Form,
  Icon,
  Toast,
  getPreferenceValues,
  showToast,
  useNavigation,
} from "@raycast/api";
import { useEffect, useState } from "react";

import { addUri, ensureDaemon } from "./lib/rpc";
import { isMagnetUri, isNetdiskUrl } from "./lib/netdisk";
import { loadSettingsOrDefaults } from "./lib/state";
import { Aria2Settings, ExtensionPreferences } from "./lib/types";

interface FormValues {
  urls: string;
  directory: string[];
  out: string;
  split: string;
  showAdvanced: boolean;
  userAgent: string;
  referer: string;
  cookie: string;
  authorization: string;
  proxy: string;
  checksum: string;
  pause: boolean;
  navigate: boolean;
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function buildHeaders(values: FormValues): string[] {
  const headers: string[] = [];
  if (values.cookie.trim()) headers.push(`Cookie: ${values.cookie.trim()}`);
  if (values.authorization.trim())
    headers.push(`Authorization: ${values.authorization.trim()}`);
  return headers;
}

export default function AddDownload() {
  const preferences = getPreferenceValues<ExtensionPreferences>();
  const { pop } = useNavigation();
  const [settings, setSettings] = useState<Aria2Settings | null>(null);
  const [urls, setUrls] = useState("");
  const [directory, setDirectory] = useState<string[]>([]);
  const [out, setOut] = useState("");
  const [split, setSplit] = useState("16");
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [userAgent, setUserAgent] = useState("");
  const [referer, setReferer] = useState("");
  const [cookie, setCookie] = useState("");
  const [authorization, setAuthorization] = useState("");
  const [proxy, setProxy] = useState("");
  const [checksum, setChecksum] = useState("");
  const [pause, setPause] = useState(false);
  const [navigate, setNavigate] = useState(true);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    async function boot() {
      const loaded = await loadSettingsOrDefaults();
      if (cancelled) return;
      setSettings(loaded);
      setSplit(String(loaded.split));
      setDirectory(loaded.downloadDir ? [loaded.downloadDir] : []);
      try {
        const clipboard = await Clipboard.readText();
        if (
          clipboard &&
          (clipboard.startsWith("http://") ||
            clipboard.startsWith("https://") ||
            isMagnetUri(clipboard))
        ) {
          setUrls(clipboard);
        }
      } catch {
        // Clipboard access is optional.
      }
      setIsLoading(false);
    }
    boot();
    return () => {
      cancelled = true;
    };
  }, []);

  async function submit(values: FormValues) {
    const lines = values.urls
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    if (lines.length === 0) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Enter at least one URL or magnet link",
      });
      return;
    }

    const netdisk = lines.find((line) => isNetdiskUrl(line));
    if (netdisk) {
      await showToast({
        style: Toast.Style.Failure,
        title: "Use LinkSwift for netdisk links",
        message:
          "Directly pasting a netdisk URL misses the Cookie/Referer/UA that LinkSwift sends.",
      });
      return;
    }

    const options: Record<string, string | string[]> = {
      "max-connection-per-server": values.split,
      split: values.split,
      "min-split-size": settings?.minSplitSize ?? "1M",
    };
    if (values.directory.length > 0) options.dir = values.directory[0];
    if (values.out.trim() && lines.length === 1)
      options.out = values.out.trim();
    if (values.userAgent.trim())
      options["user-agent"] = values.userAgent.trim();
    if (values.referer.trim()) options.referer = values.referer.trim();
    if (values.proxy.trim()) options["all-proxy"] = values.proxy.trim();
    if (values.checksum.trim()) options.checksum = values.checksum.trim();
    if (values.pause) options.pause = "true";
    const headers = buildHeaders(values);
    if (headers.length > 0) options.header = headers;

    const toast = await showToast({
      style: Toast.Style.Animated,
      title: "Adding download…",
    });
    try {
      await ensureDaemon();
      for (const line of lines) {
        await addUri([line], options);
      }
      toast.style = Toast.Style.Success;
      toast.title =
        lines.length === 1
          ? "Download added"
          : `${lines.length} downloads added`;
      toast.message = lines.length === 1 ? lines[0].slice(0, 100) : "";
      if (values.navigate) pop();
    } catch (error) {
      toast.style = Toast.Style.Failure;
      toast.title = "Could not add download";
      toast.message = messageOf(error);
    }
  }

  if (isLoading || !settings) {
    return <Form isLoading={true} />;
  }

  return (
    <Form
      isLoading={isLoading}
      navigationTitle="Add Download"
      actions={
        <ActionPanel>
          <Action.SubmitForm title="Add Download" onSubmit={submit} />
          <Action
            title="Paste Clipboard"
            icon={Icon.Clipboard}
            onAction={async () => {
              const text = await Clipboard.readText();
              if (text) setUrls(text);
            }}
          />
        </ActionPanel>
      }
    >
      <Form.TextArea
        id="urls"
        title="URLs"
        placeholder={"https://example.com/file.iso\nmagnet:?xt=urn:btih:…"}
        info="One URL or magnet per line. Netdisk direct links should be pushed by LinkSwift instead."
        value={urls}
        onChange={setUrls}
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
      <Form.TextField
        id="out"
        title="Rename"
        placeholder="Leave empty to use the remote file name"
        value={out}
        onChange={setOut}
      />
      <Form.Dropdown
        id="split"
        title="Connections"
        value={split}
        onChange={setSplit}
      >
        <Form.Dropdown.Item value="1" title="1" />
        <Form.Dropdown.Item value="4" title="4" />
        <Form.Dropdown.Item value="8" title="8" />
        <Form.Dropdown.Item value="16" title="16 (recommended)" />
      </Form.Dropdown>
      <Form.Checkbox
        id="showAdvanced"
        label="Advanced request options"
        value={showAdvanced}
        onChange={setShowAdvanced}
      />
      {showAdvanced && (
        <>
          <Form.Separator />
          <Form.TextField
            id="userAgent"
            title="User-Agent"
            placeholder="Optional. LinkSwift sends its own per task."
            value={userAgent}
            onChange={setUserAgent}
          />
          <Form.TextField
            id="referer"
            title="Referer"
            placeholder="Optional. LinkSwift sends its own per task."
            value={referer}
            onChange={setReferer}
          />
          <Form.PasswordField
            id="cookie"
            title="Cookie"
            placeholder="Optional; keep empty for normal direct links"
            value={cookie}
            onChange={setCookie}
          />
          <Form.PasswordField
            id="authorization"
            title="Authorization"
            placeholder="Optional header value"
            value={authorization}
            onChange={setAuthorization}
          />
          <Form.TextField
            id="proxy"
            title="Proxy"
            placeholder="Optional all-proxy, e.g. http://127.0.0.1:7890"
            value={proxy}
            onChange={setProxy}
          />
          <Form.TextField
            id="checksum"
            title="Checksum"
            placeholder="Optional, e.g. sha-256=…"
            value={checksum}
            onChange={setChecksum}
          />
        </>
      )}
      <Form.Separator />
      <Form.Checkbox
        id="pause"
        label="Add as paused"
        value={pause}
        onChange={setPause}
      />
      <Form.Checkbox
        id="navigate"
        label="Return after adding"
        value={navigate}
        onChange={setNavigate}
      />
    </Form>
  );
}
