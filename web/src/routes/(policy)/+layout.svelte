<script lang="ts">
  import "../../policy.css";
  import { asset, resolve } from "$app/paths";

  let { children } = $props();
</script>

<header class="policy-header">
  <a class="brand" href={resolve("/")}>
    <img src={asset("logo.svg")} alt="">
    SubTube
  </a>
</header>
<main class="policy">{@render children()}</main>
