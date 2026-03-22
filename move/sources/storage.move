module astrologistics::storage;

use sui::object_bag::{Self, ObjectBag};
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::event;
use sui::dynamic_field;
use astrologistics::constants;
use astrologistics::guild::{Self, Guild, GuildMemberCap};

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
const E_ZERO_WEIGHT: u64 = 9;       // Fix H-5
const E_ZERO_VALUE: u64 = 10;       // Fix H-5
const E_NOT_GUILD_MEMBER: u64 = 11;
const E_NO_GUILD: u64 = 12;
const E_GUILD_MISMATCH: u64 = 13;

// ============ Structs ============

public struct GuildIdKey has copy, drop, store {}

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

public struct StorageShared has copy, drop {
    storage_id: ID,
    owner: address,
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

/// Create a private (owned) storage. NOT shared — only owner can interact.
/// Call share_storage() later to permanently convert to shared.
public fun create_private_storage(
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

    // Transfer to owner (owned object, not shared)
    transfer::transfer(storage, ctx.sender());

    AdminCap {
        id: object::new(ctx),
        storage_id,
    }
}

#[allow(lint(share_owned))]
/// Permanently convert an owned storage to shared. Irreversible (SUI limitation).
/// This enables other players to deposit/withdraw and interact with the storage.
public fun share_storage(storage: Storage) {
    let storage_id = object::id(&storage);
    let owner = storage.owner;
    event::emit(StorageShared { storage_id, owner });
    transfer::share_object(storage);
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

// ============ Deposit / Withdraw ============

/// Deposit cargo into storage. Returns a DepositReceipt.
public fun deposit(
    storage: &mut Storage,
    item_type: vector<u8>,
    weight: u64,
    value: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): DepositReceipt {
    // Fix H-5: reject zero-weight/value cargo
    assert!(weight > 0, E_ZERO_WEIGHT);
    assert!(value > 0, E_ZERO_VALUE);
    assert!(storage.current_load + weight <= storage.max_capacity, E_CAPACITY_EXCEEDED);

    let cargo = Cargo {
        id: object::new(ctx),
        owner: ctx.sender(),
        item_type,
        weight,
        value,
        storage_id: object::id(storage),
        deposited_at: clock::timestamp_ms(clock),
    };

    let cargo_id = object::id(&cargo);
    storage.current_load = storage.current_load + weight;
    object_bag::add(&mut storage.cargo_bag, cargo_id, cargo);

    let receipt = DepositReceipt {
        id: object::new(ctx),
        storage_id: object::id(storage),
        cargo_id,
        depositor: ctx.sender(),
    };
    table::add(&mut storage.live_receipts, cargo_id, true);

    event::emit(CargoDeposited {
        storage_id: object::id(storage),
        cargo_id,
        depositor: ctx.sender(),
        weight,
        value,
    });

    receipt
}

#[allow(lint(self_transfer))]
/// Withdraw cargo using a DepositReceipt. Collects storage fee.
/// Fee is calculated: value * fee_rate_bps * days_stored / BPS_SCALE
/// Fee is collected into Storage's accumulated_fees balance.
public fun withdraw(
    storage: &mut Storage,
    receipt: DepositReceipt,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Cargo {
    let DepositReceipt { id, storage_id, cargo_id, depositor: _ } = receipt;
    assert!(storage_id == object::id(storage), E_RECEIPT_MISMATCH);
    assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);
    object::delete(id);

    // Remove live receipt tracking
    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };

    // Remove cargo from bag
    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;

    // Calculate storage fee: value * fee_rate_bps * days_stored / BPS_SCALE
    // Use u128 to prevent overflow (Fix M2)
    let now = clock::timestamp_ms(clock);
    let duration_ms = if (now > cargo.deposited_at) { now - cargo.deposited_at } else { 0 };
    let days_stored = duration_ms / 86_400_000;
    let fee = if (days_stored == 0) { 0 } else {
        ((
            (cargo.value as u128) *
            (storage.fee_rate_bps as u128) *
            (days_stored as u128) /
            (constants::bps_scale() as u128)
        ) as u64)
    };

    // Collect fee (Fix C1)
    assert!(coin::value(&payment) >= fee, E_INSUFFICIENT_FEE);
    if (fee > 0) {
        let mut payment_balance = coin::into_balance(payment);
        let fee_balance = balance::split(&mut payment_balance, fee);
        balance::join(&mut storage.accumulated_fees, fee_balance);
        // Return excess to caller
        if (balance::value(&payment_balance) > 0) {
            transfer::public_transfer(
                coin::from_balance(payment_balance, ctx),
                ctx.sender(),
            );
        } else {
            balance::destroy_zero(payment_balance);
        };
    } else {
        // No fee — return full payment
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, ctx.sender());
        } else {
            coin::destroy_zero(payment);
        };
    };

    event::emit(CargoWithdrawn {
        storage_id: object::id(storage),
        cargo_id,
        withdrawer: ctx.sender(),
        storage_fee: fee,
    });

    cargo
}

/// Calculate storage fee for a cargo (view function)
public fun calculate_fee(storage: &Storage, cargo_id: ID, clock: &Clock): u64 {
    let cargo: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    let now = clock::timestamp_ms(clock);
    let duration_ms = if (now > cargo.deposited_at) { now - cargo.deposited_at } else { 0 };
    let days_stored = duration_ms / 86_400_000;
    if (days_stored == 0) { 0 } else {
        (((cargo.value as u128) * (storage.fee_rate_bps as u128) * (days_stored as u128) / (constants::bps_scale() as u128)) as u64)
    }
}

/// Admin claims accumulated fees
public fun claim_fees(
    storage: &mut Storage,
    cap: &AdminCap,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    let amount = balance::value(&storage.accumulated_fees);
    if (amount > 0) {
        coin::from_balance(balance::split(&mut storage.accumulated_fees, amount), ctx)
    } else {
        coin::zero(ctx)
    }
}

// ============ Auth / Reclaim / Admin ============

/// Withdraw using hot-potato auth (for third-party withdrawals like courier).
/// WithdrawAuth has zero abilities — must be explicitly destructured here.
#[allow(lint(self_transfer))]
public fun withdraw_with_auth(
    storage: &mut Storage,
    receipt: DepositReceipt,
    auth: WithdrawAuth,
    payment: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): Cargo {
    let receipt_id = object::id(&receipt);
    let WithdrawAuth { receipt_id: auth_receipt_id, authorized_by: _ } = auth;
    assert!(auth_receipt_id == receipt_id, E_AUTH_MISMATCH);
    withdraw(storage, receipt, payment, clock, ctx)
}

/// Admin reclaim orphaned cargo after grace period.
/// Only works when the receipt has been consumed (no live_receipt).
public fun admin_reclaim(
    storage: &mut Storage,
    cap: &AdminCap,
    cargo_id: ID,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);
    assert!(!table::contains(&storage.live_receipts, cargo_id), E_RECEIPT_STILL_LIVE);

    // Check grace period
    let cargo_ref: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    let now = clock::timestamp_ms(clock);
    assert!(now >= cargo_ref.deposited_at + constants::reclaim_grace_ms(), E_GRACE_PERIOD_NOT_MET);

    // Remove cargo
    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;

    event::emit(AdminReclaimed {
        storage_id: object::id(storage),
        cargo_id,
    });

    // Destroy cargo
    let Cargo { id, owner: _, item_type: _, weight: _, value: _, storage_id: _, deposited_at: _ } = cargo;
    object::delete(id);
}

/// Update storage fee rate (admin only, capped at MAX_OWNER_FEE_BPS)
public fun update_fee_rate(storage: &mut Storage, cap: &AdminCap, new_rate: u64) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    assert!(new_rate <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);
    storage.fee_rate_bps = new_rate;
}

/// Remove cargo for transport (package-level). Cleans up ObjectBag + live_receipts + current_load.
/// Returns Cargo for re-deposit at destination.
public(package) fun remove_cargo_for_transport(
    storage: &mut Storage,
    receipt: DepositReceipt,
): Cargo {
    let DepositReceipt { id, storage_id, cargo_id, depositor: _ } = receipt;
    assert!(storage_id == object::id(storage), E_RECEIPT_MISMATCH);
    assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);
    object::delete(id);

    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };

    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;
    cargo
}

/// Deposit an existing Cargo object (package-level, for transport re-deposit).
public(package) fun deposit_cargo(
    storage: &mut Storage,
    cargo: Cargo,
    _clock: &Clock,
    ctx: &mut TxContext,
): DepositReceipt {
    assert!(storage.current_load + cargo.weight <= storage.max_capacity, E_CAPACITY_EXCEEDED);

    let cargo_id = object::id(&cargo);
    let weight = cargo.weight;
    let value = cargo.value;
    storage.current_load = storage.current_load + weight;
    object_bag::add(&mut storage.cargo_bag, cargo_id, cargo);

    let receipt = DepositReceipt {
        id: object::new(ctx),
        storage_id: object::id(storage),
        cargo_id,
        depositor: ctx.sender(),
    };
    table::add(&mut storage.live_receipts, cargo_id, true);

    event::emit(CargoDeposited {
        storage_id: object::id(storage),
        cargo_id,
        depositor: ctx.sender(),
        weight,
        value,
    });

    receipt
}

// ============ Guild Integration ============

/// Set guild_id on a storage (AdminCap gated). Uses dynamic_field (upgrade-safe).
public fun set_storage_guild(storage: &mut Storage, cap: &AdminCap, guild_id: ID) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    if (dynamic_field::exists_(&storage.id, GuildIdKey {})) {
        *dynamic_field::borrow_mut(&mut storage.id, GuildIdKey {}) = guild_id;
    } else {
        dynamic_field::add(&mut storage.id, GuildIdKey {}, guild_id);
    };
}

/// Remove guild_id from a storage (AdminCap gated).
public fun remove_storage_guild(storage: &mut Storage, cap: &AdminCap) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    if (dynamic_field::exists_(&storage.id, GuildIdKey {})) {
        let _: ID = dynamic_field::remove(&mut storage.id, GuildIdKey {});
    };
}

/// Get guild_id of a storage. Returns None if not set.
public fun storage_guild_id(storage: &Storage): Option<ID> {
    if (dynamic_field::exists_(&storage.id, GuildIdKey {})) {
        option::some(*dynamic_field::borrow(&storage.id, GuildIdKey {}))
    } else {
        option::none()
    }
}

/// Withdraw with guild member fee discount.
/// Discount: fee * (BPS_SCALE - guild_fee_discount_bps) / BPS_SCALE
#[allow(lint(self_transfer))]
public fun withdraw_as_guild_member(
    storage: &mut Storage,
    receipt: DepositReceipt,
    payment: Coin<SUI>,
    guild: &Guild,
    guild_cap: &GuildMemberCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Cargo {
    // Verify guild membership
    assert!(guild::verify_membership(guild, guild_cap), E_NOT_GUILD_MEMBER);
    // Verify storage has a guild and it matches
    let storage_guild = storage_guild_id(storage);
    assert!(option::is_some(&storage_guild), E_NO_GUILD);
    assert!(*option::borrow(&storage_guild) == object::id(guild), E_GUILD_MISMATCH);

    let DepositReceipt { id, storage_id, cargo_id, depositor: _ } = receipt;
    assert!(storage_id == object::id(storage), E_RECEIPT_MISMATCH);
    assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);
    object::delete(id);

    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };

    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;

    // Calculate fee with guild discount
    let now = clock::timestamp_ms(clock);
    let duration_ms = if (now > cargo.deposited_at) { now - cargo.deposited_at } else { 0 };
    let days_stored = duration_ms / 86_400_000;
    let base_fee = if (days_stored == 0) { 0 } else {
        (((cargo.value as u128) * (storage.fee_rate_bps as u128) * (days_stored as u128)
          / (constants::bps_scale() as u128)) as u64)
    };
    // Apply guild discount
    let fee = ((base_fee as u128)
        * ((constants::bps_scale() - constants::guild_fee_discount_bps()) as u128)
        / (constants::bps_scale() as u128)) as u64;

    assert!(coin::value(&payment) >= fee, E_INSUFFICIENT_FEE);
    if (fee > 0) {
        let mut payment_balance = coin::into_balance(payment);
        let fee_balance = balance::split(&mut payment_balance, fee);
        balance::join(&mut storage.accumulated_fees, fee_balance);
        if (balance::value(&payment_balance) > 0) {
            transfer::public_transfer(coin::from_balance(payment_balance, ctx), ctx.sender());
        } else {
            balance::destroy_zero(payment_balance);
        };
    } else {
        if (coin::value(&payment) > 0) {
            transfer::public_transfer(payment, ctx.sender());
        } else {
            coin::destroy_zero(payment);
        };
    };

    event::emit(CargoWithdrawn {
        storage_id: object::id(storage),
        cargo_id,
        withdrawer: ctx.sender(),
        storage_fee: fee,
    });

    cargo
}

#[test_only]
/// Create private storage and immediately share it (same tx).
/// Workaround: SUI test framework doesn't support owned→shared conversion across txs.
public fun create_private_storage_and_share(
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

    event::emit(StorageShared { storage_id, owner: ctx.sender() });
    transfer::share_object(storage);

    AdminCap {
        id: object::new(ctx),
        storage_id,
    }
}

#[test_only]
/// Clear live_receipt for a cargo (simulates receipt consumption by upper modules)
public fun clear_live_receipt_for_testing(storage: &mut Storage, cargo_id: ID) {
    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };
}
