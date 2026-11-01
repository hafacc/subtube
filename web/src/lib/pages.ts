import privacy from "../../../shared/pages/privacy.json";
import terms from "../../../shared/pages/terms.json";

/** An info page every client shows in the app, as `shared/pages/*.json` holds it. */
export interface InfoPage {
  /** heading */
  title: string;
  /** one-line summary, the built page's description */
  description: string;
  /** where the website publishes it */
  web: string;
  /** last change, as YYYY-MM-DD */
  updated: string;
  /** paragraphs before the first section */
  intro: string[];
  /** headed lists */
  sections: { heading: string; items: string[] }[];
}

/** The info pages' names. */
export type InfoPageName = "privacy" | "terms";

/** Every info page, by name. */
export const INFO_PAGES: Record<InfoPageName, InfoPage> = { privacy, terms };

/** A run of a page's text, a link when it has `href`. */
export interface TextPart {
  /** what is shown */
  text: string;
  /** where it leads */
  href?: string;
}

const LINK = /\[([^[\]]+)\]\(((?:https|mailto):[^()\s]+)\)/g;

/** Split a page's text into plain runs and its `[label](url)` links. */
export function textParts(text: string): TextPart[] {
  const parts: TextPart[] = [];
  let written = 0;
  for (const match of text.matchAll(LINK)) {
    if (match.index > written) {
      parts.push({ text: text.slice(written, match.index) });
    }
    parts.push({ text: match[1], href: match[2] });
    written = match.index + match[0].length;
  }
  if (written < text.length) {
    parts.push({ text: text.slice(written) });
  }
  return parts;
}

/** "Last updated October 13, 2026" for a page's `updated`. */
export function updatedLabel(updated: string): string {
  const date = new Date(`${updated}T00:00:00Z`).toLocaleDateString("en-US", {
    dateStyle: "long",
    timeZone: "UTC",
  });
  return `Last updated ${date}`;
}
