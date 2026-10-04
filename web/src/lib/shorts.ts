import type { FeedItem, Video } from "./types";

/**
 * Shorts are capped at 3 minutes, so a longer video can't be one and needs no
 * verdict.
 */
export const SHORTS_MAX_SECONDS = 180;

const PROBE_CONCURRENCY = 6;

/** Whether a video could be a Short at all, and so is worth classifying. */
export function isShortsCandidate(item: FeedItem): boolean {
  return (
    item.kind === "video" &&
    !!item.durationSeconds &&
    item.durationSeconds <= SHORTS_MAX_SECONDS
  );
}

/**
 * Set `isShort` on one channel's uploads. The verdict comes from the channel's
 * Shorts list (`loadShortIds`, null when the channel has none). Should that list
 * ever stop being served, every channel would look Short-free, so a platform
 * that can ask `/shorts/{id}` directly (`probe`) does so instead; an
 * inconclusive answer leaves the verdict unknown, which a channel filtering on
 * Shorts holds back.
 */
export async function classifyShorts(
  videos: Video[],
  loadShortIds: () => Promise<Set<string> | null>,
  probe?: (videoId: string) => Promise<boolean | null>,
): Promise<Video[]> {
  const candidates = videos.filter(isShortsCandidate);
  if (candidates.length === 0) {
    return videos.map((video) => ({ ...video, isShort: false }));
  }
  const shortIds = await loadShortIds();
  if (shortIds || !probe) {
    return videos.map((video) => ({
      ...video,
      isShort: isShortsCandidate(video) && !!shortIds?.has(video.videoId),
    }));
  }
  const verdicts = new Map<string, boolean | null>();
  for (let start = 0; start < candidates.length; start += PROBE_CONCURRENCY) {
    const batch = candidates.slice(start, start + PROBE_CONCURRENCY);
    const answers = await Promise.all(
      batch.map((video) => probe(video.videoId).catch(() => null)),
    );
    batch.forEach((video, index) => {
      verdicts.set(video.videoId, answers[index]);
    });
  }
  return videos.map((video) => {
    if (!isShortsCandidate(video)) {
      return { ...video, isShort: false };
    } else {
      return { ...video, isShort: verdicts.get(video.videoId) ?? undefined };
    }
  });
}
