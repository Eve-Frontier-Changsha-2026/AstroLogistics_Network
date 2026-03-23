// Shared objects deployed on testnet (from init-testnet.ts)
export const TESTNET_OBJECTS = {
  storage1: '0x1fcf2620712dad4745c8c2e4be10e5e3ffc6688b8a6c5dd8f5581d6223e7614c',
  storage2: '0x2a97c1b681a0420e8023e18b24230e23fb18cbfbc1962f06ab9edc24f59d7bcb',
  threatMap: '0xed6223a66967c994c781139af5bfe779a75309bbe6aea365ea00f58d68504f71',
  fuelStation1: '0x6d9f65c5a91e9d3f5b3f44d1bb0d6cff9fa9d96233973691e0f7f98479652238',
  fuelStation2: '0xecacfc19504df97bbbe164e499902d4fd7e015332fe54bc02aa0974c0f7eb3d6',
  guild: '0x6b1dafcaf0b2fce591440a0e43f3dd0a4b7d06ae6ceea4138c00154f742e75c4',
} as const;

// Admin caps (deployer-owned, not used in regular UI)
export const ADMIN_CAPS = {
  adminCap1: '0x60b9678a56c9cfa20e249434f958fbee8a9a1307acf8bca01ea51654ad63c1c3',
  adminCap2: '0x910553b99d112e29e2d73f4c0337d1a4085afc4997570a68b78d28189edcce13',
  oracleCap: '0xf3fd216ef4a86d818ba2aec607735f1ee079ffe40810d1f4c8de874b85cccd35',
  fuelTreasuryCap: '0x077592721b6425e85c5c2cfbb8bef7a479719e07b83878a30aa6c07c1428bfbc',
} as const;
