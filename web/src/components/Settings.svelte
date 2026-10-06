<script module lang="ts">
  import type { DriveUser } from "../lib/drive";

  // by account channel id, so reopening the popover doesn't ask again
  const users = new Map<string, DriveUser>();
</script>

<script lang="ts">
  import { onMount } from "svelte";
  import { getValidToken } from "../lib/auth";
  import { privacyUrl, termsUrl } from "../lib/config";
  import { fetchDriveUser } from "../lib/drive";
  import type { ChannelSummary } from "../lib/youtube";
  import Avatar from "./Avatar.svelte";
  import Icon from "./Icon.svelte";

  let {
    account,
    lastSynced,
    onsignout,
    ondelete,
    onclose,
  }: {
    /** the signed-in account's channel */
    account: ChannelSummary;
    /** when Drive last answered, in epoch milliseconds */
    lastSynced: number | null;
    /** sign out */
    onsignout: () => void;
    /** delete the profile everywhere; rejects when Drive can't be reached */
    ondelete: () => Promise<void>;
    /** close the popover */
    onclose: () => void;
  } = $props();

  const RELATIVE = new Intl.RelativeTimeFormat(undefined, { numeric: "auto" });

  let now = $state(Date.now());
  // svelte-ignore state_referenced_locally
  let user: DriveUser | null = $state(users.get(account.channelId) ?? null);
  let panel: HTMLElement;
  let confirming = $state(false);
  let deleting = $state(false);
  let deleteFailed = $state(false);

  async function deleteProfile(): Promise<void> {
    deleting = true;
    deleteFailed = false;
    try {
      await ondelete();
    } catch (caught) {
      console.error(caught);
      deleteFailed = true;
    } finally {
      deleting = false;
    }
  }

  function ago(time: number): string {
    const seconds = Math.round((time - now) / 1000);
    if (seconds > -60) {
      return RELATIVE.format(0, "second");
    } else if (seconds > -3600) {
      return RELATIVE.format(Math.round(seconds / 60), "minute");
    } else if (seconds > -86400) {
      return RELATIVE.format(Math.round(seconds / 3600), "hour");
    } else {
      return RELATIVE.format(Math.round(seconds / 86400), "day");
    }
  }

  onMount(() => {
    if (!user) {
      const channelId = account.channelId;
      void (async () => {
        try {
          const found = await fetchDriveUser(await getValidToken());
          users.set(channelId, found);
          user = found;
        } catch {
          // the channel's name stays
        }
      })();
    }
    const timer = setInterval(() => {
      now = Date.now();
    }, 30_000);
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Element;
      if (
        !panel.contains(target) &&
        !target.closest("[data-settings-toggle]")
      ) {
        onclose();
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || deleting) {
        return;
      } else if (confirming) {
        confirming = false;
      } else {
        onclose();
      }
    };
    document.addEventListener("pointerdown", onPointerDown);
    window.addEventListener("keydown", onKeyDown);
    return () => {
      clearInterval(timer);
      document.removeEventListener("pointerdown", onPointerDown);
      window.removeEventListener("keydown", onKeyDown);
    };
  });
</script>

<section aria-label="Settings" bind:this={panel}>
  <div class="who">
    <Avatar
      title={account.title}
      thumbnail={account.thumbnail}
      size={40}
      tint
    />
    <span class="names">
      <span class="name">{user?.displayName ?? account.title}</span>
      {#if user?.emailAddress}
        <span class="secondary handle">{user.emailAddress}</span>
      {/if}
    </span>
  </div>

  <div class="box">
    <Icon name="cloudCheck" size={20} />
    <div class="box-text">
      <strong>Synced with Google Drive</strong>
      {#if lastSynced !== null}
        <span class="secondary">Last synced {ago(lastSynced)}</span>
      {:else}
        <span class="secondary">Syncing…</span>
      {/if}
      <span class="secondary"
        >Your channels, filters and watched list are kept in a hidden SubTube
        folder in your Drive.</span
      >
    </div>
  </div>

  <div class="box">
    <Icon name="puzzle" size={20} />
    <div class="box-text">
      <strong>Chrome extension</strong>
      <span class="secondary"
        >Installed. Keeps you signed in and checks for Shorts.</span
      >
    </div>
  </div>

  <div class="sign-out">
    <button type="button" onclick={onsignout}>
      <Icon name="signOut" />
      Sign out
    </button>
    <p class="secondary">
      Your settings stay in your Drive. Sign back in to get them.
    </p>
  </div>

  <div class="delete">
    <button
      type="button"
      onclick={() => {
        deleteFailed = false;
        confirming = true;
      }}
    >
      <Icon name="trash" />
      Delete profile
    </button>
    <p class="secondary">
      Deletes your filters, followed channels and watched marks from Google
      Drive, on all your devices. Your YouTube account isn't changed.
    </p>
  </div>

  <div class="legal">
    <a href={privacyUrl} target="_blank" rel="noopener noreferrer">
      Privacy policy
    </a>
    <a href={termsUrl} target="_blank" rel="noopener noreferrer">Terms</a>
  </div>

  {#if confirming}
    <div class="backdrop">
      <div
        class="confirm"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="delete-title"
        aria-describedby="delete-text"
      >
        <h2 id="delete-title">Delete your profile?</h2>
        <p id="delete-text">
          This deletes your filters, followed channels and watched marks from
          Google Drive and from this device. It can't be undone.
        </p>
        {#if deleteFailed}
          <p class="error-text" role="alert">
            Couldn't delete your profile. Check your connection and try again.
          </p>
        {/if}
        <div class="confirm-actions">
          <button
            type="button"
            class="button-quiet"
            disabled={deleting}
            onclick={() => {
              confirming = false;
            }}
          >
            Cancel
          </button>
          <button
            type="button"
            class="destructive"
            disabled={deleting}
            onclick={() => void deleteProfile()}
          >
            Delete profile
          </button>
        </div>
      </div>
    </div>
  {/if}
</section>

<style>
  section {
    position: absolute;
    top: 56px;
    right: 12px;
    left: 12px;
    z-index: 15;
    margin-left: auto;
    max-width: 360px;
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px;
    border: 1px solid var(--border);
    border-radius: 12px;
    background: var(--page);
    box-shadow: 0 12px 32px var(--shadow);
  }

  .who {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .names {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .name {
    font-size: 15px;
    font-weight: 600;
  }

  .handle {
    font-size: 13px;
  }

  .box {
    display: flex;
    gap: 12px;
    padding: 12px;
    border-radius: 10px;
    background: var(--surface);
  }

  .box-text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
    font-size: 13px;
    line-height: 18px;
  }

  strong {
    font-size: 14px;
  }

  .sign-out,
  .delete {
    display: flex;
    flex-direction: column;
    gap: 6px;
    border-top: 1px solid var(--border);
    padding-top: 12px;
  }

  .sign-out button,
  .delete button {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 36px;
    padding: 0 8px;
    border: 0;
    border-radius: 6px;
    background: transparent;
    color: var(--gold);
    font-size: 14px;
    font-weight: 600;
    text-align: left;
  }

  .delete button {
    color: var(--error);
  }

  .sign-out button:hover,
  .delete button:hover {
    background: var(--surface);
  }

  .sign-out p,
  .delete p {
    margin: 0;
    padding: 0 8px;
    font-size: 12px;
    line-height: 17px;
  }

  .legal {
    display: flex;
    gap: 12px;
    padding: 0 8px;
    font-size: 12px;
  }

  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 40;
    display: grid;
    place-items: center;
    padding: 16px;
    background: rgba(0, 0, 0, 0.5);
  }

  .confirm {
    width: 100%;
    max-width: 400px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: 20px;
    border-radius: 12px;
    background: var(--page);
    box-shadow: 0 12px 32px var(--shadow);
  }

  .confirm h2 {
    margin: 0;
    font-size: 18px;
    font-weight: 600;
  }

  .confirm p {
    margin: 0;
    font-size: 14px;
    line-height: 20px;
  }

  .confirm-actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  .destructive {
    min-height: 40px;
    padding: 0 16px;
    border: 0;
    border-radius: 8px;
    background: var(--error);
    color: var(--page);
    font-size: 14px;
    font-weight: 600;
  }

  .destructive:disabled {
    opacity: 0.5;
  }
</style>
