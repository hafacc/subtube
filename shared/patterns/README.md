# Filter patterns

A channel filter's `regex` is written in one small pattern language that every
client — JavaScript (web, extension), Swift (`NSRegularExpression`, i.e. ICU)
and Kotlin (`java.util.regex`) — reads and matches the same way. It is a subset
of regular expressions, chosen so that:

1. one regular expression, the **meta regex**, accepts exactly the valid
   patterns, so validity is one check that every client runs identically;
2. after a fixed rewrite (below), all three engines find the same matches.

A client validates with the meta regex before saving, and refuses to save a
pattern it rejects. A stored pattern that fails the meta regex (a newer client's,
or a hand-edited file) is treated as no pattern.

## The language

| Syntax | Meaning |
| --- | --- |
| any character except `\ ^ $ . \| ? * + ( ) [ ] { }` | itself (including space, `-`, `,`, `:`, `/`, `#`, `&`, line breaks, emoji) |
| `\` + one of `\ ^ $ . \| ? * + ( ) [ ] { } /` | that character |
| `\t` `\n` `\r` | tab, line feed, carriage return |
| `.` | any one character (code point), line breaks included |
| `\d` `\D` | ASCII digit `[0-9]` / anything else |
| `\w` `\W` | ASCII word character `[A-Za-z0-9_]` / anything else |
| `\s` `\S` | Unicode White_Space (U+0009–U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028, U+2029, U+202F, U+205F, U+3000) / anything else |
| `\b` `\B` | boundary / no boundary between a `\w` and a non-`\w` (ASCII, so there is no boundary between `é` and a space) |
| `^` `$` | very start / very end of the text (never at line breaks, and `$` never before a final line break) |
| `[…]` `[^…]` | one character in / not in the set |
| `\|` | alternative |
| `( )` `(?: )` | group (both just group; nothing is captured) — **no group inside a group** |
| `*` `+` `?` `{n}` `{n,}` `{n,m}` | repetition, each optionally followed by `?` (lazy); `n` and `m` are single digits 0–9 with `n ≤ m` |

Inside `[…]` a set is one or more of:

- a character other than `\ ] [ ^ -` (and `&` not followed by `&`);
- a range `x-y` where both ends are ASCII digits, both lowercase or both
  uppercase letters, with `x ≤ y` (`[0-9]`, `[a-f]`, `[C-X]`);
- `\` + one of `\ ^ $ . | ? * + ( ) [ ] { } / -`, or `\t \n \r \d \w \s`.

A set may not be empty and may not start with `:` (ICU reads `[:alpha:]` as a
POSIX class). `-`, `^` (other than the leading negation), `[` and `]` must be
escaped inside a set.

Everything else is invalid, notably: nested groups, lookahead and lookbehind,
named groups, inline flags (`(?i)`), backreferences, `\u`/`\x`/`\p`/`\0`/`\c`
escapes, `\v` `\f` `\h` `\R` `\A` `\z` `\Q…\E`, escaping a letter or any other
character not listed, possessive quantifiers (`*+`), a quantifier with nothing
to repeat or after an anchor (`^*`, `\b?`), counts over 9, `{,m}`, `[]`, `[^]`,
`&&` and nested sets.

Matching is a **search**: the filter matches if the pattern is found anywhere
in the text. The empty pattern `""` means "no pattern" in a filter (nothing is
searched); whitespace is a pattern like any other.

### Case

`caseSensitive` defaults to false. Case-insensitive matching covers **ASCII
letters only**: `a` matches `A`, but `é` does not match `É`, `ß` does not match
`SS`, and `k` does not match the Kelvin sign. The engines disagree on Unicode
case folding (ICU folds `ß` to `ss`, Java compares single characters, JS uses
simple case folding), so the language doesn't use any engine's case-insensitive
mode; the rewrite spells the cases out instead.

### Phrases

Clients don't show the pattern itself: a user types phrases, and the client
builds the pattern from them and reads a saved pattern back into them
(`fixtures/phrases.json` has the exact rules). A filter's pattern is applied
only when it reads back as phrases; any other pattern, valid or not, is
treated as no pattern and written as `""` the next time that filter is saved.
The built patterns use only literals, `\` escapes of the special characters,
`\s+`, `\b` and `|`.

## Why this subset

It covers what title and description filters need — words, alternatives,
optional parts, numbers, anchors, word boundaries — and drops every construct
where the three engines differ or that the meta regex couldn't check:

- **Nesting** — a regex can't balance parentheses, so one level of groups is
  what keeps the meta regex a complete validator.
- **Counts ≤ 9, ranges within one ASCII run** — `{3,2}` and `[z-a]` are errors
  in every engine, and a regex can only check order over a small table.
- **`\d \w \s \b`, `^ $`, `.`** — each engine defines them differently
  (Unicode digits in ICU, NBSP in JS `\s` but not Java's, `$` before a final
  newline in Java and ICU, ICU's `.` eating `\r\n` whole), so they are
  rewritten into explicit forms.
- **Lazy quantifiers** are kept: they never change *whether* a pattern is
  found, only which match the regex tester highlights, and all engines agree.

## Using it

### Validate

Load `meta-regex.txt` as UTF-8 and trim trailing whitespace (the file has no
trailing newline, but an editor may add one; the regex itself ends in `$`).
Compile it with no flags — JavaScript: `new RegExp(meta, "u")`; Swift:
`NSRegularExpression(pattern: meta)`; Kotlin: `Regex(meta)` — and accept a
pattern iff the meta regex finds a match in it (`test`, `firstMatch`,
`containsMatchIn`). The schema embeds the same string as the `regex` field's
`pattern`.

### Rewrite, then compile

Walk the valid pattern code point by code point and emit the **engine
pattern**:

| In the pattern | Emit |
| --- | --- |
| `.` | `[\s\S]` |
| `$` | `(?![\s\S])` |
| `(` or `(?:` | `(?:` |
| `\d` `\D` | `[0-9]` `[^0-9]` |
| `\w` `\W` | `[A-Za-z0-9_]` `[^A-Za-z0-9_]` |
| `\s` `\S` | `[`*SPACE*`]` `[^`*SPACE*`]` |
| `\b` | `(?:(?<=[A-Za-z0-9_])(?![A-Za-z0-9_])\|(?<![A-Za-z0-9_])(?=[A-Za-z0-9_]))` |
| `\B` | `(?:(?<=[A-Za-z0-9_])(?=[A-Za-z0-9_])\|(?<![A-Za-z0-9_])(?![A-Za-z0-9_]))` |
| inside `[…]`: `\d` `\w` `\s` | `0-9`, `A-Za-z0-9_`, *SPACE* |
| case-insensitive, an ASCII letter outside a set | `[` letter, other case `]`, e.g. `a` → `[aA]` |
| case-insensitive, inside a set | keep every item, then append the other case of each letter item and letter range just before `]`: `[^a-cx]` → `[^a-cxA-CX]` |
| anything else (other escapes, `^`, `\|`, quantifiers, literals) | itself |
| the whole pattern is empty | `(?:)` (ICU refuses an empty pattern) |

*SPACE* is `\` `u` + four hex digits for each White_Space code point listed
above, with ranges for the runs: U+0009-U+000D, U+0020, U+0085, U+00A0,
U+1680, U+2000-U+200A, U+2028, U+2029, U+202F, U+205F, U+3000 (exact string:
`SPACE` in `shared/tools/pattern.ts`).

Compile the engine pattern **case-sensitively** and otherwise with no flags,
except JavaScript's `u` (so `.` and sets see code points, not UTF-16 halves):

- JavaScript: `new RegExp(engine, "u")`, then `regex.test(text)`
- Swift: `NSRegularExpression(pattern: engine)`, then
  `firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil`
- Kotlin: `Regex(engine)`, then `regex.containsMatchIn(text)`

`shared/tools/pattern.ts` is the reference implementation of both the meta
regex and the rewrite; `shared/fixtures/patterns.json` is what every client's
port must pass.

## Checking the engines agree

```sh
bun shared/tools/cross-engine.ts
```

Runs `fixtures/patterns.json` plus 6,000 seeded random patterns (over 30,000
match checks) through Bun, `swift` (ICU) and `java` (`JAVA_HOME`, else Android
Studio's bundled JDK), and fails on any disagreement between them or with a
fixture. Run it after any change to the language.
