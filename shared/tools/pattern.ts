/*
 * Reference implementation of the filter pattern language in
 * shared/patterns/README.md: the meta regex that validates a pattern, and the
 * rewrite that turns a valid pattern into the engine pattern every client
 * compiles. The tools use it; clients carry their own port.
 */

const DIGITS = "0123456789";
const LOWER = "abcdefghijklmnopqrstuvwxyz";
const UPPER = LOWER.toUpperCase();

/** `x-y` for every ordered pair in one run of characters. */
function orderedRanges(run: string): string[] {
  const last = run[run.length - 1];
  return Array.from(run, (first) => `${first}-[${first}-${last}]`);
}

/** The meta regex: matches exactly the valid patterns. */
export function buildMetaRegex(): string {
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
