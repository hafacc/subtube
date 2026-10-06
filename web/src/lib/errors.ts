/** What the app says when Google can't be reached or answers with a failure. */
export const UNREACHABLE_MESSAGE =
  "Couldn't reach Google. Check your connection and try again.";

/** An error whose message is written for the user and shown as it is. */
export class ShownError extends Error {}

/** What to show for a failure: a {@link ShownError}'s own message, else {@link UNREACHABLE_MESSAGE}. */
export function shownMessage(caught: unknown): string {
  return caught instanceof ShownError ? caught.message : UNREACHABLE_MESSAGE;
}

/** Thrown when only an interactive sign-in can produce a token. */
export class SignInRequiredError extends ShownError {
  constructor() {
    super("Sign in again to continue.");
    this.name = "SignInRequiredError";
  }
}

/** Thrown when the user closed Google's sign-in page or refused there: nothing to report. */
export class SignInCancelledError extends Error {
  constructor() {
    super("sign-in cancelled");
    this.name = "SignInCancelledError";
  }
}

/** Thrown when the extension the web app needs isn't installed. */
export class ExtensionMissingError extends ShownError {
  constructor() {
    super("The SubTube extension isn't installed.");
    this.name = "ExtensionMissingError";
  }
}

/** Thrown when the installed extension gave no answer to a message. */
export class ExtensionSilentError extends ShownError {
  constructor() {
    super("The SubTube extension didn't answer.");
    this.name = "ExtensionSilentError";
  }
}
