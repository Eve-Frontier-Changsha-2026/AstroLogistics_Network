// On-chain statuses — contracts are destroyed on settle/cancel/timeout
export const CONTRACT_STATUS: Record<number, string> = {
  0: 'Open',
  1: 'Accepted',
  2: 'PendingConfirm',
  3: 'Delivered',
  4: 'Disputed',
};

export const TRANSPORT_STATUS: Record<number, string> = {
  0: 'Created',
  1: 'Paid',
  2: 'Completed',
  3: 'Cancelled',
};

export const TRANSPORT_TIER: Record<number, string> = {
  0: 'Instant',
  1: 'Express',
  2: 'Standard',
};
