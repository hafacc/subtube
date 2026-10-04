import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [svelte()],
  build: {
    outDir: "dist",
    target: "es2022",
    // privacy.html is a page of its own, served at /privacy; it loads none of the app
    rollupOptions: { input: ["index.html", "privacy.html"] },
  },
  // the extension's id check lets in any localhost port
  server: { port: 3000 },
});
