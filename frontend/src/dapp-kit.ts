import { createDAppKit } from '@mysten/dapp-kit-react';
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { NETWORKS, DEFAULT_NETWORK, GRPC_URLS, type Network } from './config/network';
import type { WalletInitializer } from '@mysten/dapp-kit-core';

// DEV-only: inject test wallet from localStorage for Playwright E2E.
// Uses dynamic import() so TestWallet.ts is excluded from the production bundle.
const walletInitializers: WalletInitializer[] = [];
if (import.meta.env.DEV && typeof localStorage !== 'undefined') {
  const testKey = localStorage.getItem('testKeypair');
  if (testKey) {
    // Lazy-loaded — Vite code-splits this chunk and eliminates it in prod
    import('./test/TestWallet').then(({ testWalletInitializer }) => {
      walletInitializers.push(testWalletInitializer(testKey));
    }).catch(() => { /* test wallet unavailable */ });
  }
}

export const dAppKit = createDAppKit({
  networks: [...NETWORKS],
  defaultNetwork: DEFAULT_NETWORK,
  createClient: (network) =>
    new SuiGrpcClient({
      network: network as Network,
      baseUrl: GRPC_URLS[network as Network],
    }),
  walletInitializers,
  autoConnect: true,
});

declare module '@mysten/dapp-kit-react' {
  interface Register {
    dAppKit: typeof dAppKit;
  }
}
