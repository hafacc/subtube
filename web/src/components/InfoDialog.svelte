<script lang="ts">
  import { Dialog } from "bits-ui";
  import { infoPage } from "../lib/info-page.svelte";
  import { INFO_PAGES, updatedLabel } from "../lib/pages";
  import Icon from "./Icon.svelte";
  import PageText from "./PageText.svelte";

  // kept while the dialog fades out
  let shown = $state(INFO_PAGES.privacy);
  $effect(() => {
    if (infoPage.open !== null) {
      shown = INFO_PAGES[infoPage.open];
    }
  });
</script>

<Dialog.Root
  open={infoPage.open !== null}
  onOpenChange={(open) => {
    if (!open) {
      infoPage.open = null;
    }
  }}
>
  <Dialog.Overlay>
    {#snippet child({
      props: overlay,
    })}
      <div {...overlay} class="backdrop fades">
        <Dialog.Content forceMount preventScroll={false}>
          {#snippet child({
            props: content,
          })}
            <div {...content} class="sheet" style:contain="none">
              <header>
                <Dialog.Title level={2}>
                  {#snippet child({
                    props: title,
                  })}
                    <h2 {...title}>{shown.title}</h2>
                  {/snippet}
                </Dialog.Title>
                <a
                  class="icon-button"
                  href={shown.web}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label="Open on the web"
                  title="Open on the web"
                >
                  <Icon name="external" size={18} />
                </a>
                <Dialog.Close>
                  {#snippet child({
                    props: close,
                  })}
                    <button
                      {...close}
                      type="button"
                      class="icon-button"
                      aria-label="Close"
                      title="Close"
                    >
                      <Icon name="close" size={18} />
                    </button>
                  {/snippet}
                </Dialog.Close>
              </header>
              <div class="body">
                <p class="updated">{updatedLabel(shown.updated)}</p>
                <PageText page={shown} level={3} />
              </div>
            </div>
          {/snippet}
        </Dialog.Content>
      </div>
    {/snippet}
  </Dialog.Overlay>
</Dialog.Root>

<style>
  /* under the player in a wide window (29, 30), over it in a narrow one (11), as Settings is */
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 25;
    display: grid;
    place-items: center;
    padding: 16px;
    background: var(--scrim);
  }

  .sheet {
    width: 100%;
    max-width: 640px;
    max-height: min(720px, calc(100vh - 32px));
    display: flex;
    flex-direction: column;
    border: 1px solid var(--border);
    border-radius: 12px;
    background: var(--page);
    box-shadow: 0 12px 32px var(--shadow);
    overflow: hidden;
  }

  header {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 16px 16px 8px 24px;
  }

  h2 {
    flex: 1;
    min-width: 0;
    margin: 0;
    font-size: 22px;
    line-height: 28px;
    text-wrap: balance;
  }

  .body {
    padding: 0 24px 24px;
    overflow-y: auto;
    font-size: 15px;
    line-height: 1.6;
    overflow-wrap: break-word;
    user-select: text;
  }

  .updated {
    margin: 0 0 16px;
    color: var(--text-secondary);
    font-size: 13px;
  }

  .body :global(p) {
    margin: 12px 0;
  }

  .body :global(h3) {
    margin: 24px 0 4px;
    font-size: 16px;
    line-height: 24px;
  }

  .body :global(ul) {
    margin: 0;
    padding-left: 1.25em;
  }

  .body :global(li) {
    margin: 6px 0;
  }
</style>
