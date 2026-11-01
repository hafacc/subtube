import type { InfoPageName } from "./pages";

/** The info page shown over the app, if any. */
export const infoPage: { open: InfoPageName | null } = $state({ open: null });
