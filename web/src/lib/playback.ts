import type { RouteItem } from "./router";
import type { FeedItem } from "./types";
import type { VideoData, YouTubePlayer } from "./youtube-player";

/** What a playing item reads from and saves to the feed. */
export interface PlaybackFeed {
  /** Save how far a video has been played. */
  recordProgress(
    id: string,
    position: number,
    playerDuration: number,
    ended: boolean,
    upload: "later" | "soon" | "now",
  ): void;
  /** Mark a video or playlist watched. */
  setWatched(id: string, isWatched: boolean): void;
  /** Where a video starts when opened, in seconds. */
  resumeAt(id: string): number;
  /** A loaded item by id. */
  findItem(id: string): FeedItem | undefined;
}

/** The player states playback reacts to, as `YT.PlayerState` numbers them. */
export interface PlaybackStates {
  /** playing */
  PLAYING: number;
  /** paused */
  PAUSED: number;
  /** the video ended */
  ENDED: number;
}

/**
 * One item in one player, wherever the player is drawn: starts a video where
 * it was left, saves its position as it plays, and marks it watched at the
 * player's reported end.
 *
 * Nothing is saved for a playlist or a live broadcast; a playlist is marked
 * when its last video ends. `onended` runs once the item is over.
 */
export class Playback {
  /** what the player last reported about its video */
  videoData: VideoData | null = null;
  private readonly item: RouteItem;
  private readonly feed: PlaybackFeed;
  private readonly states: PlaybackStates;
  private readonly onended: () => void;
  private readonly ontoggle: () => void;
  private player: YouTubePlayer | null = null;
  private playing = false;
  // the last of playing and paused the player reported; buffering between them doesn't count
  private settled: "playing" | "paused" | null = null;
  private covered = false;
  // paused by `cover`, to play again once nothing covers the player
  private held = false;
  // the next pause or play the player reports is this class's doing
  private ownToggle = false;
  // from the first time the video plays until it ends: while set, its position is worth saving
  private tracking = false;

  /**
   * Playback of `item`, before its player exists. `ontoggle` runs when the
   * video is paused, or played again after a pause, by anyone but
   * {@link cover}.
   */
  constructor(
    item: RouteItem,
    feed: PlaybackFeed,
    states: PlaybackStates,
    onended: () => void,
    ontoggle: () => void = () => undefined,
  ) {
    this.item = item;
    this.feed = feed;
    this.states = states;
    this.onended = onended;
    this.ontoggle = ontoggle;
  }

  /**
   * Say whether something covers the player: a covered player is paused, and
   * one this paused plays again once nothing covers it.
   */
  cover(covered: boolean): void {
    this.covered = covered;
    if (covered && this.playing) {
      this.hold();
    } else if (!covered && this.held) {
      this.held = false;
      this.ownToggle = true;
      this.player?.playVideo();
    }
  }

  private hold(): void {
    this.held = true;
    this.ownToggle = true;
    this.player?.pauseVideo();
  }

  /** The options the player is made with. */
  get playerVars(): Record<string, string | number> {
    // a video is loaded in `ready`: combining videoId with the `playlist`
    // param drops the first id
    if (this.item.kind === "playlist") {
      return {
        autoplay: 1,
        rel: 0,
        fs: 1,
        listType: "playlist",
        list: this.item.id,
      };
    } else {
      return { rel: 0, fs: 1 };
    }
  }

  /** The player is ready: start a video where it was left. */
  ready(player: YouTubePlayer): void {
    this.player = player;
    if (this.item.kind === "video") {
      player.loadPlaylist([this.item.id], 0, this.feed.resumeAt(this.item.id));
    }
  }

  /** Whether the position is saved: not for a playlist or a live broadcast. */
  private savesPosition(): boolean {
    const entry = this.feed.findItem(this.item.id);
    const live = entry?.kind === "video" && entry.liveStatus === "live";
    return this.item.kind === "video" && !live;
  }

  /** Save the position of a video that has played; `upload` as in {@link PlaybackFeed.recordProgress}. */
  save(upload: "later" | "soon" | "now"): void {
    if (this.player && this.tracking && this.savesPosition()) {
      this.feed.recordProgress(
        this.item.id,
        this.player.getCurrentTime(),
        this.player.getDuration(),
        false,
        upload,
      );
    }
  }

  /** The regular save while playing, kept on this device only. */
  tick(): void {
    if (this.playing) {
      this.save("later");
    }
  }

  private finish(player: YouTubePlayer): void {
    this.tracking = false;
    if (this.savesPosition()) {
      this.feed.recordProgress(
        this.item.id,
        player.getCurrentTime(),
        player.getDuration(),
        true,
        "soon",
      );
    } else {
      this.feed.setWatched(this.item.id, true);
    }
    this.onended();
  }

  /** The player changed state. */
  stateChanged(state: number, player: YouTubePlayer): void {
    this.player = player;
    const wasPlaying = this.playing;
    this.playing = state === this.states.PLAYING;
    this.tracking ||= this.playing;
    if (this.playing || state === this.states.PAUSED) {
      const settled = this.playing ? "playing" : "paused";
      const toggled = this.settled !== null && this.settled !== settled;
      this.settled = settled;
      if (this.ownToggle) {
        this.ownToggle = false;
      } else if (toggled) {
        this.ontoggle();
      }
      if (this.playing && this.covered) {
        this.hold();
      } else if (this.playing) {
        this.held = false;
      }
    }
    this.videoData = player.getVideoData();
    if (this.item.kind === "playlist") {
      // the player's own list already skips unavailable videos
      const loaded = player.getPlaylist();
      if (
        state === this.states.ENDED &&
        loaded &&
        player.getPlaylistIndex() === loaded.length - 1
      ) {
        this.finish(player);
      }
    } else if (state === this.states.ENDED) {
      this.finish(player);
    } else if (state === this.states.PAUSED && wasPlaying) {
      this.save("soon");
    }
  }
}
