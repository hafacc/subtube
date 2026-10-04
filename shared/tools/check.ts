/*
 * Checks shared/ is consistent: every fixture is valid JSON with a description
 * and uniquely named cases, the example device files pass or fail the schema
 * as their names say (valid-* / invalid-*), and the meta regex in
 * patterns/meta-regex.txt, in the schema and in tools/pattern.ts is the same.
 *
 *   cd shared && bun install && bun tools/check.ts
 */
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import Ajv2020 from "ajv/dist/2020";
import { buildMetaRegex } from "./pattern";

const SHARED = join(import.meta.dir, "..");
const failures: string[] = [];

function readJson(path: string): unknown {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (caught) {
    failures.push(`${path}: ${(caught as Error).message}`);
    return undefined;
  }
}

const fixtures = join(SHARED, "fixtures");
for (const name of readdirSync(fixtures).filter((file) =>
  file.endsWith(".json"),
)) {
  const fixture = readJson(join(fixtures, name)) as
    | { description?: unknown; cases?: { name?: unknown }[] }
    | undefined;
  if (fixture === undefined) {
    continue;
  }
  if (
    typeof fixture.description !== "string" ||
    !Array.isArray(fixture.cases)
  ) {
    failures.push(`${name}: needs a description and a cases array`);
    continue;
  }
  const seen = new Set<unknown>();
  for (const testCase of fixture.cases) {
    if (typeof testCase.name !== "string" || seen.has(testCase.name)) {
      failures.push(`${name}: missing or repeated case name ${testCase.name}`);
    }
    seen.add(testCase.name);
  }
}

const meta = readFileSync(join(SHARED, "patterns", "meta-regex.txt"), "utf8");
if (meta !== buildMetaRegex()) {
  failures.push("patterns/meta-regex.txt differs from tools/pattern.ts");
}
const schema = readJson(join(SHARED, "schema", "device-file.schema.json")) as {
  $defs: { filter: { properties: { regex: { pattern: string } } } };
};
if (schema.$defs.filter.properties.regex.pattern !== meta) {
  failures.push(
    "the schema's regex pattern differs from patterns/meta-regex.txt",
  );
}

const validate = new Ajv2020({ strict: true, allErrors: true }).compile(schema);
const examples = join(fixtures, "device-files");
for (const name of readdirSync(examples)) {
  const expected = name.startsWith("valid-");
  if (!expected && !name.startsWith("invalid-")) {
    failures.push(`device-files/${name}: name must start valid- or invalid-`);
  }
  const file = readJson(join(examples, name));
  if (file !== undefined && validate(file) !== expected) {
    failures.push(
      `device-files/${name}: expected ${expected ? "valid" : "invalid"}${expected ? `: ${JSON.stringify(validate.errors)}` : ""}`,
    );
  }
}

for (const failure of failures) {
  console.error(failure);
}
console.log(
  failures.length === 0
    ? "shared/ is consistent"
    : `${failures.length} failures`,
);
process.exit(failures.length === 0 ? 0 : 1);
