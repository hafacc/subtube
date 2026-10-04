import { plugin } from "bun";
import { compileModule } from "svelte/compiler";

/* `bun test` knows nothing of runes: compile `.svelte.ts` modules as Vite does. */
const transpiler = new Bun.Transpiler({ loader: "ts" });

plugin({
  name: "svelte-modules",
  setup(build) {
    build.onLoad({ filter: /\.svelte\.ts$/ }, async ({ path }) => {
      const source = transpiler.transformSync(await Bun.file(path).text());
      const compiled = compileModule(source, {
        filename: path,
        generate: "client",
      });
      return { contents: compiled.js.code, loader: "js" };
    });
  },
});
