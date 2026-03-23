import { useState } from 'react';

export function AddressDisplay({ address }: { address: string }) {
  const [copied, setCopied] = useState(false);
  const short = `${address.slice(0, 6)}...${address.slice(-4)}`;

  const copy = () => {
    navigator.clipboard.writeText(address);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  };

  return (
    <button onClick={copy} className="text-cyan-400 hover:text-cyan-300 text-sm font-mono" title={address}>
      {copied ? 'Copied!' : short}
    </button>
  );
}
