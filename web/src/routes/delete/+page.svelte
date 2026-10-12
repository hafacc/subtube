<script lang="ts">
  import { onMount } from "svelte";
  import { resolve } from "$app/paths";
  import GoogleButton from "../../components/GoogleButton.svelte";
  import Icon from "../../components/Icon.svelte";
  import Logo from "../../components/Logo.svelte";
  import { privacyUrl, termsUrl } from "../../lib/config";
  import { fetchDriveUser } from "../../lib/drive";
  import {
    deleteEverything,
    returnedToken,
    signInUrl,
  } from "../../lib/web-sign-in";
  import { TokenExpiredError } from "../../lib/youtube";

  type Stage = "signedOut" | "signedIn" | "working" | "failed" | "deleted";

  const STATE_KEY = "subtube.deleteSignIn";

  let stage = $state<Stage>("signedOut");
  // held in memory only: a reload signs the page out
  let token: string | null = null;
  let account = $state<string | null>(null);

  /** The state of the sign-in this tab started, which answers one return only. */
  function takeState(): string | null {
    try {
      const state = sessionStorage.getItem(STATE_KEY);
      sessionStorage.removeItem(STATE_KEY);
      return state;
    } catch {
      return null;
    }
  }

  onMount(() => {
    const returned = returnedToken(location.hash, takeState());
    if (location.hash) {
      history.replaceState(history.state, "", location.pathname);
    }
    if (returned) {
      token = returned;
      stage = "signedIn";
      fetchDriveUser(returned)
        .then((user) => {
          account = user.emailAddress ?? user.displayName;
        })
        .catch(() => undefined);
    }
  });

  function signIn(): void {
    const state = crypto.randomUUID();
    try {
      sessionStorage.setItem(STATE_KEY, state);
    } catch {
      // without it the returning token is refused and the page stays signed out
    }
    // the one address on the OAuth client, however this page was reached
    location.assign(signInUrl(location.origin + resolve("/delete"), state));
  }

  async function remove(): Promise<void> {
    if (token) {
      stage = "working";
      try {
        await deleteEverything(token);
        token = null;
        stage = "deleted";
      } catch (caught) {
        if (caught instanceof TokenExpiredError) {
          token = null;
          account = null;
          stage = "signedOut";
        } else {
          stage = "failed";
        }
      }
    }
  }
</script>

<svelte:head>
  <title>Delete your SubTube profile</title>
  <meta
    name="description"
    content="Sign in and delete everything SubTube stored for you."
  >
</svelte:head>

<!-- laid out as ExtensionRequired and GetApp: the brand over one card -->
<div class="page">
  <header>
    <a class="brand" href={resolve("/")}><Logo /> SubTube</a>
  </header>
  <main>
    <section aria-labelledby="delete-title">
      {#if stage === "deleted"}
        <span class="disk">
          <Icon name="check" size={28} strokeWidth={2.5} />
        </span>
      {:else}
        <span class="badge-icon">
          <Icon name="trash" size={30} strokeWidth={1.75} />
        </span>
      {/if}
      <h1 id="delete-title">Delete your SubTube profile</h1>
      {#if stage === "deleted"}
        <p class="lead" role="status">Your profile is deleted.</p>
      {:else if stage === "signedOut"}
        <p class="lead">
          Sign in to delete your profile: your filters and which videos you've
          watched, on every device.
        </p>
        <div class="actions"><GoogleButton onclick={signIn} /></div>
      {:else}
        {#if account}
          <p class="account">
            Signed in as {account}.
            <button type="button" class="link" onclick={signIn}>
              Use a different account
            </button>
          </p>
        {/if}
        <p class="lead">
          This deletes your filters and which videos you've watched from your
          Google Drive, and removes SubTube's access to your Google account. It
          happens right away and can't be undone.
        </p>
        {#if stage === "failed"}
          <p class="error-text" role="alert">
            Deleting didn't finish. Some data may already be gone. Please try
            again.
          </p>
        {/if}
        <div class="actions">
          <button
            type="button"
            class="destructive"
            disabled={stage === "working"}
            onclick={() => void remove()}
          >
            Delete profile
          </button>
        </div>
      {/if}
      <p class="footer">
        The apps have the same option in Settings.
        <a href={privacyUrl}>Privacy policy</a>
        <a href={termsUrl}>Terms</a>
      </p>
    </section>
  </main>
</div>

<style>
  .page {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    background: var(--surface);
  }

  header {
    padding: 12px 16px;
  }

  .brand {
    width: fit-content;
    color: var(--text);
    text-decoration: none;
  }

  main {
    flex: 1;
    display: grid;
    place-items: center;
    padding: 32px 16px 64px;
  }

  section {
    width: 100%;
    max-width: 520px;
    padding: 40px;
    border: 1px solid var(--border);
    border-radius: 16px;
    background: var(--page);
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  @media (max-width: 480px) {
    section {
      padding: 24px;
    }
  }

  .badge-icon {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border-radius: 14px;
    background: var(--tint);
    color: var(--gold);
  }

  /* as the feed's "caught up" mark */
  .disk {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border-radius: 50%;
    background: var(--sunflower);
    color: var(--ink);
  }

  h1 {
    margin: 0;
    font-size: 26px;
    line-height: 32px;
    font-weight: 700;
  }

  .lead,
  .account {
    margin: 0;
    font-size: 16px;
    line-height: 24px;
  }

  .lead {
    color: var(--text-secondary);
  }

  .link {
    padding: 0;
    border: 0;
    background: none;
    color: var(--gold);
    text-decoration: underline;
  }

  .link:hover {
    color: var(--gold-hover);
  }

  .error-text {
    font-size: 15px;
  }

  .actions {
    display: flex;
    padding-top: 4px;
  }

  /* as Settings' "Delete profile", at the height of this page's other buttons */
  .destructive {
    min-height: 44px;
    padding: 0 22px;
    border: 0;
    border-radius: 22px;
    background: var(--error);
    color: var(--page);
    font-size: 16px;
    font-weight: 600;
    transition: opacity 0.15s;
  }

  .destructive:disabled {
    opacity: 0.5;
  }

  .footer {
    margin: 0;
    padding-top: 16px;
    border-top: 1px solid var(--border);
    font-size: 13px;
    line-height: 19px;
    color: var(--text-secondary);
  }

  @media (prefers-reduced-motion: reduce) {
    .destructive {
      transition: none;
    }
  }
</style>
