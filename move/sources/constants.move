module astrologistics::constants;

/// Fixed-point scale: 1000 = 1.0 (used for alpha, danger scores, tier multipliers)
public fun fp_scale(): u64 { 1000 }

/// Basis points scale: 10000 = 100%
public fun bps_scale(): u64 { 10000 }

/// Max owner fee: 5000 = 50%
public fun max_owner_fee_bps(): u64 { 5000 }

/// Grace period for admin_reclaim: 30 days in milliseconds
public fun reclaim_grace_ms(): u64 { 2_592_000_000 }

/// Transport tier multipliers (FP_SCALE): Instant=3.0, Express=1.5, Standard=1.0
public fun tier_multiplier_instant(): u64 { 3000 }
public fun tier_multiplier_express(): u64 { 1500 }
public fun tier_multiplier_standard(): u64 { 1000 }

/// Transport tier delays in ms: Instant=0, Express=5min, Standard=15min
public fun tier_delay_instant(): u64 { 0 }
public fun tier_delay_express(): u64 { 300_000 }
public fun tier_delay_standard(): u64 { 900_000 }

/// Min/Max fuel cost per weight unit
public fun min_fuel_cost_per_weight(): u64 { 10 }
public fun max_fuel_cost_per_weight(): u64 { 100_000 }

/// Reporter cooldown: 1 hour in ms
public fun reporter_cooldown_ms(): u64 { 3_600_000 }

/// Keeper bounty: 50 = 0.5% (in BPS)
public fun keeper_bounty_bps(): u64 { 50 }

/// Max batch update size for threat oracle
public fun max_batch_size(): u64 { 100 }

/// Max route length
public fun max_route_length(): u64 { 50 }

/// Scarce threshold: 30% (300 in FP_SCALE)
public fun scarce_threshold(): u64 { 300 }

/// Scarce bonus multiplier: 1.5x (1500 in FP_SCALE)
public fun scarce_bonus(): u64 { 1500 }

/// Max alpha for fuel station pricing: 10x (10000 in FP_SCALE)
public fun max_alpha(): u64 { 10_000 }

/// Min courier contract reward (anti-farming)
public fun min_contract_reward(): u64 { 1000 }

/// Guild member fee discount: 3000 = 30% off storage fees
public fun guild_fee_discount_bps(): u64 { 3000 }

/// Max members per guild
public fun max_guild_members(): u64 { 100 }

/// Max guild name length in bytes (Red Team Fix: input fuzzing)
public fun max_guild_name_length(): u64 { 128 }
