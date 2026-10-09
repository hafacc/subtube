/** What the IFrame player reports about its current video (undocumented, long stable). */
export interface VideoData {
  /** the playing video's id */
  video_id?: string;
  /** its title */
  title?: string;
  /** its channel's name */
  author?: string;
}

/** The subset of the YouTube IFrame Player API subtube uses. */
export interface YouTubePlayer {
  /** Remove the player. */
  destroy(): void;
  /** The player's iframe. */
  getIframe(): HTMLIFrameElement;
  /** Pause the playing video. */
  pauseVideo(): void;
  /** Play the loaded video. */
  playVideo(): void;
  /** Load and play a list of video ids in order, starting at `index`, `startSeconds` into it. */
  loadPlaylist(playlist: string[], index?: number, startSeconds?: number): void;
  /** How far the playing video has played, in seconds. */
  getCurrentTime(): number;
  /** The playing video's length in seconds; 0 until it is known. */
  getDuration(): number;
  /** The playing video. */
  getVideoData(): VideoData;
  /** The ids the player loaded for a playlist. */
  getPlaylist(): string[] | null;
  /** The playing position within {@link getPlaylist}. */
  getPlaylistIndex(): number;
}

/** A player state change. */
export interface PlayerStateChangeEvent {
  /** the new state, one of `YT.PlayerState` */
  data: number;
  /** the player */
  target: YouTubePlayer;
}

/** The global `YT` namespace the IFrame API script defines. */
export interface YouTubeNamespace {
  /** Make a player in place of `element`. */
  Player: new (
    element: HTMLElement,
    options: {
      width?: string | number;
      height?: string | number;
      playerVars?: Record<string, string | number>;
      events?: {
        onReady?: (event: { target: YouTubePlayer }) => void;
        onStateChange?: (event: PlayerStateChangeEvent) => void;
        onError?: (event: { data: number; target: YouTubePlayer }) => void;
      };
    },
  ) => YouTubePlayer;
  /** Player states. */
  PlayerState: { PLAYING: number; PAUSED: number; ENDED: number };
}

declare global {
  interface Window {
    YT?: YouTubeNamespace;
    onYouTubeIframeAPIReady?: () => void;
  }
}

let apiPromise: Promise<YouTubeNamespace> | null = null;

/** Load the IFrame API script once; a failed load is retried on the next call. */
export function loadIframeApi(): Promise<YouTubeNamespace> {
  const loaded = window.YT;
  if (loaded?.Player) {
    return Promise.resolve(loaded);
  }
  apiPromise ??= new Promise<YouTubeNamespace>((resolve, reject) => {
    const priorCallback = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      priorCallback?.();
      if (window.YT) {
        resolve(window.YT);
      }
    };
    const script = document.createElement("script");
    script.src = "https://www.youtube.com/iframe_api";
    script.onerror = () => {
      apiPromise = null;
      script.remove();
      reject(new Error("Couldn't load the YouTube player."));
    };
    document.head.appendChild(script);
  });
  return apiPromise;
}
