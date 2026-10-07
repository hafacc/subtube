import adapter from "@sveltejs/adapter-static";
import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [
    sveltekit({
      adapter: adapter({ pages: "dist" }),
      // Pages can't send headers, so every page carries this as a <meta>, with the hashes of SvelteKit's own inline scripts added
      csp: {
        mode: "hash",
        directives: {
          "default-src": ["self"],
          "script-src": [
            "self",
            // the theme script in src/app.html; src/lib/csp.test.ts fails when the two drift
            "sha256-VWx/62e7hhf1mz18aUvCHSiJoyXuhRYr02Xx/mQ8MLA=",
            "https://www.youtube.com",
          ],
          "style-src": ["self", "unsafe-inline"],
          "img-src": [
            "self",
            "data:",
            "https://*.ytimg.com",
            "https://*.ggpht.com",
            "https://*.googleusercontent.com",
          ],
          "connect-src": ["self", "https://www.googleapis.com"],
          "frame-src": ["https://www.youtube.com"],
          "object-src": ["none"],
          "base-uri": ["self"],
          "form-action": ["none"],
        },
      },
    }),
  ],
  build: { target: "es2022" },
  // the extension's id check lets in any localhost port
  server: { port: 3000 },
});
