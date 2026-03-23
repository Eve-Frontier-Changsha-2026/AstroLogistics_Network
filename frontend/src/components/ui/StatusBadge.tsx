const BADGE_COLORS: Record<string, string> = {
  Open: 'bg-blue-900/60 text-blue-300 border-blue-700',
  Accepted: 'bg-yellow-900/60 text-yellow-300 border-yellow-700',
  PendingConfirm: 'bg-purple-900/60 text-purple-300 border-purple-700',
  Delivered: 'bg-green-900/60 text-green-300 border-green-700',
  Disputed: 'bg-red-900/60 text-red-300 border-red-700',
  Created: 'bg-blue-900/60 text-blue-300 border-blue-700',
  Paid: 'bg-yellow-900/60 text-yellow-300 border-yellow-700',
  Completed: 'bg-green-900/60 text-green-300 border-green-700',
  Cancelled: 'bg-gray-800 text-gray-400 border-gray-600',
};

export function StatusBadge({ status }: { status: string }) {
  const colors = BADGE_COLORS[status] ?? 'bg-gray-800 text-gray-400 border-gray-600';
  return (
    <span className={`inline-block px-2 py-0.5 text-xs rounded-full border ${colors}`}>
      {status}
    </span>
  );
}
