<script lang="ts">
  let {
    size = 20,
  }: {
    /** width and height in pixels */
    size?: number;
  } = $props();
</script>

<img
  src={`${import.meta.env.BASE_URL}logo.svg`}
  width={size}
  height={size}
  alt=""
>
