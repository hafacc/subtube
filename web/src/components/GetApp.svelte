<script lang="ts">
  import {
    appStoreUrl,
    macAppStoreUrl,
    playStoreUrl,
    privacyUrl,
  } from "../lib/config";
  import Logo from "./Logo.svelte";

  let {
    platform,
  }: {
    /** which app to offer */
    platform: "ios" | "ipados" | "android" | "mac";
  } = $props();

  interface Offer {
    heading: string;
    body: string;
    badgeSmall: string;
    badgeLarge: string;
    url: string | null;
    footer: string;
  }

  const PHONE_BODY =
    "On a phone, SubTube is an app. Your channels, filters and what you've watched come with you when you sign in.";
  const PHONE_FOOTER = "On a computer, open SubTube in Chrome.";

  const OFFERS: Record<typeof platform, Offer> = {
    ios: {
      heading: "Get SubTube for iPhone",
      body: PHONE_BODY,
      badgeSmall: "Download on the",
      badgeLarge: "App Store",
      url: appStoreUrl,
      footer: PHONE_FOOTER,
    },
    ipados: {
      heading: "Get SubTube for iPad",
      body: "On an iPad, SubTube is an app. Your channels, filters and what you've watched come with you when you sign in.",
      badgeSmall: "Download on the",
      badgeLarge: "App Store",
      url: appStoreUrl,
      footer: PHONE_FOOTER,
    },
    android: {
      heading: "Get SubTube for Android",
      body: PHONE_BODY,
      badgeSmall: "Get it on",
      badgeLarge: "Google Play",
      url: playStoreUrl,
      footer: PHONE_FOOTER,
    },
    mac: {
      heading: "Get SubTube for Mac",
      body: "In Safari, SubTube is a Mac app. Your channels, filters and what you've watched come with you when you sign in.",
      badgeSmall: "Download on the",
      badgeLarge: "Mac App Store",
      url: macAppStoreUrl,
      footer: "Or open SubTube in Chrome, with its extension.",
    },
  };

  const offer = $derived(OFFERS[platform]);
</script>

<div class="page">
  <div class="body">
    <div class="wordmark"><Logo size={40} /> SubTube</div>
    <h1>{offer.heading}</h1>
    <p class="lead">{offer.body}</p>
    {#if offer.url}
      <a class="badge" href={offer.url}>
        <span class="small">{offer.badgeSmall}</span>
        <span class="large">{offer.badgeLarge}</span>
      </a>
    {:else}
      <span class="badge" aria-disabled="true">
        <span class="small">{offer.badgeSmall}</span>
        <span class="large">{offer.badgeLarge}</span>
      </span>
    {/if}
  </div>
  <p class="footer">
    {offer.footer}
    <a href={privacyUrl} target="_blank" rel="noopener noreferrer"
      >Privacy policy</a
    >
  </p>
</div>

<style>
  .page {
    min-height: 100vh;
    max-width: 480px;
    margin: 0 auto;
    display: flex;
    flex-direction: column;
    padding: 88px 24px 40px;
  }

  .body {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 24px;
  }

  .wordmark {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 30px;
    font-weight: 700;
  }

  h1 {
    margin: 0;
    font-size: 28px;
    line-height: 34px;
    font-weight: 700;
  }

  .lead {
    margin: 0;
    font-size: 17px;
    line-height: 25px;
    color: var(--text-secondary);
  }

  .badge {
    align-self: flex-start;
    display: flex;
    flex-direction: column;
    justify-content: center;
    min-height: 56px;
    padding: 0 22px;
    border-radius: 12px;
    background: #000000;
    color: #ffffff;
    text-decoration: none;
  }

  .badge:hover {
    color: #ffffff;
  }

  .badge[aria-disabled="true"] {
    opacity: 0.5;
  }

  .small {
    font-size: 12px;
    line-height: 14px;
  }

  .large {
    font-size: 20px;
    line-height: 24px;
    font-weight: 600;
  }

  .footer {
    margin: 0;
    padding-top: 16px;
    border-top: 1px solid var(--border);
    font-size: 14px;
    line-height: 20px;
    color: var(--text-secondary);
  }
</style>
