/*
 * Filter patterns as the phrases a user types (shared/fixtures/phrases.json):
 * the saved filter holds a pattern, built from phrases and read back into them.
 */

// the pattern language's `\s` set (shared/patterns/README.md), not the engine's
const WHITESPACE =
  /^[\t-\r \u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]$/;
const WORD_CHARACTER = /^[A-Za-z0-9_]$/;
const SPECIAL = new Set("\\^$.|?*+()[]{}");
const WHITESPACE_RUN = "\\s+";
const BOUNDARY = "\\b";

function isWhitespace(character: string | undefined): boolean {
  return character !== undefined && WHITESPACE.test(character);
}

function isWordCharacter(character: string | undefined): boolean {
  return character !== undefined && WORD_CHARACTER.test(character);
}

/** One phrase's part of a pattern; "" for a phrase that is only whitespace. */
function phrasePattern(phrase: string): string {
  const characters = Array.from(phrase);
  let start = 0;
  let end = characters.length;
  while (start < end && isWhitespace(characters[start])) {
    start += 1;
  }
  while (end > start && isWhitespace(characters[end - 1])) {
    end -= 1;
  }
  const trimmed = characters.slice(start, end);
  if (trimmed.length === 0) {
    return "";
  } else {
    let body = "";
    trimmed.forEach((character, index) => {
      if (isWhitespace(character)) {
        if (!isWhitespace(trimmed[index - 1])) {
          body += WHITESPACE_RUN;
        }
      } else if (SPECIAL.has(character)) {
        body += `\\${character}`;
      } else {
        body += character;
      }
    });
    const before = isWordCharacter(trimmed[0]) ? BOUNDARY : "";
    const after = isWordCharacter(trimmed[trimmed.length - 1]) ? BOUNDARY : "";
    return `${before}${body}${after}`;
  }
}

/**
 * The filter pattern that finds any of `phrases`, each as whole words.
 *
 * Empty phrases and repeats are dropped; no phrases give the empty pattern.
 */
export function phrasesToPattern(phrases: readonly string[]): string {
  const parts = new Set(phrases.map(phrasePattern));
  parts.delete("");
  return Array.from(parts).join("|");
}

/** The phrase one alternative of a pattern may stand for; null when it uses anything a phrase can't produce. */
function readPhrase(alternative: readonly string[]): string | null {
  let phrase = "";
  let index = 0;
  while (index < alternative.length) {
    const character = alternative[index];
    const next = alternative[index + 1];
    if (character !== "\\") {
      phrase += character;
      index += 1;
    } else if (
      next === "b" &&
      (index === 0 || index === alternative.length - 2)
    ) {
      index += 2;
    } else if (next === "s" && alternative[index + 2] === "+") {
      phrase += " ";
      index += 3;
    } else if (next !== undefined && SPECIAL.has(next)) {
      phrase += next;
      index += 2;
    } else {
      return null;
    }
  }
  return phrase;
}

/**
 * The phrases a pattern was built from, or null when {@link phrasesToPattern}
 * could not have produced it.
 */
export function patternToPhrases(pattern: string): string[] | null {
  const alternatives: string[][] = [[]];
  const characters = Array.from(pattern);
  for (let index = 0; index < characters.length; index += 1) {
    const character = characters[index];
    if (character === "|") {
      alternatives.push([]);
    } else {
      alternatives[alternatives.length - 1].push(character);
      if (character === "\\" && index + 1 < characters.length) {
        index += 1;
        alternatives[alternatives.length - 1].push(characters[index]);
      }
    }
  }
  const phrases = pattern === "" ? [] : alternatives.map(readPhrase);
  if (phrases.some((phrase) => phrase === null)) {
    return null;
  } else {
    const read = phrases as string[];
    return phrasesToPattern(read) === pattern ? read : null;
  }
}

/** A saved pattern as the app uses it: unchanged when it is phrases, otherwise no pattern. */
export function phrasePatternOnly(pattern: unknown): string {
  return typeof pattern === "string" && patternToPhrases(pattern) !== null
    ? pattern
    : "";
}
