<script lang="ts">
  import type { FeedController } from "../lib/feed.svelte";
  import { filterGroups, groupName } from "../lib/groups";
  import { compareIgnoringCase } from "../lib/text-order";
  import Avatar from "./Avatar.svelte";
  import Icon from "./Icon.svelte";
  import Switch from "./Switch.svelte";

  let {
    feed,
    group,
    onclose,
  }: {
    /** the feed whose channels are grouped */
    feed: FeedController;
    /** the group to edit by its name, or null for a new one */
    group: string | null;
    /** called to close the editor: after "Save", "Cancel" and "Delete group" */
    onclose: () => void;
  } = $props();

  // svelte-ignore state_referenced_locally
  let field = $state(group ?? "");
  // the channels switched on, which nothing saves until "Save"
  // svelte-ignore state_referenced_locally
  let members: ReadonlySet<string> = $state.raw(
    new Set(
      Array.from(feed.channels.values())
        .filter(
          (channel) =>
            group !== null && filterGroups(channel.filter).includes(group),
        )
        .map((channel) => channel.channelId),
    ),
  );

  const name = $derived(groupName(field));
  const existing = $derived(group !== null && feed.groups.includes(group));
  const channels = $derived(
    Array.from(feed.channels.values()).toSorted((left, right) =>
      compareIgnoringCase(left.title, right.title),
    ),
  );
  function toggle(channelId: string, member: boolean): void {
    const next = new Set(members);
    if (member) {
      next.add(channelId);
    } else {
      next.delete(channelId);
    }
    members = next;
  }

  function save(): void {
    if (name !== null && members.size > 0) {
      feed.saveGroup(group, name, Array.from(members));
      onclose();
    }
  }
</script>

<div class="editor">
  <h2>{group === null ? "New group" : "Edit group"}</h2>
  <div class="filter-group">
    <label class="label" for="group-name">Name</label>
    <input
      id="group-name"
      type="text"
      class="text-input"
      autocomplete="off"
      bind:value={field}
    >
  </div>

  <div class="filter-group channels">
    <span class="label">Channels</span>
    <div class="rows">
      {#each channels as channel (channel.channelId)}
        <div class="channel-row" class:off={!channel.filter.enabled}>
          <Avatar
            title={channel.title}
            thumbnail={channel.thumbnail}
            size={24}
          />
          <span class="channel-title">{channel.title}</span>
          <Switch
            checked={members.has(channel.channelId)}
            label={channel.title}
            onchange={(member) => toggle(channel.channelId, member)}
          />
        </div>
      {/each}
    </div>
  </div>

  <div class="actions">
    {#if existing && group !== null}
      {@const deleted = group}
      <button
        type="button"
        class="button-compact destructive"
        onclick={() => {
          feed.deleteGroup(deleted);
          onclose();
        }}
      >
        <Icon name="trash" />
        Delete group
      </button>
    {/if}
    <button type="button" class="button-compact cancel" onclick={onclose}>
      Cancel
    </button>
    <button
      type="button"
      class="button-compact primary"
      disabled={name === null || members.size === 0}
      onclick={save}
    >
      Save
    </button>
  </div>
</div>

<style>
  /* fills the panel: only the channel rows scroll */
  .editor {
    display: flex;
    flex-direction: column;
    gap: 12px;
    height: 100%;
    padding: 12px 12px 0;
  }

  .editor > * {
    flex-shrink: 0;
  }

  /* as the filter editor's heading */
  h2 {
    margin: 2px 0 0;
    font-size: 17px;
    line-height: 22px;
    font-weight: 700;
  }

  .label {
    font-weight: 500;
  }

  /* never shorter than its heading and one row */
  .editor > .channels {
    flex: 1 1 0;
    min-height: 96px;
  }

  .rows {
    flex: 1 1 0;
    min-height: 44px;
    overflow-y: auto;
  }

  .actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .cancel {
    margin-left: auto;
  }
</style>
