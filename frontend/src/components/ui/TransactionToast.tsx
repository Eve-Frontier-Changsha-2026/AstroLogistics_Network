import { useEffect, useState } from 'react';

interface ToastProps {
  digest: string | null;
  error: string | null;
  onClose: () => void;
}

export function TransactionToast({ digest, error, onClose }: ToastProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (digest || error) {
      setVisible(true);
      const timer = setTimeout(() => { setVisible(false); onClose(); }, 5000);
      return () => clearTimeout(timer);
    }
  }, [digest, error, onClose]);

  if (!visible) return null;

  return (
    <div className={`fixed bottom-4 right-4 z-50 px-4 py-3 rounded-lg border text-sm max-w-sm ${
      error ? 'bg-red-900/80 border-red-700 text-red-200' : 'bg-green-900/80 border-green-700 text-green-200'
    }`}>
      {error ? (
        <p>Transaction failed: {error}</p>
      ) : (
        <p>
          Success!{' '}
          <a
            href={`https://suiscan.xyz/testnet/tx/${digest}`}
            target="_blank"
            rel="noopener noreferrer"
            className="underline"
          >
            View on explorer
          </a>
        </p>
      )}
    </div>
  );
}
