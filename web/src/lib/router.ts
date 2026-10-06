/** What the player is showing over the background: a single video or a playlist. */
export type RouteItem =
  | { kind: "video"; id: string }
  | { kind: "playlist"; id: string };

/**
 * The app is one static page, so where you are lives in the query string: an
 * optional `channel` background (a channel page; otherwise the feed) plus an
 * optional open `item` over it. Opening a video from a channel page keeps both,
 * so the channel stays behind the player.
 */
export interface Route {
  /** the channel page behind, or null for the feed */
  channel: string | null;
  /** what the player shows, or null when it is closed */
  item: RouteItem | null;
}

/** Read a route from a query string. */
export function parseRoute(search: string): Route {
  const params = new URLSearchParams(search);
  const channel = params.get("channel") || null;
  const video = params.get("v");
  const playlist = params.get("list");
  const item: RouteItem | null = video
    ? { kind: "video", id: video }
    : playlist
      ? { kind: "playlist", id: playlist }
      : null;
  return { channel, item };
}

/** The URL for a route, keeping `path` (the page's own path). */
export function routeToUrl(route: Route, path: string): string {
  const params = new URLSearchParams();
  if (route.channel) {
    params.set("channel", route.channel);
  }
  if (route.item?.kind === "video") {
    params.set("v", route.item.id);
  } else if (route.item?.kind === "playlist") {
    params.set("list", route.item.id);
  }
  const query = params.toString();
  return query ? `${path}?${query}` : path;
}
