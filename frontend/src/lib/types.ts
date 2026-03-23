// Parsed on-chain data types (from SUI RPC results)

export interface StorageData {
  id: string;
  owner: string;
  systemId: number;
  maxCapacity: number;
  currentLoad: number;
  feeRateBps: number;
  guildId: string | null;
  isShared: boolean;
}

export interface CargoData {
  id: string;
  owner: string;
  itemType: string;
  weight: number;
  value: number;
  depositedAt: number;
}

export interface DepositReceiptData {
  id: string;
  storageId: string;
  cargoId: string;
  depositor: string;
}

export interface CourierContractData {
  id: string;
  client: string;
  fromStorage: string;
  toStorage: string;
  reward: number;
  clientDeposit: number;
  minCourierDeposit: number;
  deadline: number;
  status: number;
  courier: string | null;
  cargoValue: number;
  hasGuildBonus: boolean;
}

export interface GuildData {
  id: string;
  leader: string;
  name: string;
  memberCount: number;
  memberTableId: string;
  createdAt: number;
}

export interface FuelStationData {
  id: string;
  owner: string;
  storageId: string;
  basePrice: number;
  alpha: number;
  ownerFeeBps: number;
  currentFuel: number;
  maxFuel: number;
  totalSupplied: number;
}

export interface TransportOrderData {
  id: string;
  sender: string;
  fromStorage: string;
  toStorage: string;
  tier: number;
  fuelCost: number;
  status: number;
  earliestCompleteAt: number;
}
