import type { ReactNode } from 'react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { Panel } from './Panel';

export function WalletGuard({ children }: { children: ReactNode }) {
  const account = useCurrentAccount();
  if (!account) {
    return (
      <Panel className="text-center py-12">
        <p className="text-gray-400">Connect your wallet to continue.</p>
      </Panel>
    );
  }
  return <>{children}</>;
}
