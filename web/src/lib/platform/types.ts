/** A Google access token for YouTube and the Drive app folder. */
export interface Token {
  accessToken: string;
  /** Seconds the token has left when it was issued. */
  expiresIn: number;
}

/** What the web app gets from the extension: Google tokens and the Shorts probe. */
export interface Platform {
  /** Interactive sign-in. */
  signIn(): Promise<Token>;
  /** A token without any UI, or null when only {@link signIn} can get one. */
  silentToken(): Promise<Token | null>;
  /** Revoke the grant and forget whatever this platform stored for it. */
  signOut(): Promise<void>;
  /** Whether a video is a Short; null when YouTube's answer was inconclusive. */
  probeShort?(videoId: string): Promise<boolean | null>;
}

/** The Google scopes subtube asks for. */
export const SCOPES = [
  "https://www.googleapis.com/auth/youtube.readonly",
  "https://www.googleapis.com/auth/drive.appdata",
];
