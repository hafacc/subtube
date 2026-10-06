/*
 * Runs the pattern fixtures, the patterns the phrase fixtures build, plus
 * seeded random patterns, through JavaScript,
 * ICU (NSRegularExpression via the swift CLI) and java.util.regex, and fails
 * unless all three agree with each other and with the fixtures — both on which
 * patterns the meta regex accepts and on what the valid ones match.
 *
 *   bun shared/tools/cross-engine.ts
 *
 * Needs `swift` and a JDK; JAVA_HOME, else Android Studio's bundled one, else
 * `java` on the PATH.
 */
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildMetaRegex, toEnginePattern } from "./pattern";

const SHARED = join(import.meta.dir, "..");
const ENGINES = join(import.meta.dir, "engines");
const FUZZ_PATTERNS = 6000;
const SEED = 20261003;

/** A pattern fixture case. */
interface PatternCase {
  /** case name */
  name: string;
  /** pattern under test */
  pattern: string;
  /** whether the meta regex accepts it */
  valid: boolean;
  /** search results for valid patterns */
  matches?: { text: string; caseSensitive: boolean; matches: boolean }[];
}

/** One line of engine input: a validity check or a search. */
type Job =
  | { kind: "V"; pattern: string; label: string; expected?: boolean }
  | {
      kind: "M";
      engine: string;
      text: string;
      label: string;
      expected?: boolean;
    };

function mulberry32(seed: number): () => number {
  let state = seed;
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let mixed = Math.imul(state ^ (state >>> 15), 1 | state);
    mixed = (mixed + Math.imul(mixed ^ (mixed >>> 7), 61 | mixed)) ^ mixed;
    return ((mixed ^ (mixed >>> 14)) >>> 0) / 4294967296;
  };
}

const PIECES = [
  ..."aAzZbBkK09 _-,:&#!/.*+?|()[]{}^$\\\n",
  "é",
  "É",
  "😀",
  " ",
  "(?:",
  "(?=",
  "(?<=",
  "{2}",
  "{1,3}",
  "{3,1}",
  "{2,}",
  "{,2}",
  "[a-z]",
  "[^0-9]",
  "[z-a]",
  "[a&&b]",
  "[:a]",
  "[-a]",
  "\\d",
  "\\D",
  "\\w",
  "\\W",
  "\\s",
  "\\S",
  "\\b",
  "\\B",
  "\\n",
  "\\t",
  "\\u0041",
  "\\x41",
  "\\1",
  "\\p{L}",
  "\\-",
  "\\.",
  "\\]",
  "*?",
  "+?",
  "??",
  "a*+",
];

const TEXTS = [
  "",
  "abc ABC 123",
  "a_b-c, d:e & f!",
  "Kz kZ 09 90",
  "😀é É x",
  "line1\nline2\n",
  "[x]{y}(z)^$|.*+?\\/",
  "aaaa bbbb",
  "\t  　",
  "b",
  "a\r\nc",
  "x\r\n",
];

function fuzzPatterns(): string[] {
  const random = mulberry32(SEED);
  return Array.from({ length: FUZZ_PATTERNS }, () => {
    const length = 1 + Math.floor(random() * 8);
    return Array.from(
      { length },
      () => PIECES[Math.floor(random() * PIECES.length)],
    ).join("");
  });
}

function javaBinary(): string {
  const homes = [
    process.env.JAVA_HOME,
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home",
  ];
  for (const home of homes) {
    if (home && existsSync(join(home, "bin", "java"))) {
      return join(home, "bin", "java");
    }
  }
  return "java";
}

function run(command: string[]): string[] {
  const result = Bun.spawnSync(command, { stderr: "inherit" });
  if (result.exitCode !== 0) {
    throw new Error(`${command.join(" ")} exited ${result.exitCode}`);
  }
  return result.stdout.toString().split("\n").slice(0, -1);
}

function jsSearch(engine: string, text: string): string {
  try {
    return new RegExp(engine, "u").test(text) ? "1" : "0";
  } catch {
    return "E";
  }
}

const b64 = (text: string) => Buffer.from(text, "utf8").toString("base64");

const meta = readFileSync(join(SHARED, "patterns", "meta-regex.txt"), "utf8");
if (meta !== buildMetaRegex()) {
  throw new Error(
    "patterns/meta-regex.txt is out of date with tools/pattern.ts",
  );
}
const metaRegex = new RegExp(meta, "u");
const fixture: { cases: PatternCase[] } = JSON.parse(
  readFileSync(join(SHARED, "fixtures", "patterns.json"), "utf8"),
);

// the patterns built from phrases are valid patterns, checked like the others
const phrases: {
  cases: {
    name: string;
    op: string;
    pattern: string;
    matches?: PatternCase["matches"];
  }[];
} = JSON.parse(readFileSync(join(SHARED, "fixtures", "phrases.json"), "utf8"));
const built: PatternCase[] = phrases.cases
  .filter((testCase) => testCase.op === "build")
  .map((testCase) => ({
    name: `phrases / ${testCase.name}`,
    pattern: testCase.pattern,
    valid: true,
    matches: testCase.matches,
  }));

const jobs: Job[] = [];
for (const testCase of [...fixture.cases, ...built]) {
  jobs.push({
    kind: "V",
    pattern: testCase.pattern,
    label: testCase.name,
    expected: testCase.valid,
  });
  for (const check of testCase.matches ?? []) {
    jobs.push({
      kind: "M",
      engine: toEnginePattern(testCase.pattern, check.caseSensitive),
      text: check.text,
      label: `${testCase.name} / ${JSON.stringify(check.text)}${check.caseSensitive ? " (case-sensitive)" : ""}`,
      expected: check.matches,
    });
  }
}
let fuzzValid = 0;
for (const pattern of fuzzPatterns()) {
  const label = `fuzz ${JSON.stringify(pattern)}`;
  jobs.push({ kind: "V", pattern, label });
  if (metaRegex.test(pattern)) {
    fuzzValid += 1;
    for (const caseSensitive of [true, false]) {
      const engine = toEnginePattern(pattern, caseSensitive);
      for (const text of TEXTS) {
        jobs.push({
          kind: "M",
          engine,
          text,
          label: `${label} on ${JSON.stringify(text)}${caseSensitive ? " (case-sensitive)" : ""}`,
        });
      }
    }
  }
}

const input = [
  `META\t${b64(meta)}`,
  ...jobs.map((job) =>
    job.kind === "V"
      ? `V\t${b64(job.pattern)}`
      : `M\t${b64(job.engine)}\t${b64(job.text)}`,
  ),
].join("\n");
const inputPath = join(mkdtempSync(join(tmpdir(), "subtube-engines-")), "in");
writeFileSync(inputPath, `${input}\n`);

const results: Record<string, string[]> = {
  javascript: jobs.map((job) =>
    job.kind === "V"
      ? metaRegex.test(job.pattern)
        ? "1"
        : "0"
      : jsSearch(job.engine, job.text),
  ),
  icu: run(["swift", join(ENGINES, "check.swift"), inputPath]),
  java: run([javaBinary(), join(ENGINES, "Check.java"), inputPath]),
};

const failures: string[] = [];
jobs.forEach((job, index) => {
  const answers = Object.entries(results).map(
    ([engine, lines]) => `${engine}=${lines[index]}`,
  );
  const values = new Set(Object.values(results).map((lines) => lines[index]));
  const expected =
    job.expected === undefined ? undefined : job.expected ? "1" : "0";
  if (
    values.size !== 1 ||
    values.has("E") ||
    (expected !== undefined && !values.has(expected))
  ) {
    const detail =
      job.kind === "M" ? ` engine=${JSON.stringify(job.engine)}` : "";
    failures.push(
      `${job.kind} ${job.label}: ${answers.join(" ")}${expected ? ` expected=${expected}` : ""}${detail}`,
    );
  }
});

for (const failure of failures.slice(0, 50)) {
  console.error(failure);
}
console.log(
  `${jobs.length} checks (${fuzzValid}/${FUZZ_PATTERNS} random patterns valid), ${failures.length} failures`,
);
process.exit(failures.length === 0 ? 0 : 1);
