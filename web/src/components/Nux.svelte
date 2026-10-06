<script lang="ts" module>
  /** sessionStorage key: set across the reload that lets the page see a newly added extension. */
  const RESUME_AT_EXTENSION = "subtube.setupAtExtension";

  /** Whether setup reloaded itself on its extension step and should reopen there; asked once. */
  export function resumesAtExtension(): boolean {
    try {
      const resumes = sessionStorage.getItem(RESUME_AT_EXTENSION) !== null;
      sessionStorage.removeItem(RESUME_AT_EXTENSION);
      return resumes;
    } catch {
      return false;
    }
  }
</script>

<script lang="ts">
  import { getValidToken } from "../lib/auth";
  import { channelInfo } from "../lib/channel-info";
  import { mostCommonShorts, SHORTS_OPTIONS } from "../lib/channel-summary";
  import {
    keepPendingStart,
    START_OPTIONS,
    type StartFrom,
  } from "../lib/chips";
  import { chromeWebStoreUrl, privacyUrl, termsUrl } from "../lib/config";
  import { handOffPrefetched, Prefetch } from "../lib/feed.svelte";
  import { recheckPlatform } from "../lib/platform";
  import type { Session } from "../lib/session.svelte";
  import { ProfileDeletedError } from "../lib/sync-store";
  import type { Channel, ShortsFilter } from "../lib/types";
  import { fetchSubscriptions } from "../lib/youtube";
  import Avatar from "./Avatar.svelte";
  import ChoiceRow from "./ChoiceRow.svelte";
  import Icon from "./Icon.svelte";
  import Logo from "./Logo.svelte";
  import Switch from "./Switch.svelte";

  type Step =
    | "intro"
    | "extension"
    | "signin"
    | "channels"
    | "shorts"
    | "start"
    | "done";

  let {
    session,
    start = "intro",
    extension,
    onextension,
  }: {
    /** who is signing in */
    session: Session;
    /** the step to open on */
    start?: Step;
    /** whether the extension answered when the page loaded */
    extension: boolean;
    /** called once setup moves on with the extension added */
    onextension: () => void;
  } = $props();

  // the step list's entry for each step
  const STEP_POSITION: Record<Step, number> = {
    intro: 0,
    extension: 1,
    signin: 2,
    channels: 3,
    shorts: 4,
    start: 5,
    done: 6,
  };
  const LABELS = [
    "What SubTube is",
    "Add the Chrome extension",
    "Sign in with Google",
    "Choose channels",
    "Shorts",
    "Where to start",
  ];
  const SKELETON_ROWS = Array.from({ length: 16 }, (_, index) => index);

  /** How often the extension step looks for the extension while it is missing. */
  const EXTENSION_POLL_MS = 1500;

  // svelte-ignore state_referenced_locally
  let step: Step = $state(start);
  // svelte-ignore state_referenced_locally
  let extensionFound = $state(extension);
  const index = $derived(STEP_POSITION[step]);

  let channels: Channel[] = $state.raw([]);
  let enabled: Record<string, boolean> = $state({});
  // the channels' most common Shorts setting when loaded; applied to all only if changed
  let startingShorts: ShortsFilter = $state("all");
  let shortsDefault: ShortsFilter = $state("all");
  let startFrom: StartFrom = $state("all");
  let query = $state("");
  let loadingChannels = $state(false);
  let channelsLoaded = $state(false);
  let error: string | null = $state(null);

  // the items of the channels left on, fetched from "Choose channels"' Next
  const prefetch = new Prefetch();

  const onCount = $derived(
    channels.filter((channel) => enabled[channel.channelId]).length,
  );
  const shownChannels = $derived(
    channels.filter((channel) =>
      channel.title.toLowerCase().includes(query.trim().toLowerCase()),
    ),
  );
  /*
   * A page only gets to message an extension that was there when it loaded, so
   * one added since is seen after a reload; setup reopens on this step.
   */
  function reloadForExtension(): void {
    try {
      sessionStorage.setItem(RESUME_AT_EXTENSION, "1");
    } catch {
      // setup then reopens on its first screen
    }
    window.location.reload();
  }

  async function lookForExtension(): Promise<boolean> {
    if ((await recheckPlatform()) !== null) {
      extensionFound = true;
    }
    return extensionFound;
  }

  $effect(() => {
    if (step !== "extension" || extensionFound) {
      return;
    }
    const timer = setInterval(() => void lookForExtension(), EXTENSION_POLL_MS);
    // coming back from the Web Store tab
    const onVisible = async () => {
      if (
        document.visibilityState === "visible" &&
        !(await lookForExtension())
      ) {
        reloadForExtension();
      }
    };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  });

  function leaveExtensionStep(): void {
    if (!extension) {
      onextension();
    }
    go("signin");
  }

  function go(target: Step): void {
    error = null;
    step = target;
    if (target === "channels" && !channelsLoaded) {
      void loadChannels();
    }
  }

  async function signIn(): Promise<void> {
    if (await session.signIn()) {
      if (session.setupDone) {
        return;
      }
      go("channels");
    }
  }

  async function loadChannels(): Promise<void> {
    let store = session.store;
    if (!store) {
      return;
    }
    loadingChannels = true;
    try {
      const token = await getValidToken();
      try {
        await store.load();
      } catch (caught) {
        if (!(caught instanceof ProfileDeletedError) || !session.store) {
          throw caught;
        }
        // the session opened an empty store; setup runs in full on it
        store = session.store;
        await store.load();
      }
      if (store.profileFound) {
        // the account was set up before, here or on another device
        session.finishSetup();
        return;
      }
      const subscribed = await fetchSubscriptions(token);
      const followed = store.followedIds();
      const info =
        followed.length > 0 ? await channelInfo(followed, token) : undefined;
      channels = Array.from(store.channels(subscribed, info).values()).sort(
        (left, right) => left.title.localeCompare(right.title),
      );
      enabled = Object.fromEntries(
        channels.map((channel) => [channel.channelId, channel.filter.enabled]),
      );
      startingShorts = mostCommonShorts(
        channels.map((channel) => channel.filter),
      );
      shortsDefault = startingShorts;
      channelsLoaded = true;
    } catch (caught) {
      error = (caught as Error).message;
    } finally {
      loadingChannels = false;
    }
  }

  function saveFilters(
    change: (channel: Channel) => Partial<Channel["filter"]>,
  ): void {
    const store = session.store;
    channels = channels.map((channel) => {
      const changes = Object.entries(change(channel));
      if (changes.every(([key, value]) => channel.filter[key] === value)) {
        return channel;
      } else {
        const filter = { ...channel.filter, ...Object.fromEntries(changes) };
        store?.setFilter(channel.channelId, filter);
        return { ...channel, filter };
      }
    });
  }

  function prefetchOn(): void {
    prefetch.fetchOnly(channels.filter((channel) => channel.filter.enabled));
  }

  function saveChannels(): void {
    saveFilters((channel) => ({ enabled: enabled[channel.channelId] ?? true }));
    prefetchOn();
    go("shorts");
  }

  function saveShorts(): void {
    if (shortsDefault !== startingShorts) {
      saveFilters(() => ({ shortsFilter: shortsDefault }));
      startingShorts = shortsDefault;
    }
    // a Shorts choice that filters needs the Shorts lists the prefetch left out
    prefetchOn();
    go("start");
  }

  function finish(): void {
    if (session.account) {
      keepPendingStart(session.account.channelId, startFrom);
      handOffPrefetched(session.account.channelId, prefetch);
    }
    session.finishSetup();
  }

  // svelte-ignore state_referenced_locally
  if (start === "channels") {
    void loadChannels();
  }
</script>

{#snippet shortsChoice()}
  <div class="filter-group controls">
    <ChoiceRow
      label="Shorts"
      options={SHORTS_OPTIONS}
      value={shortsDefault}
      onchange={(value) => {
        shortsDefault = value;
      }}
    />
  </div>
{/snippet}

<div class="page">
  <header class="brand"><Logo /> SubTube</header>
  <main>
    <div class="frame">
      <nav aria-label="Setup steps">
        <ol>
          {#each LABELS as label, position (label)}
            {@const done = position < index}
            {@const current = position === index}
            <li aria-current={current ? "step" : undefined} class:current>
              {#if done}
                <span class="step-done"
                  ><Icon name="check" size={14} strokeWidth={3} /></span
                >
              {:else}
                <span class="step-number" class:current>{position + 1}</span>
              {/if}
              {label}
            </li>
          {/each}
        </ol>
      </nav>

      <section>
        {#if step === "intro"}
          <div class="content">
            <div class="wordmark"><Logo hull={36} /> SubTube</div>
            <h1>Your subscriptions, your filters, no algorithm.</h1>
            <ul class="points">
              <li>
                <Icon name="tv" size={22} color="var(--gold)" />
                New videos from the channels you subscribe to, latest first.
              </li>
              <li>
                <Icon name="filter" size={22} color="var(--gold)" />
                Filters for each channel hide Shorts, live streams, or titles
                you don't want.
              </li>
              <li>
                <Icon name="eye" size={22} color="var(--gold)" />
                What you've watched is remembered on all your devices.
              </li>
            </ul>
          </div>
          <div class="actions end">
            <button
              type="button"
              class="button-primary"
              onclick={() => go("extension")}
            >
              Get started
            </button>
          </div>
        {:else if step === "extension"}
          <div class="content">
            <span class="badge-icon"
              ><Icon name="puzzle" size={28} strokeWidth={1.75} /></span
            >
            <h1>Add the Chrome extension</h1>
            <p class="lead">
              SubTube needs its extension to keep you signed in to Google and to
              check which videos are Shorts.
            </p>
            <ul class="checks">
              <li>
                <Icon name="check" size={20} color="var(--gold)" />
                It only works with SubTube and YouTube.
              </li>
              <li>
                <Icon name="check" size={20} color="var(--gold)" />
                It has no buttons or pages of its own.
              </li>
            </ul>
            {#if extensionFound}
              <p role="status" class="added">
                <Icon name="check" size={20} strokeWidth={2.5} />
                Extension added
              </p>
            {:else}
              <div class="install">
                <a
                  class="button-primary"
                  href={chromeWebStoreUrl}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  <Icon name="plus" size={18} />
                  Add to Chrome
                </a>
                <p class="secondary small">
                  Already added it?
                  <a
                    href={window.location.href}
                    onclick={(event) => {
                      event.preventDefault();
                      reloadForExtension();
                    }}
                    >Reload this page.</a
                  >
                </p>
              </div>
            {/if}
          </div>
          <div class="actions">
            <button
              type="button"
              class="button-quiet"
              onclick={() => go("intro")}
            >
              Back
            </button>
            <button
              type="button"
              class="button-primary push"
              disabled={!extensionFound}
              onclick={leaveExtensionStep}
            >
              Next
            </button>
          </div>
        {:else if step === "signin"}
          <div class="content">
            <h1>Sign in with Google</h1>
            <p class="lead">SubTube asks Google for two permissions:</p>
            <div class="permissions">
              <div class="permission">
                <Icon name="tv" size={24} color="var(--gold)" />
                <strong>Read your YouTube subscriptions</strong>
                <span class="secondary"
                  >So it knows which channels to show. It can't change anything
                  on your YouTube account.</span
                >
              </div>
              <div class="permission">
                <Icon name="folder" size={24} color="var(--gold)" />
                <strong>Keep its settings in your Google Drive</strong>
                <span class="secondary"
                  >In a hidden folder that only SubTube can open. It holds your
                  filters and what you've watched. SubTube can't see your other
                  files.</span
                >
              </div>
            </div>
            <p class="secondary small">
              SubTube has no server of its own. Your data stays in your Google
              account and on this device.
            </p>
            {#if session.error}
              <p class="error-text">{session.error}</p>
            {/if}
          </div>
          <div class="actions">
            <button
              type="button"
              class="button-quiet"
              onclick={() => go("extension")}
            >
              Back
            </button>
            <button
              type="button"
              class="button-primary push google"
              disabled={session.connecting}
              onclick={() => void signIn()}
            >
              <span class="g" aria-hidden="true">G</span>
              Sign in with Google
            </button>
          </div>
          <p class="agree secondary small">
            By signing in, you agree to SubTube's
            <a href={termsUrl} target="_blank" rel="noopener noreferrer"
              >Terms</a
            >
            and
            <a href={privacyUrl} target="_blank" rel="noopener noreferrer"
              >Privacy Policy</a
            >.
          </p>
        {:else if step === "channels"}
          <div class="content tight">
            {#if !channelsLoaded}
              {#if loadingChannels}
                <div class="channel-grid shimmer" aria-busy="true">
                  {#each SKELETON_ROWS as index (index)}
                    <div class="channel-row" aria-hidden="true">
                      <span class="skeleton-block skeleton-avatar"></span>
                      <span class="skeleton-block skeleton-name"></span>
                      <span class="skeleton-block skeleton-switch"></span>
                    </div>
                  {/each}
                </div>
              {:else if error}
                <p class="error-text">{error}</p>
              {/if}
            {:else}
              <h1>Choose channels</h1>
              <p class="lead">
                Your subscriptions start on. Turn off any you don't want in your
                feed.
              </p>
              <div class="search-row">
                <label for="nux-search" class="visually-hidden"
                  >Search channels</label
                >
                <div class="search-field">
                  <Icon name="search" size={18} />
                  <input
                    id="nux-search"
                    placeholder="Search channels"
                    bind:value={query}
                  >
                </div>
                <button
                  type="button"
                  class="toggle-all"
                  onclick={() => {
                    const turnOn = onCount === 0;
                    enabled = Object.fromEntries(
                      channels.map((channel) => [channel.channelId, turnOn]),
                    );
                  }}
                >
                  {onCount > 0 ? "Turn all off" : "Turn all on"}
                </button>
              </div>
              {#if channels.length === 0}
                <p class="secondary">
                  You don't subscribe to any channels yet. Subscribe on YouTube
                  and they'll show up here.
                </p>
              {/if}
              <div class="channel-grid">
                {#each shownChannels as channel (channel.channelId)}
                  {@const on = enabled[channel.channelId] ?? true}
                  <div class="channel-row" class:off={!on}>
                    <Avatar
                      title={channel.title}
                      thumbnail={channel.thumbnail}
                      size={24}
                    />
                    <span class="channel-title">{channel.title}</span>
                    <Switch
                      checked={on}
                      label={`Show ${channel.title} in feed`}
                      onchange={(checked) => {
                        enabled[channel.channelId] = checked;
                      }}
                    />
                  </div>
                {/each}
              </div>
            {/if}
          </div>
          <div class="actions">
            <button
              type="button"
              class="button-quiet"
              onclick={() => go("signin")}
            >
              Back
            </button>
            <span class="secondary count push">
              {#if channelsLoaded}
                {onCount}
                of {channels.length} on
              {/if}
            </span>
            <button
              type="button"
              class="button-primary"
              disabled={!channelsLoaded}
              onclick={saveChannels}
            >
              Next
            </button>
          </div>
        {:else if step === "shorts"}
          <div class="content">
            <h1>Shorts</h1>
            <p class="lead">
              This applies to every channel. You can change it for a single
              channel under Channels.
            </p>
            {@render shortsChoice()}
          </div>
          <div class="actions">
            <button
              type="button"
              class="button-quiet"
              onclick={() => go("channels")}
            >
              Back
            </button>
            <button
              type="button"
              class="button-primary push"
              onclick={saveShorts}
            >
              Next
            </button>
          </div>
        {:else if step === "start"}
          <div class="content">
            <h1>Where to start</h1>
            <p class="lead">Older videos are marked as watched.</p>
            <div class="filter-group controls">
              <ChoiceRow
                label="Where to start"
                options={START_OPTIONS}
                value={startFrom}
                onchange={(value) => {
                  startFrom = value;
                }}
              />
            </div>
          </div>
          <div class="actions">
            <button
              type="button"
              class="button-quiet"
              onclick={() => go("shorts")}
            >
              Back
            </button>
            <button
              type="button"
              class="button-primary push"
              onclick={() => go("done")}
            >
              Next
            </button>
          </div>
        {:else}
          <div class="content centered">
            <span class="done-icon"
              ><Icon name="check" size={32} strokeWidth={2.5} /></span
            >
            <h1>You're set</h1>
            <p class="lead narrow">
              Your feed starts with the latest video you haven't watched. Click
              one to play it.
            </p>
          </div>
          <div class="actions end">
            <button type="button" class="button-primary" onclick={finish}>
              Open my feed
            </button>
          </div>
        {/if}
      </section>
    </div>
  </main>
  <footer>
    <a href={privacyUrl} target="_blank" rel="noopener noreferrer"
      >Privacy policy</a
    >
    <a href={termsUrl} target="_blank" rel="noopener noreferrer">Terms</a>
  </footer>
</div>

<style>
  .page {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    background: var(--surface);
  }

  header {
    padding: 16px 24px;
  }

  main {
    flex: 1;
    display: grid;
    place-items: center;
    padding: 16px 16px 24px;
  }

  footer {
    display: flex;
    justify-content: center;
    gap: 12px;
    padding: 0 16px 20px;
    font-size: 12px;
  }

  .agree {
    text-align: right;
  }

  .frame {
    width: 100%;
    max-width: 920px;
    min-height: 620px;
    display: flex;
    flex-wrap: wrap;
    overflow: hidden;
    border: 1px solid var(--border);
    border-radius: 16px;
    background: var(--page);
  }

  nav {
    flex: 1 1 288px;
    padding: 32px;
    background: var(--surface-raised);
    border-right: 1px solid var(--border);
  }

  ol {
    margin: 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 16px;
    font-size: 15px;
  }

  ol li {
    display: flex;
    align-items: center;
    gap: 12px;
    color: var(--text-secondary);
  }

  ol li.current {
    color: var(--text);
    font-weight: 600;
  }

  .step-done {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: var(--sunflower);
    color: var(--ink);
  }

  .step-number {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    border: 2px solid var(--switch-off);
    color: var(--switch-off);
    font-size: 12px;
    font-weight: 400;
  }

  .step-number.current {
    border-color: var(--gold);
    color: var(--gold);
  }

  section {
    flex: 999 1 440px;
    min-width: 0;
    padding: 40px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  @media (max-width: 520px) {
    nav,
    section {
      padding: 24px;
    }
  }

  .content {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .content.tight {
    gap: 14px;
  }

  .content.centered {
    justify-content: center;
    gap: 18px;
  }

  .wordmark {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 30px;
    line-height: 36px;
    font-weight: 700;
  }

  h1 {
    margin: 0;
    font-size: 30px;
    line-height: 36px;
    font-weight: 700;
  }

  .lead {
    margin: 0;
    font-size: 16px;
    line-height: 24px;
    color: var(--text-secondary);
  }

  .narrow {
    max-width: 460px;
  }

  .small {
    margin: 0;
    font-size: 13px;
    line-height: 18px;
  }

  .points,
  .checks {
    margin: 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
  }

  .points {
    gap: 18px;
  }

  .points li {
    display: flex;
    gap: 14px;
    align-items: flex-start;
    font-size: 16px;
    line-height: 22px;
    color: var(--text-secondary);
  }

  .checks {
    gap: 10px;
  }

  .checks li {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    font-size: 15px;
    line-height: 21px;
  }

  .badge-icon {
    display: grid;
    place-items: center;
    width: 52px;
    height: 52px;
    border-radius: 14px;
    background: var(--tint);
    color: var(--gold);
  }

  .install {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
  }

  .added {
    margin: 0;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 12px 14px;
    border-radius: 10px;
    background: var(--tint);
    color: var(--tint-text);
    font-size: 15px;
    font-weight: 600;
  }

  .actions {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .actions.end {
    justify-content: flex-end;
  }

  .push {
    margin-left: auto;
  }

  .google {
    padding: 0 24px;
    gap: 10px;
  }

  .g {
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: #ffffff;
    color: #8a6100;
    font-size: 14px;
    font-weight: 800;
  }

  .permissions {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(min(220px, 100%), 1fr));
    gap: 12px;
  }

  .permission {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 18px;
    border-radius: 12px;
    background: var(--surface);
    font-size: 14px;
    line-height: 20px;
  }

  .permission strong {
    font-size: 16px;
  }

  .search-row {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .search-row .search-field {
    flex: 1;
  }

  .search-row input {
    font-size: 15px;
  }

  .toggle-all {
    min-height: 40px;
    padding: 0 8px;
    border: 0;
    background: transparent;
    font-size: 14px;
    font-weight: 500;
    text-decoration: underline;
  }

  .channel-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(220px, 100%), 1fr));
    column-gap: 20px;
  }

  .channel-row {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    border-bottom: 1px solid var(--border);
    font-size: 14px;
  }

  .channel-row.off > :global(:not(.switch)) {
    opacity: 0.45;
  }

  .skeleton-avatar {
    width: 24px;
    height: 24px;
    border-radius: 50%;
  }

  .skeleton-name {
    flex: 1;
    max-width: 140px;
    height: 12px;
    margin-right: auto;
  }

  .skeleton-switch {
    width: 36px;
    height: 20px;
    border-radius: 10px;
  }

  .channel-title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .count {
    font-size: 14px;
  }

  .controls {
    max-width: 360px;
  }

  .done-icon {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    border-radius: 50%;
    background: var(--tint);
    color: var(--gold);
  }
</style>
