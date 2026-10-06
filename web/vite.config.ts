import { svelte } from "@sveltejs/vite-plugin-svelte";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [svelte()],
  build: {
    outDir: "dist",
    target: "es2022",
    // privacy.html and terms.html are pages of their own, served at /privacy and /terms; they load none of the app
    rollupOptions: { input: ["index.html", "privacy.html", "terms.html"] },
  },
  // the extension's id check lets in any localhost port
  server: { port: 3000 },
});
