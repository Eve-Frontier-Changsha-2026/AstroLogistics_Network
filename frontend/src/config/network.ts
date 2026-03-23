export const NETWORKS = ['testnet'] as const;
export type Network = (typeof NETWORKS)[number];

export const DEFAULT_NETWORK: Network = 'testnet';

export const GRPC_URLS: Record<Network, string> = {
  testnet: 'https://fullnode.testnet.sui.io:443',
};
