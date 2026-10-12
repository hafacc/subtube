import {
  type PlaylistPlace,
  type PlaylistStart,
  playlistProgress,
} from "./progress";
import type { RouteItem } from "./router";
import type { FeedItem } from "./types";
import type { VideoData, YouTubePlayer } from "./youtube-player";

/** What a playing item reads from and saves to the feed. */
export interface PlaybackFeed {
  /** Save how far a video has been played, or a playlist's video, with its `place` in the playlist. */
  recordProgress(
    id: string,
    position: number,
    playerDuration: number,
    ended: boolean,
    upload: "later" | "soon" | "now",
    place?: PlaylistPlace,
  ): void;
  /** Mark a video or playlist watched. */
  setWatched(id: string, isWatched: boolean): void;
  /** Where a video starts when opened, in seconds. */
  resumeAt(id: string): number;
  /** Where a playlist starts when opened, among the `videos` its player loaded. */
  playlistStart(id: string, videos: readonly string[]): PlaylistStart;
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
 * One item in one player, wherever the player is drawn: starts a video, or a
 * playlist's video, where it was left, saves its position as it plays, and
 * marks it watched at the player's reported end.
 *
 * Nothing is saved for a live broadcast; a playlist is marked when its last
 * video ends. `onended` runs once the item is over, which a
 * video the player refuses to play is at once ({@link failed}).
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
    // param drops the first id. A playlist is only cued here, so `ready` can
    // read its videos and start at the one that was playing.
    if (this.item.kind === "playlist") {
      return {
        rel: 0,
        fs: 1,
        listType: "playlist",
        list: this.item.id,
      };
    } else {
      return { rel: 0, fs: 1 };
    }
  }

  /** The player is ready: start a video, or a playlist's video, where it was left. */
  ready(player: YouTubePlayer): void {
    this.player = player;
    if (this.item.kind === "video") {
      player.loadPlaylist([this.item.id], 0, this.feed.resumeAt(this.item.id));
    } else {
      const { index, position } = this.feed.playlistStart(
        this.item.id,
        player.getPlaylist() ?? [],
      );
      player.loadPlaylist({
        list: this.item.id,
        listType: "playlist",
        index,
        startSeconds: position,
      });
    }
  }

  /** Whether the position is saved: not for a live broadcast. */
  private savesPosition(): boolean {
    const entry = this.feed.findItem(this.item.id);
    return !(entry?.kind === "video" && entry.liveStatus === "live");
  }

  /** Save the position of a video that has played; `upload` as in {@link PlaybackFeed.recordProgress}. */
  save(upload: "later" | "soon" | "now"): void {
    if (this.player && this.tracking && this.savesPosition()) {
      if (this.item.kind === "video") {
        this.feed.recordProgress(
          this.item.id,
          this.player.getCurrentTime(),
          this.player.getDuration(),
          false,
          upload,
        );
      } else {
        const video = this.player.getVideoData().video_id;
        if (video) {
          const position = this.player.getCurrentTime();
          const progress = playlistProgress(
            this.player.getPlaylistIndex(),
            this.player.getPlaylist()?.length ?? 0,
            position,
            this.player.getDuration(),
          );
          // a playlist has no length, so its video's is not passed as one
          this.feed.recordProgress(this.item.id, position, 0, false, upload, {
            video,
            progress,
          });
        }
      }
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
    if (this.item.kind === "video" && this.savesPosition()) {
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

  /**
   * The player reported an error: a video that can't play is over, unmarked
   * and with its saved position as it was. A playlist's player skips such a
   * video itself.
   */
  failed(): void {
    if (this.item.kind === "video") {
      this.tracking = false;
      this.onended();
    }
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
    // the player's own list already skips unavailable videos
    const loaded = player.getPlaylist();
    const isLast =
      this.item.kind === "video" ||
      (loaded !== null && player.getPlaylistIndex() === loaded.length - 1);
    if (state === this.states.ENDED && isLast) {
      this.finish(player);
    } else if (state === this.states.PAUSED && wasPlaying) {
      this.save("soon");
    }
  }
}
