/*
 * Local storage that may be missing or full (private windows, blocked
 * storage): a read then finds nothing and a write is dropped, and the app
 * goes on with what it has in memory.
 */

/** The text kept under `key`; null when there is none or storage can't be read. */
export function readText(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

/** Keep `text` under `key`, or remove the key when `text` is null; says whether storage took it. */
export function writeText(key: string, text: string | null): boolean {
  try {
    if (text === null) {
      localStorage.removeItem(key);
    } else {
      localStorage.setItem(key, text);
    }
    return true;
  } catch {
    return false;
  }
}

/** The JSON value kept under `key`; null when there is none or it can't be read. */
export function readJson<Value>(key: string): Value | null {
  try {
    const raw = readText(key);
    return raw ? (JSON.parse(raw) as Value) : null;
  } catch {
    return null;
  }
}

/** Keep `value` as JSON under `key`, or remove the key when `value` is null. */
export function writeJson(key: string, value: unknown): boolean {
  return writeText(key, value === null ? null : JSON.stringify(value));
}

/** Every key kept that starts with `prefix`. */
export function keysWith(prefix: string): string[] {
  try {
    return Object.keys(localStorage).filter((key) => key.startsWith(prefix));
  } catch {
    return [];
  }
}
