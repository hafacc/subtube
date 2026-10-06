import { parseRoute, type Route, routeToUrl } from "./router";

/** What each history entry of the app carries. */
interface EntryState {
  /** how many entries the app made lie before this one */
  depth: number;
}

function depthOf(state: unknown): number {
  const depth = (state as Partial<EntryState> | null)?.depth;
  return typeof depth === "number" && Number.isInteger(depth) && depth > 0
    ? depth
    : 0;
}

/**
 * The URL as state: `open` pushes a history entry (so Back returns), `close`
 * drops the open item and keeps the channel background. A deep link with
 * nothing of ours behind it closes by stripping the item rather than leaving
 * the site.
 */
export class Router {
  /** where the app is */
  route: Route = $state(parseRoute(window.location.search));
  // kept in each entry's state, so it is right after Back, Forward and a reload
  private depth = depthOf(window.history.state);

  constructor() {
    window.addEventListener("popstate", (event) => {
      this.depth = depthOf(event.state);
      this.route = parseRoute(window.location.search);
    });
  }

  private url(route: Route): string {
    return routeToUrl(route, window.location.pathname);
  }

  private entry(): EntryState {
    return { depth: this.depth };
  }

  /** Go to a route, as a new history entry. */
  open(route: Route): void {
    this.depth += 1;
    window.history.pushState(this.entry(), "", this.url(route));
    this.route = parseRoute(window.location.search);
  }

  /** Go to a route in place of the current history entry, so Back still leaves the player. */
  replace(route: Route): void {
    window.history.replaceState(this.entry(), "", this.url(route));
    this.route = parseRoute(window.location.search);
  }

  /** Close the open item, going back when the app put it there. */
  close(): void {
    if (this.depth > 0) {
      window.history.back();
    } else {
      this.replace({ channel: this.route.channel, item: null });
    }
  }
}
