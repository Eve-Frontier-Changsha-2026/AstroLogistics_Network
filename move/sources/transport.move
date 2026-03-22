module astrologistics::transport;

use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::fuel::{Self, FUEL, FuelTreasuryCap};
use astrologistics::constants;

// ============ Error codes ============
const E_FUEL_COST_TOO_LOW: u64 = 0;
const E_FUEL_COST_TOO_HIGH: u64 = 1;
const E_INVALID_TIER: u64 = 2;
const E_TOO_EARLY: u64 = 3;
const E_WRONG_STATUS: u64 = 4;
const E_NOT_OWNER: u64 = 5;
const E_STORAGE_MISMATCH: u64 = 6;

// ============ Structs ============

public struct TransportOrder has key, store {
    id: UID,
    sender: address,
    from_storage: ID,
    to_storage: ID,
    receipt: Option<DepositReceipt>,
    cargo_weight: u64,
    route: vector<u64>,
    fuel_cost: u64,
    danger_snapshot: u64,
    tier: u8,
    earliest_complete_at: u64,
    status: u8,   // 0=Created, 1=FuelPaid, 2=Completed
    created_at: u64,
}

// ============ Events ============

public struct TransportCreated has copy, drop {
    order_id: ID,
    sender: address,
    from_storage: ID,
    to_storage: ID,
    tier: u8,
    fuel_cost: u64,
}

public struct TransportPaid has copy, drop {
    order_id: ID,
    fuel_amount: u64,
}

public struct TransportCompleted has copy, drop {
    order_id: ID,
    new_receipt_id: ID,
}

public struct TransportCancelled has copy, drop {
    order_id: ID,
}

// ============ Tier helpers ============

fun tier_delay(tier: u8): u64 {
    if (tier == 0) { constants::tier_delay_instant() }
    else if (tier == 1) { constants::tier_delay_express() }
    else if (tier == 2) { constants::tier_delay_standard() }
    else { abort E_INVALID_TIER }
}

// ============ Public functions ============

/// Create a transport order. Receipt is moved in by value.
/// fuel_cost is validated against min/max bounds based on cargo weight.
public fun create_order(
    from_storage: &Storage,
    to_storage: &Storage,
    receipt: DepositReceipt,
    route: vector<u64>,
    fuel_cost: u64,
    danger_snapshot: u64,
    tier: u8,
    clock: &Clock,
    ctx: &mut TxContext,
): TransportOrder {
    assert!(tier <= 2, E_INVALID_TIER);

    // Validate receipt belongs to from_storage (before any ObjectBag lookup)
    assert!(storage::receipt_storage_id(&receipt) == object::id(from_storage), E_STORAGE_MISMATCH);

    // Read cargo weight from storage
    let cargo_id = storage::receipt_cargo_id(&receipt);
    let weight = storage::cargo_weight_by_id(from_storage, cargo_id);

    // Validate fuel_cost bounds
    let min_cost = constants::min_fuel_cost_per_weight() * weight;
    let max_cost = constants::max_fuel_cost_per_weight() * weight;
    assert!(fuel_cost >= min_cost, E_FUEL_COST_TOO_LOW);
    assert!(fuel_cost <= max_cost, E_FUEL_COST_TOO_HIGH);

    let now = clock::timestamp_ms(clock);
    let delay = tier_delay(tier);

    let from_id = object::id(from_storage);
    let to_id = object::id(to_storage);

    let order = TransportOrder {
        id: object::new(ctx),
        sender: ctx.sender(),
        from_storage: from_id,
        to_storage: to_id,
        receipt: option::some(receipt),
        cargo_weight: weight,
        route,
        fuel_cost,
        danger_snapshot,
        tier,
        earliest_complete_at: now + delay,
        status: 0,
        created_at: now,
    };

    event::emit(TransportCreated {
        order_id: object::id(&order),
        sender: ctx.sender(),
        from_storage: from_id,
        to_storage: to_id,
        tier,
        fuel_cost,
    });

    order
}

/// Pay fuel for the transport order.
/// Fix M3: splits exact fuel_cost, returns excess to sender.
#[allow(lint(self_transfer))]
public fun pay_fuel(
    order: &mut TransportOrder,
    mut fuel: Coin<FUEL>,
    treasury: &mut FuelTreasuryCap,
    ctx: &mut TxContext,
) {
    assert!(order.status == 0, E_WRONG_STATUS);
    assert!(coin::value(&fuel) >= order.fuel_cost, E_FUEL_COST_TOO_LOW);

    // Split exact amount to burn
    let exact = coin::split(&mut fuel, order.fuel_cost, ctx);
    fuel::burn(treasury, exact);

    // Return excess
    if (coin::value(&fuel) > 0) {
        transfer::public_transfer(fuel, ctx.sender());
    } else {
        coin::destroy_zero(fuel);
    };

    order.status = 1;

    event::emit(TransportPaid {
        order_id: object::id(order),
        fuel_amount: order.fuel_cost,
    });
}

/// Complete the transport. Extracts cargo from source storage, deposits at destination.
/// Fix H5: uses remove_cargo_for_transport + deposit_cargo (preserves original cargo value).
/// Returns new DepositReceipt at destination.
public fun complete_transport(
    mut order: TransportOrder,
    from_storage: &mut Storage,
    to_storage: &mut Storage,
    clock: &Clock,
    ctx: &mut TxContext,
): DepositReceipt {
    assert!(order.status == 1, E_WRONG_STATUS);
    assert!(order.sender == ctx.sender(), E_NOT_OWNER); // Fix M-5: sender auth
    assert!(object::id(from_storage) == order.from_storage, E_STORAGE_MISMATCH);
    assert!(object::id(to_storage) == order.to_storage, E_STORAGE_MISMATCH);

    let now = clock::timestamp_ms(clock);
    assert!(now >= order.earliest_complete_at, E_TOO_EARLY);

    // Extract receipt from order
    let receipt = option::extract(&mut order.receipt);

    // Fix H5: remove cargo from source storage (cleans ObjectBag + live_receipts + current_load)
    let cargo = storage::remove_cargo_for_transport(from_storage, receipt);

    // Fix M5: deposit original cargo at destination (preserves value)
    let new_receipt = storage::deposit_cargo(to_storage, cargo, clock, ctx);

    let new_receipt_id = object::id(&new_receipt);
    let order_id = object::uid_to_inner(&order.id);

    // Destroy order
    let TransportOrder {
        id, sender: _, from_storage: _, to_storage: _, receipt: remaining,
        cargo_weight: _, route: _, fuel_cost: _, danger_snapshot: _,
        tier: _, earliest_complete_at: _, status: _, created_at: _,
    } = order;
    option::destroy_none(remaining);
    object::delete(id);

    event::emit(TransportCompleted { order_id, new_receipt_id });

    new_receipt
}

/// Cancel order before fuel payment. Returns receipt to sender.
/// Fix Low: saves order_id before deleting UID.
public fun cancel_order(
    order: TransportOrder,
    ctx: &mut TxContext,
): DepositReceipt {
    assert!(order.status == 0, E_WRONG_STATUS);
    assert!(order.sender == ctx.sender(), E_NOT_OWNER);

    let TransportOrder {
        id, sender: _, from_storage: _, to_storage: _, mut receipt,
        cargo_weight: _, route: _, fuel_cost: _, danger_snapshot: _,
        tier: _, earliest_complete_at: _, status: _, created_at: _,
    } = order;

    let returned_receipt = option::extract(&mut receipt);
    option::destroy_none(receipt);

    // Fix Low: extract ID before delete
    let order_id = object::uid_to_inner(&id);
    object::delete(id);

    event::emit(TransportCancelled { order_id });

    returned_receipt
}

// ============ Getters ============

public fun order_tier(order: &TransportOrder): u8 { order.tier }
public fun order_fuel_cost(order: &TransportOrder): u64 { order.fuel_cost }
public fun order_status(order: &TransportOrder): u8 { order.status }
public fun order_earliest_complete_at(order: &TransportOrder): u64 { order.earliest_complete_at }
public fun order_sender(order: &TransportOrder): address { order.sender }
public fun order_from_storage(order: &TransportOrder): ID { order.from_storage }
public fun order_to_storage(order: &TransportOrder): ID { order.to_storage }
