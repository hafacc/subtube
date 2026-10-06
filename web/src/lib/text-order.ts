/** Text with every code point lowercased on its own (Unicode's locale-independent mapping), so every client folds alike. */
export function foldCase(text: string): string {
  return Array.from(text, (character) => character.toLowerCase()).join("");
}

/** Order two strings by Unicode code point, not UTF-16 unit. */
export function compareCodePoints(left: string, right: string): number {
  let leftIndex = 0;
  let rightIndex = 0;
  while (leftIndex < left.length && rightIndex < right.length) {
    const leftPoint = left.codePointAt(leftIndex) ?? 0;
    const rightPoint = right.codePointAt(rightIndex) ?? 0;
    if (leftPoint !== rightPoint) {
      return leftPoint < rightPoint ? -1 : 1;
    }
    leftIndex += leftPoint > 0xffff ? 2 : 1;
    rightIndex += rightPoint > 0xffff ? 2 : 1;
  }
  return left.length - leftIndex - (right.length - rightIndex);
}

/** Order two strings ignoring case: {@link foldCase} both, then by code point. */
export function compareIgnoringCase(left: string, right: string): number {
  return compareCodePoints(foldCase(left), foldCase(right));
}

/** Whether a name contains what was typed in a search field, ignoring case only; nothing typed finds every name. */
export function nameMatches(name: string, typed: string): boolean {
  return foldCase(name).includes(foldCase(typed.trim()));
}
