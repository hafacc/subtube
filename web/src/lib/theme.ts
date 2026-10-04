/** The colour theme: follow the system, or force light or dark. */
export type Theme = "system" | "light" | "dark";

const STORAGE_KEY = "subtube.theme";
const NEXT: Record<Theme, Theme> = {
  system: "light",
  light: "dark",
  dark: "system",
};

/** The theme picked on this browser. */
export function readTheme(): Theme {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    return stored === "light" || stored === "dark" ? stored : "system";
  } catch {
    return "system";
  }
}

/** Apply and remember the theme after `theme`, returning it. */
export function cycleTheme(theme: Theme): Theme {
  const next = NEXT[theme];
  if (next === "system") {
    delete document.documentElement.dataset.theme;
  } else {
    document.documentElement.dataset.theme = next;
  }
  try {
    if (next === "system") {
      localStorage.removeItem(STORAGE_KEY);
    } else {
      localStorage.setItem(STORAGE_KEY, next);
    }
  } catch {
    // applies for this visit only
  }
  return next;
}
