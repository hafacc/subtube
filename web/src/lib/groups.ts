import { topicLabel } from "./chips";
import { defaultFilter } from "./sync-merge";
import { compareCodePoints, compareIgnoringCase } from "./text-order";
import type { ChannelFilter } from "./types";

/** The most code points a group's name has. */
export const GROUP_NAME_MAX = 24;

/** The two synced settings that hold selected group chips. */
export type GroupSetting = "groupChips" | "channelGroupChips";

/** The selected group chips of both rows, as the settings hold them. */
export type GroupSelections = Readonly<Record<GroupSetting, readonly string[]>>;

/** What a group edit saves: the changed filters by channel id, and the changed settings. */
export interface GroupEdit {
  /** each changed channel's whole filter */
  channels: Record<string, ChannelFilter>;
  /** each changed setting's new value */
  settings: Partial<Record<GroupSetting, string[]>>;
}

// Unicode's White_Space code points, spelled out so every client trims alike
const SPACE =
  "\\u0009-\\u000d\\u0020\\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000";
const OUTER_SPACE = new RegExp(`^[${SPACE}]+|[${SPACE}]+$`, "g");

/**
 * Typed text as a group's name: white space at either end removed; null
 * unless 1 to {@link GROUP_NAME_MAX} code points are left.
 */
export function groupName(text: string): string | null {
  const name = text.replace(OUTER_SPACE, "");
  const { length } = Array.from(name);
  return length >= 1 && length <= GROUP_NAME_MAX ? name : null;
}

/**
 * The groups a saved filter puts its channel in, each once, in the order
 * written: the strings of `groups` that are a name as they stand. A `groups`
 * that is not an array, or holds anything but strings, is none.
 */
export function filterGroups(filter: ChannelFilter): string[] {
  const raw: unknown = filter.groups;
  if (Array.isArray(raw) && raw.every((name) => typeof name === "string")) {
    return Array.from(
      new Set(raw.filter((name: string) => groupName(name) === name)),
    );
  } else {
    return [];
  }
}

/** Order two group names as their chips go: ignoring case, then by code point. */
export function compareGroupNames(left: string, right: string): number {
  return compareIgnoringCase(left, right) || compareCodePoints(left, right);
}

/** The groups that exist, in chip order: every name a listed channel's filter has. */
export function groupNames(filters: Iterable<ChannelFilter>): string[] {
  return Array.from(
    new Set(Array.from(filters).flatMap(filterGroups)),
  ).toSorted(compareGroupNames);
}

/** The selected names that are existing groups, in chip order. */
export function selectedGroups(
  existing: readonly string[],
  selected: readonly string[],
): string[] {
  return existing.filter((name) => selected.includes(name));
}

/** What stands in a chip row's title while it has groups or topics selected. */
export interface ChipTitle {
  /** the selected groups' names, then the selected topics' labels; empty for the usual title */
  names: string[];
  /** the group the title's "Edit group" button opens: the only selected one, else null */
  edit: string | null;
}

/**
 * A chip row's title: its selected existing groups, then its selected
 * topics, each in chip order. `groups` and `topics` are the row's group and
 * topic chips in order, `groupChips` and `topicChips` its two settings.
 */
export function chipTitle(
  groups: readonly string[],
  groupChips: readonly string[],
  topics: readonly string[],
  topicChips: readonly string[],
): ChipTitle {
  const selected = selectedGroups(groups, groupChips);
  return {
    names: [
      ...selected,
      ...topics
        .filter((categoryId) => topicChips.includes(categoryId))
        .map(topicLabel)
        .filter((label) => label !== null),
    ],
    edit: selected.length === 1 ? selected[0] : null,
  };
}

/**
 * The channels the selected groups keep, by id: those in any selected
 * existing group. Null when none is selected, which keeps every channel.
 * `filters` is every listed channel's filter by its id.
 */
export function groupKeptChannels(
  filters: ReadonlyMap<string, ChannelFilter>,
  selected: readonly string[],
): Set<string> | null {
  const wanted = new Set(
    selectedGroups(groupNames(filters.values()), selected),
  );
  if (wanted.size === 0) {
    return null;
  } else {
    return new Set(
      Array.from(filters)
        .filter(([, filter]) =>
          filterGroups(filter).some((name) => wanted.has(name)),
        )
        .map(([channelId]) => channelId),
    );
  }
}

/** The ids two sets of kept channels both keep; null, which keeps all, when both are. */
export function keptByBoth(
  left: ReadonlySet<string> | null,
  right: ReadonlySet<string> | null,
): Set<string> | null {
  if (left === null || right === null) {
    const kept = left ?? right;
    return kept === null ? null : new Set(kept);
  } else {
    return new Set(Array.from(left).filter((id) => right.has(id)));
  }
}

function withGroups(filter: ChannelFilter, groups: string[]): ChannelFilter {
  return { ...filter, groups };
}

function sameNames(left: readonly string[], right: readonly string[]): boolean {
  return (
    left.length === right.length &&
    left.every((name, index) => name === right[index])
  );
}

/** Every saved filter `change` gives other groups, with the groups it gives. */
function regrouped(
  saved: Readonly<Record<string, ChannelFilter>>,
  change: (groups: string[]) => string[],
): Record<string, ChannelFilter> {
  const changed: Record<string, ChannelFilter> = {};
  for (const [channelId, filter] of Object.entries(saved)) {
    const groups = filterGroups(filter);
    const next = change(groups);
    if (!sameNames(groups, next)) {
      changed[channelId] = withGroups(filter, next);
    }
  }
  return changed;
}

function reselected(
  selections: GroupSelections,
  change: (selected: readonly string[]) => string[],
): Partial<Record<GroupSetting, string[]>> {
  const changed: Partial<Record<GroupSetting, string[]>> = {};
  for (const setting of ["groupChips", "channelGroupChips"] as const) {
    const next = change(selections[setting]);
    if (!sameNames(selections[setting], next)) {
      changed[setting] = next;
    }
  }
  return changed;
}

/**
 * Delete a group: its name leaves every saved filter that has it and both
 * settings. `saved` is every saved filter by channel id, listed or not.
 */
export function deleteGroup(
  saved: Readonly<Record<string, ChannelFilter>>,
  selections: GroupSelections,
  group: string,
): GroupEdit {
  const without = (names: readonly string[]): string[] =>
    names.filter((name) => name !== group);
  return {
    channels: regrouped(saved, without),
    settings: reselected(selections, without),
  };
}

/**
 * Rename a group on every saved filter that has it and in both settings;
 * a filter or setting that already has the new name keeps it once, where it
 * came first. Nothing changes unless `to` is a name other than `from`.
 */
export function renameGroup(
  saved: Readonly<Record<string, ChannelFilter>>,
  selections: GroupSelections,
  from: string,
  to: string,
): GroupEdit {
  if (groupName(to) !== to || from === to) {
    return { channels: {}, settings: {} };
  } else {
    const renamed = (names: readonly string[]): string[] => {
      if (names.includes(from)) {
        const moved = names.map((name) => (name === from ? to : name));
        return moved.filter(
          (name, index) => name !== to || moved.indexOf(to) === index,
        );
      } else {
        return Array.from(names);
      }
    };
    return {
      channels: regrouped(saved, renamed),
      settings: reselected(selections, renamed),
    };
  }
}

/**
 * Put channels in a group, or take them out. A channel with no saved filter
 * gets the default one; a new name goes last in the filter's `groups`.
 * Taking out the last of the `listed` channels in the group deletes it
 * ({@link deleteGroup}).
 */
export function setMembers(
  saved: Readonly<Record<string, ChannelFilter>>,
  listed: readonly string[],
  selections: GroupSelections,
  channelIds: readonly string[],
  group: string,
  member: boolean,
): GroupEdit {
  if (groupName(group) !== group) {
    return { channels: {}, settings: {} };
  } else {
    const channels: Record<string, ChannelFilter> = {};
    for (const channelId of channelIds) {
      const filter = saved[channelId] ?? defaultFilter();
      const groups = filterGroups(filter);
      if (groups.includes(group) !== member) {
        channels[channelId] = withGroups(
          filter,
          member ? [...groups, group] : groups.filter((name) => name !== group),
        );
      }
    }
    const after = { ...saved, ...channels };
    const left = listed.some(
      (channelId) =>
        after[channelId] !== undefined &&
        filterGroups(after[channelId]).includes(group),
    );
    if (member || left) {
      return { channels, settings: {} };
    } else {
      const deleted = deleteGroup(after, selections, group);
      return {
        channels: { ...channels, ...deleted.channels },
        settings: deleted.settings,
      };
    }
  }
}

/**
 * What the group editor's "Save" writes, as one edit: the listed channels
 * in the group become exactly `members`, then the group takes `name`
 * ({@link renameGroup}, which merges into a group that has it already).
 * `group` is the edited group, or null for a new one, whose members are
 * put in `name`. Only `listed` channels count as members. Nothing changes
 * unless `name` is a name and `members` has a listed channel.
 */
export function saveGroup(
  saved: Readonly<Record<string, ChannelFilter>>,
  listed: readonly string[],
  selections: GroupSelections,
  group: string | null,
  name: string,
  members: readonly string[],
): GroupEdit {
  const wanted = new Set(members);
  const inside = listed.filter((channelId) => wanted.has(channelId));
  if (groupName(name) !== name || inside.length === 0) {
    return { channels: {}, settings: {} };
  } else if (group === null) {
    return setMembers(saved, listed, selections, inside, name, true);
  } else {
    const added = setMembers(saved, listed, selections, inside, group, true);
    const withAdded = { ...saved, ...added.channels };
    const removed = setMembers(
      withAdded,
      listed,
      selections,
      listed.filter((channelId) => !wanted.has(channelId)),
      group,
      false,
    );
    const renamed = renameGroup(
      { ...withAdded, ...removed.channels },
      { ...selections, ...removed.settings },
      group,
      name,
    );
    return {
      channels: { ...added.channels, ...removed.channels, ...renamed.channels },
      settings: { ...removed.settings, ...renamed.settings },
    };
  }
}
