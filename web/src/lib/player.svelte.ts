import { feedItemId } from "./feed-item";
import {
  afterRoute,
  endOutcome,
  nextInQueue,
  type Playing,
  routeItem,
} from "./player";
import type { Route, RouteItem } from "./router";
import type { FeedItem } from "./types";
import type { WatchedMode } from "./watched-mode";

/** What the player reads from the feed. */
export interface PlayerFeed {
  /** the items on screen, in the order shown */
  readonly feed: readonly FeedItem[];
  /** the ids of every watched item */
  readonly watched: ReadonlySet<string>;
  /** the watched chip's choice */
  readonly watchedMode: WatchedMode;
  /** the synced settings the player needs */
  readonly settings: { readonly autoplay: boolean };
  /** What auto-play plays after `endedId` on the page showing. */
  autoplayNext(endedId: string): FeedItem | null;
}

/** The part of the router the player moves. */
export interface PlayerRouter {
  /** where the app is */
  readonly route: Route;
  /** Go to a route, as a new history entry. */
  open(route: Route): void;
  /** Go to a route in place of the current history entry. */
  replace(route: Route): void;
  /** Drop the open item, going back when the app put it there. */
  close(): void;
}

/**
 * The one player: what it plays, where it is drawn, and what plays next.
 *
 * A card starts it large in a wide window and in the card in a narrow one;
 * {@link minimize} sends it to the corner, {@link expand} brings it back and
 * {@link close} ends it. The URL holds the item only while the player is
 * large ({@link routeChanged}), so Back from large minimizes, and Back while
 * minimized goes back a page with the player still there. The end of an
 * item plays the next unwatched one of the list it was started from
 * ({@link ended}).
 */
export class PlayerController {
  /** what is playing; null when there is no player */
  playing: Playing | null = $state.raw(null);
  private readonly feed: PlayerFeed;
  private readonly router: PlayerRouter;
  private readonly isNarrow: () => boolean;
  private readonly isFullScreen: () => boolean;

  /**
   * A player over `feed`, moving `router`; `isNarrow` says whether cards play
   * in place, and `isFullScreen` whether something fills the screen, which
   * widens the window without the user having resized it.
   */
  constructor(
    feed: PlayerFeed,
    router: PlayerRouter,
    isNarrow: () => boolean,
    isFullScreen: () => boolean = () => false,
  ) {
    this.feed = feed;
    this.router = router;
    this.isNarrow = isNarrow;
    this.isFullScreen = isFullScreen;
  }

  private onScreen(id: string): boolean {
    return this.feed.feed.some((item) => feedItemId(item) === id);
  }

  /** Whether the card with this id holds the player. */
  inCard(id: string): boolean {
    return this.playing?.place === "card" && this.playing.item.id === id;
  }

  /** Whether the item with this id is what the player plays, wherever it is drawn. */
  isPlaying(id: string): boolean {
    return this.playing?.item.id === id;
  }

  /** Play a card of the page showing, in place of whatever was playing. */
  play(item: FeedItem): void {
    const narrow = this.isNarrow();
    const page = this.router.route.channel;
    const opened = routeItem(item);
    this.playing = {
      item: opened,
      place: narrow ? "card" : "large",
      page,
      queue: { items: [...this.feed.feed], mode: this.feed.watchedMode },
    };
    if (!narrow) {
      this.router.open({ channel: page, item: opened });
    }
  }

  /** Send the player to the corner. */
  minimize(): void {
    const playing = this.playing;
    if (playing && playing.place !== "minimized") {
      this.playing = { ...playing, place: "minimized" };
      if (this.router.route.item) {
        this.router.close();
      }
    }
  }

  /**
   * Bring a minimized player back: large in a wide window; in a narrow one
   * into its card, on the page it was started from, or large when that page
   * no longer lists it.
   */
  expand(): void {
    const playing = this.playing;
    if (playing?.place === "minimized") {
      if (this.isNarrow()) {
        const moved = this.router.route.channel !== playing.page;
        if (moved) {
          this.router.open({ channel: playing.page, item: null });
        }
        if (this.onScreen(playing.item.id)) {
          this.playing = { ...playing, place: "card" };
        } else if (moved) {
          // in the entry just made, so one Back returns to where Expand was pressed
          this.playing = { ...playing, place: "large" };
          this.router.replace({ channel: playing.page, item: playing.item });
        } else {
          this.enlarge();
        }
      } else {
        this.enlarge();
      }
    }
  }

  /** Draw the player large, over the page showing, with its item in the URL. */
  enlarge(): void {
    const playing = this.playing;
    if (playing && playing.place !== "large") {
      this.playing = { ...playing, place: "large" };
      this.router.open({
        channel: this.router.route.channel,
        item: playing.item,
      });
    }
  }

  /** The card's box can no longer hold the player: it goes to the corner, unless what fills the screen is why. */
  cardLost(): void {
    if (this.playing?.place === "card" && !this.isFullScreen()) {
      this.minimize();
    }
  }

  /** Stop playing and remove the player. */
  close(): void {
    const wasLarge = this.playing?.place === "large";
    this.playing = null;
    if (wasLarge && this.router.route.item) {
      this.router.close();
    }
  }

  /** The item with this id is over: play what comes next, stay, or close. */
  ended(endedId: string): void {
    const playing = this.playing;
    if (playing && playing.item.id === endedId) {
      const next = playing.queue
        ? nextInQueue(
            playing.queue,
            endedId,
            this.feed.watched,
            this.feed.settings.autoplay,
          )
        : this.feed.autoplayNext(endedId);
      const outcome = endOutcome(
        playing.place,
        next,
        next !== null && this.onScreen(feedItemId(next)),
      );
      if (outcome.kind === "next") {
        const item = routeItem(outcome.item);
        this.playing = { ...playing, item, place: outcome.place };
        if (outcome.place === "large") {
          this.router.replace({ channel: this.router.route.channel, item });
        }
      } else if (outcome.kind === "close") {
        this.close();
      }
    }
  }

  /** The URL's item changed, by Back, Forward, a link, or the player itself. */
  routeChanged(item: RouteItem | null): void {
    this.playing = afterRoute(this.playing, item, this.router.route.channel);
  }

  /**
   * The page, its list or the window's width changed: a card that is gone, on
   * another page, or in a window too wide to play in cards gives the player
   * to the corner. A window that is wide only while something fills the
   * screen is not too wide.
   */
  pageChanged(): void {
    const playing = this.playing;
    if (
      playing?.place === "card" &&
      ((!this.isNarrow() && !this.isFullScreen()) ||
        this.router.route.channel !== playing.page ||
        !this.onScreen(playing.item.id))
    ) {
      this.playing = { ...playing, place: "minimized" };
    }
  }
}
