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
 * One channel's uploads when its Shorts list isn't read, because nothing
 * filters on Shorts: a video that can't be a Short is marked not one, and a
 * candidate is left unjudged.
 */
export function withoutShortsList(videos: Video[]): Video[] {
  return videos.map((video) =>
    isShortsCandidate(video)
      ? { ...video, isShort: undefined }
      : { ...video, isShort: false },
  );
}

/** A channel's Shorts list as read: its ids, null when the channel has none, "failed" when it couldn't be read. */
export type ShortsList = ReadonlySet<string> | null | "failed";

/**
 * Set `isShort` on one channel's uploads (shared/fixtures/shorts.json). The
 * verdict comes from the channel's Shorts list (`loadShortIds`); a channel
 * with no list has no Shorts. Only when the list couldn't be read does a
 * platform that can ask `/shorts/{id}` directly (`probe`) do so instead; an
 * inconclusive answer leaves the verdict unknown, which a channel filtering
 * on Shorts holds back.
 */
export async function classifyShorts(
  videos: Video[],
  loadShortIds: () => Promise<ShortsList>,
  probe?: (videoId: string) => Promise<boolean | null>,
): Promise<Video[]> {
  const candidates = videos.filter(isShortsCandidate);
  if (candidates.length === 0) {
    return videos.map((video) => ({ ...video, isShort: false }));
  } else {
    const shortIds = await loadShortIds();
    if (shortIds !== "failed" || !probe) {
      const listed = shortIds === "failed" ? null : shortIds;
      return videos.map((video) => ({
        ...video,
        isShort: isShortsCandidate(video) && !!listed?.has(video.videoId),
      }));
    } else {
      const verdicts = new Map<string, boolean | null>();
      for (
        let start = 0;
        start < candidates.length;
        start += PROBE_CONCURRENCY
      ) {
        const batch = candidates.slice(start, start + PROBE_CONCURRENCY);
        const answers = await Promise.all(
          batch.map((video) => probe(video.videoId).catch(() => null)),
        );
        batch.forEach((video, index) => {
          verdicts.set(video.videoId, answers[index]);
        });
      }
      return videos.map((video) => ({
        ...video,
        isShort: isShortsCandidate(video)
          ? (verdicts.get(video.videoId) ?? undefined)
          : false,
      }));
    }
  }
}
