module astrologistics::storage;

use sui::object_bag::{Self, ObjectBag};
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::event;
use astrologistics::constants;

// ============ Error codes ============
const E_CAP_MISMATCH: u64 = 0;
const E_CAPACITY_EXCEEDED: u64 = 1;
const E_RECEIPT_MISMATCH: u64 = 2;
const E_AUTH_MISMATCH: u64 = 3;
const E_RECEIPT_STILL_LIVE: u64 = 4;
const E_GRACE_PERIOD_NOT_MET: u64 = 5;
const E_CARGO_NOT_FOUND: u64 = 6;
const E_FEE_TOO_HIGH: u64 = 7;
const E_INSUFFICIENT_FEE: u64 = 8;

// ============ Structs ============

public struct Storage has key {
    id: UID,
    owner: address,
    system_id: u64,
    max_capacity: u64,
    current_load: u64,
    fee_rate_bps: u64,
    cargo_bag: ObjectBag,
    live_receipts: Table<ID, bool>,
    accumulated_fees: Balance<SUI>,
    created_at: u64,
}

public struct AdminCap has key, store {
    id: UID,
    storage_id: ID,
}

public struct Cargo has key, store {
    id: UID,
    owner: address,
    item_type: vector<u8>,
    weight: u64,
    value: u64,
    storage_id: ID,
    deposited_at: u64,
}

public struct DepositReceipt has key, store {
    id: UID,
    storage_id: ID,
    cargo_id: ID,
    depositor: address,
}

/// Hot-potato: zero abilities — compiler forces consumption in same PTB.
/// Used by upper-layer modules (courier_market) to authorize third-party withdrawals.
public struct WithdrawAuth {
    receipt_id: ID,
    authorized_by: ID,
}

// ============ Events ============

public struct StorageCreated has copy, drop {
    storage_id: ID,
    owner: address,
    system_id: u64,
    max_capacity: u64,
}

public struct CargoDeposited has copy, drop {
    storage_id: ID,
    cargo_id: ID,
    depositor: address,
    weight: u64,
    value: u64,
}

public struct CargoWithdrawn has copy, drop {
    storage_id: ID,
    cargo_id: ID,
    withdrawer: address,
    storage_fee: u64,
}

public struct AdminReclaimed has copy, drop {
    storage_id: ID,
    cargo_id: ID,
}

// ============ Public functions ============

public fun create_storage(
    system_id: u64,
    max_capacity: u64,
    fee_rate_bps: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): AdminCap {
    assert!(fee_rate_bps <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);

    let storage = Storage {
        id: object::new(ctx),
        owner: ctx.sender(),
        system_id,
        max_capacity,
        current_load: 0,
        fee_rate_bps,
        cargo_bag: object_bag::new(ctx),
        live_receipts: table::new(ctx),
        accumulated_fees: balance::zero(),
        created_at: clock::timestamp_ms(clock),
    };
    let storage_id = object::id(&storage);
    event::emit(StorageCreated {
        storage_id,
        owner: ctx.sender(),
        system_id,
        max_capacity,
    });
    transfer::share_object(storage);
    AdminCap {
        id: object::new(ctx),
        storage_id,
    }
}

// ============ Getters ============

public fun system_id(storage: &Storage): u64 { storage.system_id }
public fun available_capacity(storage: &Storage): u64 { storage.max_capacity - storage.current_load }
public fun fee_rate(storage: &Storage): u64 { storage.fee_rate_bps }
public fun current_load(storage: &Storage): u64 { storage.current_load }
public fun storage_id_from_cap(cap: &AdminCap): ID { cap.storage_id }

// Cargo getters — by reference
public fun cargo_weight(cargo: &Cargo): u64 { cargo.weight }
public fun cargo_value(cargo: &Cargo): u64 { cargo.value }
public fun cargo_owner(cargo: &Cargo): address { cargo.owner }
public fun cargo_item_type(cargo: &Cargo): &vector<u8> { &cargo.item_type }

// Cargo getters — by storage + cargo_id (for upper modules)
public fun cargo_weight_by_id(storage: &Storage, cargo_id: ID): u64 {
    let cargo: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    cargo.weight
}
public fun cargo_value_by_id(storage: &Storage, cargo_id: ID): u64 {
    let cargo: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    cargo.value
}

// Receipt getters
public fun receipt_storage_id(receipt: &DepositReceipt): ID { receipt.storage_id }
public fun receipt_cargo_id(receipt: &DepositReceipt): ID { receipt.cargo_id }

// WithdrawAuth constructor — package-level only
public(package) fun create_withdraw_auth(receipt_id: ID, authorized_by: ID): WithdrawAuth {
    WithdrawAuth { receipt_id, authorized_by }
}

#[test_only]
/// Clear live_receipt for a cargo (simulates receipt consumption by upper modules)
public fun clear_live_receipt_for_testing(storage: &mut Storage, cargo_id: ID) {
    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };
}
