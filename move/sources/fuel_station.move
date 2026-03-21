module astrologistics::fuel_station;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::event;
use astrologistics::storage::Storage;
use astrologistics::fuel::FUEL;
use astrologistics::constants;

// ============ Error codes ============
const E_FEE_TOO_HIGH: u64 = 0;
const E_CAP_MISMATCH: u64 = 1;
const E_INSUFFICIENT_FUEL: u64 = 2;
const E_PRICE_EXCEEDS_MAX: u64 = 3;
const E_RECEIPT_MISMATCH: u64 = 4;
#[allow(unused_const)]
const E_NO_FUEL_SUPPLIED: u64 = 5;
const E_INSUFFICIENT_PAYMENT: u64 = 6;
const E_ALPHA_TOO_HIGH: u64 = 7;

// ============ Structs ============

public struct FuelStation has key {
    id: UID,
    storage_id: ID,
    owner: address,
    max_fuel: u64,
    current_fuel: u64,
    base_price: u64,
    alpha: u64,                       // FP_SCALE
    owner_fee_bps: u64,
    total_supplied: u64,              // effective supply (includes scarce bonus)
    acc_reward_per_share: u64,        // O(1) accumulator (FP_SCALE)
    revenue_pool: Balance<SUI>,       // collected SUI from fuel sales
    fuel_reserve: Balance<FUEL>,      // Fix C2: actual FUEL balance
}

public struct StationCap has key, store {
    id: UID,
    station_id: ID,
}

public struct SupplyRecord has store, drop, copy {
    amount: u64,
    reward_debt: u64,
}

public struct SupplierReceipt has key, store {
    id: UID,
    station_id: ID,
    supply_record: SupplyRecord,
}

// ============ Events ============

public struct StationCreated has copy, drop {
    station_id: ID,
    storage_id: ID,
    owner: address,
    base_price: u64,
}

public struct FuelPurchased has copy, drop {
    station_id: ID,
    buyer: address,
    amount: u64,
    price_paid: u64,
}

public struct FuelSupplied has copy, drop {
    station_id: ID,
    supplier: address,
    amount: u64,
    is_scarce: bool,
}

public struct RevenueClaimed has copy, drop {
    station_id: ID,
    supplier: address,
    amount: u64,
}

public struct SupplierWithdrawn has copy, drop {
    station_id: ID,
    receipt_id: ID,
    fuel_returned: u64,
    revenue_claimed: u64,
}

public struct PricingUpdated has copy, drop {
    station_id: ID,
    base_price: u64,
    alpha: u64,
}

// ============ Public functions ============

/// Create a new fuel station linked to a storage.
/// Fix H4: alpha capped at max_alpha().
public fun create_station(
    storage: &Storage,
    base_price: u64,
    alpha: u64,
    owner_fee_bps: u64,
    ctx: &mut TxContext,
): StationCap {
    assert!(owner_fee_bps <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);
    assert!(alpha <= constants::max_alpha(), E_ALPHA_TOO_HIGH);

    let station = FuelStation {
        id: object::new(ctx),
        storage_id: object::id(storage),
        owner: ctx.sender(),
        max_fuel: 0,
        current_fuel: 0,
        base_price,
        alpha,
        owner_fee_bps,
        total_supplied: 0,
        acc_reward_per_share: 0,
        revenue_pool: balance::zero(),
        fuel_reserve: balance::zero(),
    };

    let station_id = object::id(&station);

    event::emit(StationCreated {
        station_id,
        storage_id: object::id(storage),
        owner: ctx.sender(),
        base_price,
    });

    transfer::share_object(station);

    StationCap {
        id: object::new(ctx),
        station_id,
    }
}

/// AMM pricing: price = base_price * (FP + alpha * scarcity) / FP
/// scarcity = FP - (current * FP / max)
/// When no fuel supplied (max=0), price = base_price * (1 + alpha/FP)
public fun current_price(station: &FuelStation): u64 {
    let fp = constants::fp_scale();
    if (station.max_fuel == 0) {
        return station.base_price * (fp + station.alpha) / fp
    };
    let fill_ratio = station.current_fuel * fp / station.max_fuel;
    let scarcity = fp - fill_ratio;
    station.base_price * (fp + station.alpha * scarcity / fp) / fp
}

/// Supply fuel to the station. Fix C2: fuel goes into fuel_reserve Balance.
public fun supply_fuel(
    station: &mut FuelStation,
    fuel: Coin<FUEL>,
    ctx: &mut TxContext,
): SupplierReceipt {
    let amount = coin::value(&fuel);
    let fp = constants::fp_scale();

    // Check if scarce: current < max * 30%
    let is_scarce = station.max_fuel > 0 &&
        station.current_fuel * fp < station.max_fuel * constants::scarce_threshold();

    // Scarce bonus: effective amount = amount * 1.5
    let effective_amount = if (is_scarce) {
        amount * constants::scarce_bonus() / fp
    } else {
        amount
    };

    station.current_fuel = station.current_fuel + amount;
    station.max_fuel = station.max_fuel + amount;
    station.total_supplied = station.total_supplied + effective_amount;

    // Fix C2: store fuel in reserve instead of burning
    balance::join(&mut station.fuel_reserve, coin::into_balance(fuel));

    let receipt = SupplierReceipt {
        id: object::new(ctx),
        station_id: object::id(station),
        supply_record: SupplyRecord {
            amount: effective_amount,
            reward_debt: station.acc_reward_per_share,
        },
    };

    event::emit(FuelSupplied {
        station_id: object::id(station),
        supplier: ctx.sender(),
        amount,
        is_scarce,
    });

    receipt
}

/// Buy fuel from the station. Pays SUI, receives FUEL from reserve.
/// Fix C2: no treasury needed — fuel comes from fuel_reserve.
/// Fix H3: u128 accumulator math.
#[allow(lint(self_transfer))]
public fun buy_fuel(
    station: &mut FuelStation,
    mut payment: Coin<SUI>,
    amount: u64,
    max_price_per_unit: u64,
    ctx: &mut TxContext,
): Coin<FUEL> {
    assert!(station.current_fuel >= amount, E_INSUFFICIENT_FUEL);
    let price = current_price(station);
    assert!(price <= max_price_per_unit, E_PRICE_EXCEEDS_MAX);

    let total_cost = price * amount;
    assert!(coin::value(&payment) >= total_cost, E_INSUFFICIENT_PAYMENT);

    // Take exact payment, return change
    let paid = coin::split(&mut payment, total_cost, ctx);
    if (coin::value(&payment) > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        coin::destroy_zero(payment);
    };

    // Update station state
    station.current_fuel = station.current_fuel - amount;

    // Revenue distribution: owner_cut + supplier_pool
    let revenue = total_cost;
    let owner_cut = revenue * station.owner_fee_bps / constants::bps_scale();
    let supplier_pool = revenue - owner_cut;

    // Fix H3: update accumulator with u128 to prevent overflow
    if (station.total_supplied > 0) {
        let fp = (constants::fp_scale() as u128);
        station.acc_reward_per_share = station.acc_reward_per_share +
            (((supplier_pool as u128) * fp / (station.total_supplied as u128)) as u64);
    };

    // Add revenue to pool
    balance::join(&mut station.revenue_pool, coin::into_balance(paid));

    // Fix C2: take fuel from reserve instead of minting
    let fuel_balance = balance::split(&mut station.fuel_reserve, amount);
    let fuel_out = coin::from_balance(fuel_balance, ctx);

    event::emit(FuelPurchased {
        station_id: object::id(station),
        buyer: ctx.sender(),
        amount,
        price_paid: total_cost,
    });

    fuel_out
}

/// Claim accumulated revenue from the station.
/// Fix H3: u128 math. Fix M4: clamp to pool balance.
public fun claim_revenue(
    station: &mut FuelStation,
    receipt: &mut SupplierReceipt,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(receipt.station_id == object::id(station), E_RECEIPT_MISMATCH);

    let fp = (constants::fp_scale() as u128);
    // Fix H3: u128 accumulator math
    let pending = (((receipt.supply_record.amount as u128) *
        ((station.acc_reward_per_share - receipt.supply_record.reward_debt) as u128)) / fp) as u64;

    // Update reward debt
    receipt.supply_record.reward_debt = station.acc_reward_per_share;

    // Fix M4: clamp payout to actual pool balance
    let pool_balance = balance::value(&station.revenue_pool);
    let actual_payout = if (pending > pool_balance) { pool_balance } else { pending };

    if (actual_payout > 0) {
        let payout = balance::split(&mut station.revenue_pool, actual_payout);
        let payout_coin = coin::from_balance(payout, ctx);

        event::emit(RevenueClaimed {
            station_id: object::id(station),
            supplier: ctx.sender(),
            amount: actual_payout,
        });

        payout_coin
    } else {
        event::emit(RevenueClaimed {
            station_id: object::id(station),
            supplier: ctx.sender(),
            amount: 0,
        });
        coin::zero(ctx)
    }
}

/// Add more fuel to an existing SupplierReceipt.
/// Auto-flushes pending rewards before updating.
#[allow(lint(self_transfer))]
public fun add_supply(
    station: &mut FuelStation,
    receipt: &mut SupplierReceipt,
    fuel: Coin<FUEL>,
    ctx: &mut TxContext,
) {
    assert!(receipt.station_id == object::id(station), E_RECEIPT_MISMATCH);

    // Auto-flush pending rewards
    let fp = (constants::fp_scale() as u128);
    let pending = (((receipt.supply_record.amount as u128) *
        ((station.acc_reward_per_share - receipt.supply_record.reward_debt) as u128)) / fp) as u64;

    if (pending > 0) {
        let pool_balance = balance::value(&station.revenue_pool);
        let actual_payout = if (pending > pool_balance) { pool_balance } else { pending };
        if (actual_payout > 0) {
            let payout = balance::split(&mut station.revenue_pool, actual_payout);
            transfer::public_transfer(coin::from_balance(payout, ctx), ctx.sender());
        };
    };

    let amount = coin::value(&fuel);
    let is_scarce = station.max_fuel > 0 &&
        station.current_fuel * (constants::fp_scale()) < station.max_fuel * constants::scarce_threshold();
    let effective_amount = if (is_scarce) {
        amount * constants::scarce_bonus() / constants::fp_scale()
    } else {
        amount
    };

    station.current_fuel = station.current_fuel + amount;
    station.max_fuel = station.max_fuel + amount;
    station.total_supplied = station.total_supplied + effective_amount;

    receipt.supply_record.amount = receipt.supply_record.amount + effective_amount;
    receipt.supply_record.reward_debt = station.acc_reward_per_share;

    // Fix C2: store in reserve
    balance::join(&mut station.fuel_reserve, coin::into_balance(fuel));

    event::emit(FuelSupplied {
        station_id: object::id(station),
        supplier: ctx.sender(),
        amount,
        is_scarce,
    });
}

/// Supplier exits: claims pending revenue + proportional fuel return.
/// Fix C2: no treasury needed — fuel comes from fuel_reserve.
public fun withdraw_supplier(
    station: &mut FuelStation,
    receipt: SupplierReceipt,
    ctx: &mut TxContext,
): (Coin<SUI>, Coin<FUEL>) {
    assert!(receipt.station_id == object::id(station), E_RECEIPT_MISMATCH);

    let fp = (constants::fp_scale() as u128);

    // Calculate pending revenue (Fix H3: u128)
    let pending = (((receipt.supply_record.amount as u128) *
        ((station.acc_reward_per_share - receipt.supply_record.reward_debt) as u128)) / fp) as u64;

    // Fix M4: clamp to pool balance
    let pool_balance = balance::value(&station.revenue_pool);
    let actual_payout = if (pending > pool_balance) { pool_balance } else { pending };

    let revenue_coin = if (actual_payout > 0) {
        let payout = balance::split(&mut station.revenue_pool, actual_payout);
        coin::from_balance(payout, ctx)
    } else {
        coin::zero<SUI>(ctx)
    };

    // Calculate proportional fuel to return
    let fuel_share = if (station.total_supplied > 0) {
        // Use u128 to prevent overflow on large values
        (((station.current_fuel as u128) * (receipt.supply_record.amount as u128)
            / (station.total_supplied as u128)) as u64)
    } else {
        0
    };

    // Clamp fuel_share to available reserve
    let reserve_balance = balance::value(&station.fuel_reserve);
    let actual_fuel = if (fuel_share > reserve_balance) { reserve_balance } else { fuel_share };

    // Update station state
    station.current_fuel = station.current_fuel - actual_fuel;
    station.total_supplied = station.total_supplied - receipt.supply_record.amount;

    // Fix C2: take from reserve instead of minting
    let fuel_coin = if (actual_fuel > 0) {
        coin::from_balance(balance::split(&mut station.fuel_reserve, actual_fuel), ctx)
    } else {
        coin::zero<FUEL>(ctx)
    };

    let receipt_id = object::id(&receipt);
    event::emit(SupplierWithdrawn {
        station_id: object::id(station),
        receipt_id,
        fuel_returned: actual_fuel,
        revenue_claimed: actual_payout,
    });

    // Destroy receipt
    let SupplierReceipt { id, station_id: _, supply_record: _ } = receipt;
    object::delete(id);

    (revenue_coin, fuel_coin)
}

/// Update pricing parameters (station owner only).
/// Fix H4: alpha capped at max_alpha().
public fun update_pricing(station: &mut FuelStation, cap: &StationCap, base_price: u64, alpha: u64) {
    assert!(cap.station_id == object::id(station), E_CAP_MISMATCH);
    assert!(alpha <= constants::max_alpha(), E_ALPHA_TOO_HIGH);
    station.base_price = base_price;
    station.alpha = alpha;
    event::emit(PricingUpdated {
        station_id: object::id(station),
        base_price,
        alpha,
    });
}

/// Update owner fee (station owner only, capped at MAX_OWNER_FEE_BPS)
public fun update_fee(station: &mut FuelStation, cap: &StationCap, owner_fee_bps: u64) {
    assert!(cap.station_id == object::id(station), E_CAP_MISMATCH);
    assert!(owner_fee_bps <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);
    station.owner_fee_bps = owner_fee_bps;
}

// ============ Getters ============

public fun fuel_level(station: &FuelStation): (u64, u64) {
    (station.current_fuel, station.max_fuel)
}

public fun station_id_from_cap(cap: &StationCap): ID { cap.station_id }
public fun station_owner(station: &FuelStation): address { station.owner }
public fun station_base_price(station: &FuelStation): u64 { station.base_price }
public fun station_alpha(station: &FuelStation): u64 { station.alpha }
public fun station_owner_fee_bps(station: &FuelStation): u64 { station.owner_fee_bps }
public fun station_total_supplied(station: &FuelStation): u64 { station.total_supplied }
