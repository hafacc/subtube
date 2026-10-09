let parser: DOMParser | null = null;

/**
 * Decode HTML entities in Data API text ("Tom &amp; Jerry", "don&#39;t"), so
 * it shows as written and filters match what the user sees. The text is
 * parsed into an inert document and read back as text, never put into the
 * page as HTML; every "<" is escaped first, so nothing in it is read as a tag.
 */
export function decodeHtmlEntities(text: string): string {
  if (!text.includes("&") || typeof DOMParser === "undefined") {
    return text;
  } else {
    parser ??= new DOMParser();
    return (
      parser.parseFromString(text.replaceAll("<", "&lt;"), "text/html").body
        ?.textContent ?? text
    );
  }
}
