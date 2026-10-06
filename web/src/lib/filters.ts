import { knownTopics } from "./chips";
import { patternToPhrases } from "./phrases";
import type {
  ChannelFilter,
  FeedItem,
  FilterMode,
  FilterScope,
  LiveFilter,
  ShortsFilter,
} from "./types";
import { oneOf } from "./values";

const DIGITS = "0123456789";
const LOWER = "abcdefghijklmnopqrstuvwxyz";
const UPPER = LOWER.toUpperCase();

/** `x-y` for every ordered pair in one run of characters. */
function orderedRanges(run: string): string[] {
  const last = run[run.length - 1];
  return Array.from(run, (first) => `${first}-[${first}-${last}]`);
}

function buildMetaRegex(): string {
  const literal = String.raw`[^\\\^\$\.\|\?\*\+\(\)\[\]\{\}]`;
  const escaped = String.raw`\\[\\\^\$\.\|\?\*\+\(\)\[\]\{\}\/tnrdDwWsS]`;
  const anchor = String.raw`\^|\$|\\[bB]`;
  const classItem = [
    ...orderedRanges(DIGITS),
    ...orderedRanges(LOWER),
    ...orderedRanges(UPPER),
    String.raw`[^\\\]\[\^\-&]`,
    "&(?!&)",
    String.raw`\\[\\\^\$\.\|\?\*\+\(\)\[\]\{\}\/\-tnrdws]`,
  ].join("|");
  const characterClass = String.raw`\[\^?(?!:)(?:${classItem})+\]`;
  const bounds = Array.from(DIGITS, (digit) => `${digit},[${digit}-9]`).join(
    "|",
  );
  const quantifier = String.raw`(?:[\*\+\?]|\{[0-9]\}|\{[0-9],\}|\{(?:${bounds})\})\??`;
  const atom = String.raw`(?:${literal}|${escaped}|\.|${characterClass})`;
  const piece = `(?:${anchor}|${atom}(?:${quantifier})?)`;
  const group = String.raw`\((?:\?:)?(?:${piece}|\|)*\)`;
  return `^(?:${piece}|${group}(?:${quantifier})?|\\|)*$`;
}

const WORD = "A-Za-z0-9_";
// Not String.raw: Bun decodes some \u escapes inside it.
const SPACE =
  "\\u0009-\\u000D\\u0020\\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000";
const BOUNDARY = `(?:(?<=[${WORD}])(?![${WORD}])|(?<![${WORD}])(?=[${WORD}]))`;
const NOT_BOUNDARY = `(?:(?<=[${WORD}])(?=[${WORD}])|(?<![${WORD}])(?![${WORD}]))`;
const ANY = String.raw`[\s\S]`;
const END = `(?!${ANY})`;

const SHORTHAND_OUTSIDE: Record<string, string> = {
  d: "[0-9]",
  D: "[^0-9]",
  w: `[${WORD}]`,
  W: `[^${WORD}]`,
  s: `[${SPACE}]`,
  S: `[^${SPACE}]`,
  b: BOUNDARY,
  B: NOT_BOUNDARY,
};

const SHORTHAND_INSIDE: Record<string, string> = {
  d: "0-9",
  w: WORD,
  s: SPACE,
};

function isAsciiLetter(char: string): boolean {
  return /^[A-Za-z]$/.test(char);
}

function swapCase(char: string): string {
  return char === char.toLowerCase() ? char.toUpperCase() : char.toLowerCase();
}

/**
 * The engine pattern for a valid pattern: what JavaScript (flag `u`), Java and
 * ICU (no flags) all compile and search with.
 */
export function toEnginePattern(
  pattern: string,
  caseSensitive: boolean,
): string {
  const chars = Array.from(pattern);
  let out = "";
  let index = 0;
  while (index < chars.length) {
    const char = chars[index];
    if (char === "\\") {
      const next = chars[index + 1];
      out += SHORTHAND_OUTSIDE[next] ?? `\\${next}`;
      index += 2;
    } else if (char === ".") {
      out += ANY;
      index += 1;
    } else if (char === "$") {
      out += END;
      index += 1;
    } else if (char === "(") {
      out += "(?:";
      index += chars[index + 1] === "?" ? 3 : 1;
    } else if (char === "[") {
      index += 1;
      let body = "[";
      if (chars[index] === "^") {
        body += "^";
        index += 1;
      }
      let extra = "";
      while (chars[index] !== "]") {
        const item = chars[index];
        if (item === "\\") {
          const next = chars[index + 1];
          body += SHORTHAND_INSIDE[next] ?? `\\${next}`;
          index += 2;
        } else if (chars[index + 1] === "-") {
          const last = chars[index + 2];
          body += `${item}-${last}`;
          if (!caseSensitive && isAsciiLetter(item)) {
            extra += `${swapCase(item)}-${swapCase(last)}`;
          }
          index += 3;
        } else {
          body += item;
          if (!caseSensitive && isAsciiLetter(item)) {
            extra += swapCase(item);
          }
          index += 1;
        }
      }
      out += `${body}${extra}]`;
      index += 1;
    } else if (!caseSensitive && isAsciiLetter(char)) {
      out += `[${char}${swapCase(char)}]`;
      index += 1;
    } else {
      out += char;
      index += 1;
    }
  }
  return out === "" ? "(?:)" : out;
}

/**
 * The meta regex from shared/patterns/meta-regex.txt: it matches exactly the
 * patterns every client reads the same way.
 */
export const PATTERN_META_REGEX = buildMetaRegex();

const META = new RegExp(PATTERN_META_REGEX, "u");

/** Whether a filter pattern is in the shared pattern language. */
export function isValidPattern(pattern: string): boolean {
  return META.test(pattern);
}

/** Compile a valid filter pattern; see shared/patterns/README.md. */
export function compilePattern(
  pattern: string,
  caseSensitive: boolean,
): RegExp {
  return new RegExp(toEnginePattern(pattern, caseSensitive), "u");
}

/** A channel filter read for applying: every field known and in range. */
export interface CompiledFilter {
  /** whether the main feed loads the channel */
  enabled: boolean;
  /** the compiled pattern; null when there is none or it isn't valid */
  regex: RegExp | null;
  /** keep or drop what the pattern finds */
  mode: FilterMode;
  /** what the pattern is searched in */
  scope: FilterScope;
  /** shortest video kept, in seconds; 0 keeps every length */
  minDurationSeconds: number;
  /** which broadcast kinds are kept */
  liveFilter: LiveFilter;
  /** which of Shorts and other videos are kept */
  shortsFilter: ShortsFilter;
  /** the categories kept; empty keeps every one */
  topics: ReadonlySet<string>;
}

/**
 * Read a saved filter for applying. A field that is missing or holds a value
 * this version doesn't recognize reads as its default, and a pattern that is
 * not built from phrases as no pattern (shared/fixtures/filters.json).
 */
export function compileFilter(filter: ChannelFilter): CompiledFilter {
  const raw = filter as unknown as Record<string, unknown>;
  const base = {
    enabled: raw.enabled !== false,
    mode: oneOf(raw.mode, ["include", "exclude"] as const, "include"),
    scope: oneOf(
      raw.searchScope,
      ["title", "both", "description"] as const,
      "title",
    ),
    minDurationSeconds:
      typeof raw.minDurationSeconds === "number" && raw.minDurationSeconds > 0
        ? raw.minDurationSeconds
        : 0,
    liveFilter: oneOf(raw.liveFilter, ["all", "vod", "normal"] as const, "all"),
    shortsFilter: oneOf(
      raw.shortsFilter,
      ["all", "normal", "shorts"] as const,
      "all",
    ),
    topics: knownTopics(
      Array.isArray(raw.topics) &&
        raw.topics.every((id) => typeof id === "string")
        ? raw.topics
        : [],
    ),
  };
  const pattern = typeof raw.regex === "string" ? raw.regex : "";
  const applies =
    pattern !== "" &&
    isValidPattern(pattern) &&
    patternToPhrases(pattern) !== null;
  return {
    ...base,
    regex: applies ? compilePattern(pattern, raw.caseSensitive === true) : null,
  };
}

/** Whether a video gets through a filter's Shorts, broadcast, length and topic gates. */
function videoPassesGates(
  item: Exclude<FeedItem, { kind: "playlist" }>,
  compiled: CompiledFilter,
): boolean {
  const { minDurationSeconds, liveFilter, shortsFilter, topics } = compiled;
  const status = item.liveStatus ?? "normal";
  // a channel that gates on Shorts also hides what it couldn't judge, so a
  // Short never shows in a feed that drops them
  const shortsPass =
    shortsFilter === "all" ||
    (item.isShort !== undefined &&
      item.isShort === (shortsFilter === "shorts"));
  // upcoming videos are always hidden
  const broadcastPass =
    status !== "upcoming" &&
    !(liveFilter === "vod" && status === "normal") &&
    !(liveFilter === "normal" && status !== "normal");
  // a video of unknown length (0: live) is kept
  const lengthPass =
    !item.durationSeconds || item.durationSeconds >= minDurationSeconds;
  const topicPass =
    topics.size === 0 ||
    (item.categoryId !== undefined && topics.has(item.categoryId));
  return shortsPass && broadcastPass && lengthPass && topicPass;
}

/** Whether a compiled filter keeps an item; the gates are for videos, the pattern for playlists too. */
export function videoPassesFilter(
  item: FeedItem,
  compiled: CompiledFilter,
): boolean {
  const { regex, mode, scope } = compiled;
  if (item.kind !== "playlist" && !videoPassesGates(item, compiled)) {
    return false;
  } else if (!regex) {
    return true;
  } else {
    // title and description are searched apart: joined, a match could span both
    const matches =
      (scope !== "description" && regex.test(item.title)) ||
      (scope !== "title" && regex.test(item.description));
    return mode === "include" ? matches : !matches;
  }
}
