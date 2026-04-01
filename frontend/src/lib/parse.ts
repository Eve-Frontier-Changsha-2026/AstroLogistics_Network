/**
 * Safe string → bigint parser for SUI u64 values.
 * Prevents Number() precision loss for values > 2^53.
 */
export function parseU64(input: string): bigint {
  const trimmed = input.trim();
  if (!trimmed) return 0n;
  try {
    const val = BigInt(trimmed);
    return val < 0n ? 0n : val;
  } catch {
    return 0n;
  }
}
