<script lang="ts">
  import { Router } from "../lib/router.svelte";
  import { Session } from "../lib/session.svelte";
  import Feed from "./Feed.svelte";
  import Nux, { resumesAtExtension } from "./Nux.svelte";

  let {
    extension,
  }: {
    /** whether the extension answered when the page loaded */
    extension: boolean;
  } = $props();

  const session = new Session();
  const router = new Router();
  // the app proper needs the extension; without it setup runs, and adds it
  // svelte-ignore state_referenced_locally
  let hasExtension = $state(extension);
  // svelte-ignore state_referenced_locally
  const signedOutStart = extension
    ? session.setupDone
      ? "signin"
      : "intro"
    : session.setupDone || session.account || resumesAtExtension()
      ? "extension"
      : "intro";
</script>

{#if hasExtension && session.account && session.store && session.setupDone}
  {#key session.account.channelId}
    <Feed {session} store={session.store} {router} />
  {/key}
{:else if hasExtension && session.account && session.store}
  <Nux {session} start="channels" extension onextension={() => undefined} />
{:else}
  <Nux
    {session}
    start={signedOutStart}
    {extension}
    onextension={() => {
      hasExtension = true;
    }}
  />
{/if}
