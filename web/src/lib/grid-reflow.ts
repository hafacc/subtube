import type { Attachment } from "svelte/attachments";
import { prefersReducedMotion } from "svelte/motion";

/** How long a card takes to move to its place in a new number of columns. */
const GLIDE_MS = 300;

/** The number of columns a grid lays its items out in. */
function columnCount(grid: HTMLElement): number {
  return getComputedStyle(grid).gridTemplateColumns.split(" ").length;
}

/** Where an item is drawn, from the grid's corner, with any glide under way. */
function placeOf(
  item: Element,
  gridBox: DOMRect,
): { left: number; top: number } {
  const box = item.getBoundingClientRect();
  return { left: box.left - gridBox.left, top: box.top - gridBox.top };
}

/** Whether a box is at least partly inside the window. */
function inView(box: DOMRect): boolean {
  return box.bottom > 0 && box.top < window.innerHeight;
}

/**
 * Move a grid's items to their new places when its number of columns changes,
 * rather than jumping there; under reduced motion they jump. Only the items in
 * the window move.
 */
export const glideOnReflow: Attachment<HTMLElement> = (grid) => {
  let columns = columnCount(grid);
  let places = new Map<Element, { left: number; top: number }>();
  const measure = () => {
    const gridBox = grid.getBoundingClientRect();
    places = new Map(
      Array.from(grid.children, (item) => [item, placeOf(item, gridBox)]),
    );
  };
  measure();
  const resizes = new ResizeObserver(() => {
    const now = columnCount(grid);
    if (now !== columns && !prefersReducedMotion.current) {
      const gridBox = grid.getBoundingClientRect();
      for (const item of grid.children) {
        const before = places.get(item);
        const box = item.getBoundingClientRect();
        if (before && inView(box)) {
          // from where it is drawn now, which a glide under way still moves
          for (const glide of item.getAnimations()) {
            glide.cancel();
          }
          const after = placeOf(item, gridBox);
          const dx = before.left - after.left;
          const dy = before.top - after.top;
          if (dx !== 0 || dy !== 0) {
            item.animate(
              [
                { transform: `translate(${dx}px, ${dy}px)` },
                { transform: "none" },
              ],
              { duration: GLIDE_MS, easing: "ease-out" },
            );
          }
        }
      }
    }
    columns = now;
    measure();
  });
  // cards come and go without the grid's size changing
  const changes = new MutationObserver(measure);
  resizes.observe(grid);
  changes.observe(grid, { childList: true });
  return () => {
    resizes.disconnect();
    changes.disconnect();
  };
};
