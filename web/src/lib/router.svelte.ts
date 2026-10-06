import { parseRoute, type Route, routeToUrl } from "./router";

/**
 * The URL as state: `open` pushes a history entry (so Back returns), `close`
 * drops the open item and keeps the channel background. A deep link with
 * nothing of ours behind it closes by stripping the item rather than leaving
 * the site.
 */
export class Router {
  /** where the app is */
  route: Route = $state(parseRoute(window.location.search));
  private pushed = 0;

  constructor() {
    window.addEventListener("popstate", () => {
      this.pushed = Math.max(0, this.pushed - 1);
      this.route = parseRoute(window.location.search);
    });
  }

  /** Go to a route, as a new history entry. */
  open(route: Route): void {
    window.history.pushState(
      null,
      "",
      routeToUrl(route, window.location.pathname),
    );
    this.pushed += 1;
    this.route = parseRoute(window.location.search);
  }

  /** Go to a route in place of the current history entry, so Back still leaves the player. */
  replace(route: Route): void {
    window.history.replaceState(
      null,
      "",
      routeToUrl(route, window.location.pathname),
    );
    this.route = parseRoute(window.location.search);
  }

  /** Close the open item, going back when the app put it there. */
  close(): void {
    if (this.pushed > 0) {
      window.history.back();
    } else {
      window.history.replaceState(
        null,
        "",
        routeToUrl(
          { channel: this.route.channel, item: null },
          window.location.pathname,
        ),
      );
      this.route = parseRoute(window.location.search);
    }
  }
}
