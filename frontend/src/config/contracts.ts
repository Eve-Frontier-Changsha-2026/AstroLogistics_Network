// Original (v1) — struct types are defined here
export const ORIGINAL_PACKAGE_ID =
  '0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c';

// Latest (v3) — function calls target this
export const PACKAGE_ID =
  '0x3407e5c8c245040bb2325dc1f5160188ec5ce811378107f1d2e6e82466bf706a';

export const MODULE = {
  storage: `${PACKAGE_ID}::storage`,
  courier_market: `${PACKAGE_ID}::courier_market`,
  guild: `${PACKAGE_ID}::guild`,
  fuel_station: `${PACKAGE_ID}::fuel_station`,
  transport: `${PACKAGE_ID}::transport`,
  fuel: `${PACKAGE_ID}::fuel`,
  threat_oracle: `${PACKAGE_ID}::threat_oracle`,
  seal_policy: `${PACKAGE_ID}::seal_policy`,
} as const;

// Struct types use ORIGINAL_PACKAGE_ID (where they were first defined)
export const TYPE = {
  Storage: `${ORIGINAL_PACKAGE_ID}::storage::Storage`,
  AdminCap: `${ORIGINAL_PACKAGE_ID}::storage::AdminCap`,
  Cargo: `${ORIGINAL_PACKAGE_ID}::storage::Cargo`,
  DepositReceipt: `${ORIGINAL_PACKAGE_ID}::storage::DepositReceipt`,
  CourierContract: `${ORIGINAL_PACKAGE_ID}::courier_market::CourierContract`,
  CourierBadge: `${ORIGINAL_PACKAGE_ID}::courier_market::CourierBadge`,
  Guild: `${ORIGINAL_PACKAGE_ID}::guild::Guild`,
  GuildMemberCap: `${ORIGINAL_PACKAGE_ID}::guild::GuildMemberCap`,
  FuelStation: `${ORIGINAL_PACKAGE_ID}::fuel_station::FuelStation`,
  StationCap: `${ORIGINAL_PACKAGE_ID}::fuel_station::StationCap`,
  SupplierReceipt: `${ORIGINAL_PACKAGE_ID}::fuel_station::SupplierReceipt`,
  TransportOrder: `${ORIGINAL_PACKAGE_ID}::transport::TransportOrder`,
  ThreatMap: `${ORIGINAL_PACKAGE_ID}::threat_oracle::ThreatMap`,
  OracleCap: `${ORIGINAL_PACKAGE_ID}::threat_oracle::OracleCap`,
  ReporterCap: `${ORIGINAL_PACKAGE_ID}::threat_oracle::ReporterCap`,
  FuelTreasuryCap: `${ORIGINAL_PACKAGE_ID}::fuel::FuelTreasuryCap`,
  FUEL: `${ORIGINAL_PACKAGE_ID}::fuel::FUEL`,
} as const;

export const CLOCK = '0x6';
