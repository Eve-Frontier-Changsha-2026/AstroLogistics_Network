import { createDAppKit } from '@mysten/dapp-kit-react';
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { NETWORKS, DEFAULT_NETWORK, GRPC_URLS, type Network } from './config/network';

export const dAppKit = createDAppKit({
  networks: [...NETWORKS],
  defaultNetwork: DEFAULT_NETWORK,
  createClient: (network) =>
    new SuiGrpcClient({
      network: network as Network,
      baseUrl: GRPC_URLS[network as Network],
    }),
});

declare module '@mysten/dapp-kit-react' {
  interface Register {
    dAppKit: typeof dAppKit;
  }
}
