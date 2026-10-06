/** `value` when it is one of `allowed`, else `fallback`: how a saved field of unknown content is read. */
export function oneOf<Value extends string>(
  value: unknown,
  allowed: readonly Value[],
  fallback: Value,
): Value {
  return allowed.find((option) => option === value) ?? fallback;
}
