<script lang="ts">
  import ExtensionRequired from "./components/ExtensionRequired.svelte";
  import GetApp from "./components/GetApp.svelte";
  import Shell from "./components/Shell.svelte";
  import { currentEnvironment } from "./lib/environment";
  import { platform } from "./lib/platform";

  const environment = currentEnvironment();
  // null until the extension has answered or timed out
  let extensionFound: boolean | null = $state(null);

  if (environment.kind === "chrome") {
    void platform().then((found) => {
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
{/if}
