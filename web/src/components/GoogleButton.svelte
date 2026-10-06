<script lang="ts">
  let {
    disabled = false,
    onclick,
  }: {
    /** whether a sign-in is already running */
    disabled?: boolean;
    /** start the sign-in */
    onclick: () => void;
  } = $props();
</script>

<!--
  Google's standard sign-in button: its four-colour mark, untouched, on the
  neutral fill, stroke and text colours its branding guidelines give for a
  light and a dark page (`--google-*` in app.css).
-->
<button type="button" class="google" {disabled} {onclick}>
  <svg viewBox="0 0 18 18" width="18" height="18" aria-hidden="true">
    <path
      fill="#4285F4"
      d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844c-.209 1.125-.843 2.078-1.796 2.717v2.258h2.908c1.702-1.567 2.684-3.874 2.684-6.615z"
    />
    <path
      fill="#34A853"
      d="M9 18c2.43 0 4.467-.806 5.956-2.18l-2.908-2.259c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"
    />
    <path
      fill="#FBBC05"
      d="M3.964 10.71A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.71V4.958H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.042l3.007-2.332z"
    />
    <path
      fill="#EA4335"
      d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.958L3.964 7.29C4.672 5.163 6.656 3.58 9 3.58z"
    />
  </svg>
  Sign in with Google
</button>

<style>
  .google {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    min-height: 48px;
    padding: 0 24px 0 12px;
    border: 1px solid var(--google-stroke);
    border-radius: 24px;
    background: var(--google-fill);
    color: var(--google-text);
    font-family: var(--font);
    font-size: 16px;
    font-weight: 500;
  }

  .google:hover:not(:disabled) {
    box-shadow: 0 1px 3px var(--shadow);
  }

  .google:disabled {
    opacity: 0.6;
  }
</style>
