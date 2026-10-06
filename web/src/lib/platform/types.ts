/** A Google access token for YouTube and the Drive app folder. */
export interface Token {
  accessToken: string;
  /** Seconds the token has left. */
  expiresIn: number;
}

/** What a token asked for without UI is for. */
export interface SilentTokenOptions {
  /** the Google account's address, so Google doesn't answer for another account */
  loginHint?: string;
  /** set when Google refused the last token, so a kept copy of it isn't handed back */
  fresh?: boolean;
}

/** What the web app gets from the extension: Google tokens and the Shorts probe. */
export interface Platform {
  /** Interactive sign-in; rejects with `SignInCancelledError` when the user calls it off. */
  signIn(): Promise<Token>;
  /** A token without any UI, or null when only {@link signIn} can get one. */
  silentToken(options?: SilentTokenOptions): Promise<Token | null>;
  /** Forget whatever this platform stored for the grant; the grant itself stays. */
  signOut(): Promise<void>;
  /** Forget as {@link signOut} does and withdraw the grant at Google. */
  revoke(): Promise<void>;
  /** Whether a video is a Short; null when YouTube's answer was inconclusive. */
  probeShort?(videoId: string): Promise<boolean | null>;
}
