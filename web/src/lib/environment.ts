/** Which page a browser gets, decided once when the app loads. */
export type Environment =
  | { kind: "phone"; platform: "ios" | "ipados" | "android" }
  | { kind: "safari" }
  | { kind: "chrome" }
  | { kind: "other" };

/** What {@link environmentFor} reads from the browser. */
export interface BrowserTraits {
  /** `navigator.userAgent` */
  userAgent: string;
  /** `navigator.maxTouchPoints` */
  maxTouchPoints: number;
}

/**
 * Classify a browser: phones and tablets get the app page, desktop Safari the
 * Mac app page, Chromium browsers (which install Chrome Web Store extensions)
 * the web app, and anything else a page saying it needs Chrome.
 */
export function environmentFor(traits: BrowserTraits): Environment {
  const { userAgent, maxTouchPoints } = traits;
  if (/Android/.test(userAgent)) {
    return { kind: "phone", platform: "android" };
  } else if (/iPhone|iPod/.test(userAgent)) {
    return { kind: "phone", platform: "ios" };
  } else if (
    /iPad/.test(userAgent) ||
    // iPadOS asks for desktop sites with a Mac user agent; only touch tells it apart
    (/Macintosh/.test(userAgent) && maxTouchPoints > 1)
  ) {
    return { kind: "phone", platform: "ipados" };
  } else if (/Chrome\/|Chromium\//.test(userAgent)) {
    return { kind: "chrome" };
  } else if (
    /Macintosh/.test(userAgent) &&
    /Version\/.*Safari\//.test(userAgent)
  ) {
    return { kind: "safari" };
  } else {
    return { kind: "other" };
  }
}

/** This browser's environment. */
export function currentEnvironment(): Environment {
  return environmentFor({
    userAgent: navigator.userAgent,
    maxTouchPoints: navigator.maxTouchPoints,
  });
}
