import { plugin } from "bun";
import { compileModule } from "svelte/compiler";

/* `bun test` knows nothing of runes: compile `.svelte.ts` modules as the build does. */
const transpiler = new Bun.Transpiler({ loader: "ts" });
// the collections that signal their changes, as in the browser: bun would pick the server's plain ones
const REACTIVITY = JSON.stringify(
  `${import.meta.dir}/../node_modules/svelte/src/reactivity/index-client.js`,
);

plugin({
  name: "svelte-modules",
  setup(build) {
    build.onLoad({ filter: /\.svelte\.ts$/ }, async ({ path }) => {
      const source = transpiler
        .transformSync(await Bun.file(path).text())
        .replace(/(["'])svelte\/reactivity\1/g, REACTIVITY);
      const compiled = compileModule(source, {
        filename: path,
        generate: "client",
      });
      return { contents: compiled.js.code, loader: "js" };
    });
  },
});
