<script lang="ts">
  import { privacyUrl } from "../lib/config";
  import Icon from "./Icon.svelte";
  import Logo from "./Logo.svelte";
</script>

<div class="page">
  <header class="brand"><Logo /> SubTube</header>
  <main>
    <section aria-labelledby="gate-title">
      <span class="badge-icon"
        ><Icon name="puzzle" size={30} strokeWidth={1.75} /></span
      >
      <h1 id="gate-title">SubTube needs Chrome</h1>
      <p class="lead">
        SubTube works through a Chrome extension that keeps you signed in to
        Google and checks which videos are Shorts. Open this page in Chrome to
        use it.
      </p>
      <ul>
        <li>
          <Icon name="check" size={20} color="var(--gold)" />
          It only works with SubTube and YouTube.
        </li>
        <li>
          <Icon name="check" size={20} color="var(--gold)" />
          It has no buttons or pages of its own.
        </li>
      </ul>
      <div class="actions">
        <a class="button-primary add" href="https://www.google.com/chrome/"
          >Get Chrome</a
        >
      </div>
      <p class="footer">
        SubTube runs in Chrome on a computer. On a phone, use the SubTube app.
        <a href={privacyUrl} target="_blank" rel="noopener noreferrer"
          >Privacy policy</a
        >
      </p>
    </section>
  </main>
</div>

<style>
  .page {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    background: var(--surface);
  }

  header {
    padding: 12px 16px;
  }

  main {
    flex: 1;
    display: grid;
    place-items: center;
    padding: 32px 16px 64px;
  }

  section {
    width: 100%;
    max-width: 520px;
    padding: 40px;
    border: 1px solid var(--border);
    border-radius: 16px;
    background: var(--page);
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  @media (max-width: 480px) {
    section {
      padding: 24px;
    }
  }

  .badge-icon {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border-radius: 14px;
    background: var(--tint);
    color: var(--gold);
  }

  h1 {
    margin: 0;
    font-size: 26px;
    line-height: 32px;
    font-weight: 700;
  }

  .lead {
    margin: 0;
    font-size: 16px;
    line-height: 24px;
    color: var(--text-secondary);
  }

  ul {
    margin: 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  li {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    font-size: 15px;
    line-height: 21px;
  }

  .actions {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 12px;
    padding-top: 4px;
  }

  .add {
    min-height: 44px;
    padding: 0 22px;
    border-radius: 22px;
  }

  .footer {
    margin: 0;
    padding-top: 16px;
    border-top: 1px solid var(--border);
    font-size: 13px;
    line-height: 19px;
    color: var(--text-secondary);
  }
</style>
