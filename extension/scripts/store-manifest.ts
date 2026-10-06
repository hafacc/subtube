/** A manifest as far as the store build changes it. */
export interface Manifest {
  /** the development key, which fixes an unpacked build's id */
  key?: string;
  /** the pages that may message the extension */
  externally_connectable?: { matches?: string[] };
  [field: string]: unknown;
}

/**
 * The manifest the Chrome Web Store gets: without `key`, which the store
 * refuses (it assigns the listing's own), and without the `http:` pages
 * (localhost) that only development messages from.
 */
export function storeManifest(manifest: Manifest): Manifest {
  const { key: _developmentKey, ...rest } = manifest;
  const matches = (manifest.externally_connectable?.matches ?? []).filter(
    (match) => !match.startsWith("http:"),
  );
  return { ...rest, externally_connectable: { matches } };
}
