<script lang="ts">
  import ExtensionRequired from "./components/ExtensionRequired.svelte";
  import GetApp from "./components/GetApp.svelte";
  import Logo from "./components/Logo.svelte";
  import Shell from "./components/Shell.svelte";
  import { currentEnvironment } from "./lib/environment";
  import { platform } from "./lib/platform";

  const environment = currentEnvironment();
  // null until the extension has answered or timed out
  let extensionFound: boolean | null = $state(null);
  // the quick check missed on a browser that has had the extension: it may still be starting
  let waiting = $state(false);

  if (environment.kind === "chrome") {
    void platform(() => {
      waiting = true;
    }).then((found) => {
      extensionFound = found !== null;
    });
  }
</script>

{#if environment.kind === "phone"}
  <GetApp platform={environment.platform} />
{:else if environment.kind === "safari"}
  <GetApp platform="mac" />
{:else if environment.kind === "other"}
  <ExtensionRequired />
{:else if extensionFound !== null}
  <Shell extension={extensionFound} />
{:else if waiting}
  <main class="waiting" aria-busy="true"><Logo hull={28.8} loading /></main>
{/if}

<style>
  .waiting {
    display: grid;
    place-items: center;
    min-height: 100vh;
  }
</style>
