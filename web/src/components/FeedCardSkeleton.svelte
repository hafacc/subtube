<script lang="ts">
</script>

<!-- The shape of a FeedCard while its place is still loading; the shimmer comes from the container. -->
<div class="skeleton-card" aria-hidden="true">
  <div class="skeleton-block thumb"></div>
  <div class="text">
    <div class="skeleton-block line"></div>
    <div class="skeleton-block line short"></div>
    <div class="byline">
      <div class="skeleton-block line channel"></div>
      <div class="skeleton-block line date"></div>
    </div>
  </div>
</div>

<style>
  .skeleton-card {
    display: flex;
    flex-direction: column;
    overflow: hidden;
    border-radius: 8px;
    background: var(--surface);
  }

  .thumb {
    aspect-ratio: 16 / 9;
    border-radius: 0;
  }

  .text {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 14px 12px 20px;
  }

  .line {
    height: 12px;
  }

  .short {
    width: 60%;
  }

  .byline {
    display: flex;
    justify-content: space-between;
  }

  .channel {
    width: 40%;
    height: 10px;
  }

  .date {
    width: 15%;
    height: 10px;
  }
</style>
