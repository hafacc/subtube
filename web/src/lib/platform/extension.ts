import type {
  ExtensionRequest,
  ExtensionResponses,
} from "../../../../extension/src/protocol";
import type { Platform, Token } from "./types";

/** How long to wait for an installed extension to answer a ping. */
const PING_TIMEOUT_MS = 500;

interface ChromeRuntime {
  sendMessage(
    extensionId: string,
    message: unknown,
    callback: (response: unknown) => void,
  ): void;
  lastError?: { message?: string };
}

function runtime(): ChromeRuntime | null {
  const chrome = (globalThis as { chrome?: { runtime?: ChromeRuntime } })
    .chrome;
  // pages only see `chrome.runtime.sendMessage` when some extension lists them
  // in `externally_connectable`
  return chrome?.runtime?.sendMessage ? chrome.runtime : null;
}

function send<Request extends ExtensionRequest>(
  extensionId: string,
  request: Request,
): Promise<ExtensionResponses[Request["type"]]> {
  return new Promise((resolve, reject) => {
    const chromeRuntime = runtime();
    if (!chromeRuntime) {
      reject(new Error("The SubTube extension isn't installed."));
      return;
    }
    chromeRuntime.sendMessage(extensionId, request, (response) => {
      const failure = chromeRuntime.lastError;
      if (failure || response === undefined) {
        reject(
          new Error(failure?.message ?? "The SubTube extension didn't answer."),
        );
      } else {
        resolve(response as ExtensionResponses[Request["type"]]);
      }
    });
  });
}

function toToken(response: ExtensionResponses["token"]): Token {
  if ("error" in response) {
    throw new Error(response.error);
  } else {
    return response;
  }
}

/** Whether the extension with this id is installed and answering. */
export async function extensionInstalled(
  extensionId: string,
): Promise<boolean> {
  const timeout = new Promise<boolean>((resolve) =>
    setTimeout(() => resolve(false), PING_TIMEOUT_MS),
  );
  const ping = send(extensionId, { type: "ping" }).then(
    () => true,
    () => false,
  );
  return Promise.race([ping, timeout]);
}

/** Silent tokens and the probe, from the installed extension. */
export function extensionPlatform(extensionId: string): Platform {
  return {
    signIn: async () =>
      toToken(await send(extensionId, { type: "token", interactive: true })),
    silentToken: async () => {
      const response = await send(extensionId, {
        type: "token",
        interactive: false,
      });
      return "error" in response ? null : response;
    },
    signOut: async () => {
      await send(extensionId, { type: "signOut" });
    },
    probeShort: async (videoId) => {
      const response = await send(extensionId, { type: "probeShort", videoId });
      return "error" in response ? null : response.isShort;
    },
  };
}
