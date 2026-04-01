export function formatAddress(addr: string, chars = 6): string {
  if (addr.length <= chars * 2 + 1) return addr;
  return `${addr.slice(0, chars)}...${addr.slice(-4)}`;
}

export function formatMist(mist: number | bigint): string {
  const sui = Number(mist) / 1_000_000_000;
  return sui.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

export function formatFuel(raw: number | bigint): string {
  const fuel = Number(raw) / 1_000_000_000; // 9 decimals
  return fuel.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 4 });
}

export function formatTimestamp(ms: number): string {
  return new Date(ms).toLocaleString();
}

export function formatBps(bps: number): string {
  return `${(bps / 100).toFixed(1)}%`;
}

export function timeRemaining(deadlineMs: number): string {
  const diff = deadlineMs - Date.now();
  if (diff <= 0) return 'Expired';
  const hours = Math.floor(diff / 3_600_000);
  const mins = Math.floor((diff % 3_600_000) / 60_000);
  if (hours > 24) return `${Math.floor(hours / 24)}d ${hours % 24}h`;
  return `${hours}h ${mins}m`;
}

export function formatDistance(ly: number): string {
  return `${ly.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} LY`;
}
