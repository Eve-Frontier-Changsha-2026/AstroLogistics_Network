module astrologistics::courier_market;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::clock::{Self, Clock};
use sui::event;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::threat_oracle::{Self, OracleCap, ReporterCap};
use astrologistics::constants;

// ============ Error codes ============
const E_WRONG_STATUS: u64 = 0;
const E_NOT_CLIENT: u64 = 1;
const E_NOT_COURIER: u64 = 2;
const E_DEPOSIT_TOO_LOW: u64 = 3;
const E_NOT_TIMED_OUT: u64 = 4;
const E_BADGE_MISMATCH: u64 = 5;
const E_STORAGE_MISMATCH: u64 = 6;
const E_DEADLINE_TOO_SHORT: u64 = 7;
const E_ALREADY_CONFIRMED: u64 = 8;
const E_SAME_STORAGE: u64 = 9;        // Fix Low
const E_REWARD_TOO_LOW: u64 = 10;     // Fix H8

// Status constants (Fix M6: removed IN_DELIVERY)
const STATUS_OPEN: u8 = 0;
const STATUS_ACCEPTED: u8 = 1;
const STATUS_PENDING_CONFIRM: u8 = 2;
const STATUS_DELIVERED: u8 = 3;
const STATUS_DISPUTED: u8 = 4;

// Timing constants
const MIN_DEADLINE_MS: u64 = 3_600_000;      // 1 hour
const PICKUP_DEADLINE_MS: u64 = 7_200_000;   // 2 hours
const CONFIRM_DEADLINE_MS: u64 = 86_400_000; // 24 hours
const DISPUTE_TIMEOUT_MS: u64 = 259_200_000; // 72 hours (Fix M7)

// ============ Structs ============

public struct CourierContract has key {
    id: UID,
    client: address,
    courier: option::Option<address>,
    from_storage: ID,
    to_storage: ID,
    cargo_receipt: option::Option<DepositReceipt>,
    reward: u64,
    client_deposit: Balance<SUI>,
    courier_deposit: Balance<SUI>,
    min_courier_deposit: u64,
    cargo_value: u64,
    route: vector<u64>,
    status: u8,
    deadline: u64,
    pickup_deadline: u64,
    confirm_deadline: u64,
    dispute_deadline: u64,  // Fix M7
    created_at: u64,
}

public struct CourierBadge has key, store {
    id: UID,
    contract_id: ID,
    courier: address,
}

// ============ Events ============

public struct ContractCreated has copy, drop {
    contract_id: ID,
    client: address,
    from_storage: ID,
    to_storage: ID,
    reward: u64,
    deadline: u64,
}

public struct ContractAccepted has copy, drop {
    contract_id: ID,
    courier: address,
    deposit_amount: u64,
}

public struct CargoPickedUpAndDelivered has copy, drop {
    contract_id: ID,
    from_storage: ID,
    to_storage: ID,
}

public struct DeliveryConfirmed has copy, drop {
    contract_id: ID,
}

public struct DisputeRaised has copy, drop {
    contract_id: ID,
    client: address,
    dispute_deadline: u64,
}

public struct DisputeResolved has copy, drop {
    contract_id: ID,
    ruling: u8,
}

public struct ContractSettled has copy, drop {
    contract_id: ID,
    courier_reward: u64,
    reporter_cap_id: ID,
}

public struct ContractCancelled has copy, drop {
    contract_id: ID,
    client: address,
}

public struct TimeoutClaimed has copy, drop {
    contract_id: ID,
    stage: u8,
    keeper: address,
    bounty: u64,
}

// ============ Public functions ============

/// Create a courier contract. Client locks reward + cancel_penalty.
/// min_courier_deposit is forced >= cargo.value.
public fun create_contract(
    from_storage: &Storage,
    to_storage: &Storage,
    receipt: DepositReceipt,
    reward: Coin<SUI>,
    cancel_penalty: Coin<SUI>,
    min_courier_deposit: u64,
    route: vector<u64>,
    deadline_duration: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): ID {
    let now = clock::timestamp_ms(clock);
    assert!(deadline_duration >= MIN_DEADLINE_MS, E_DEADLINE_TOO_SHORT);
    // Fix Low: from != to
    assert!(object::id(from_storage) != object::id(to_storage), E_SAME_STORAGE);
    // Fix H8: minimum reward
    assert!(coin::value(&reward) >= constants::min_contract_reward(), E_REWARD_TOO_LOW);

    // Read cargo value for deposit enforcement
    let cargo_id = storage::receipt_cargo_id(&receipt);
    let cargo_value = storage::cargo_value_by_id(from_storage, cargo_id);

    // Enforce min_courier_deposit >= cargo_value
    let effective_min_deposit = if (min_courier_deposit > cargo_value) {
        min_courier_deposit
    } else {
        cargo_value
    };

    let reward_amount = coin::value(&reward);
    let mut client_balance = coin::into_balance(reward);
    balance::join(&mut client_balance, coin::into_balance(cancel_penalty));

    let contract = CourierContract {
        id: object::new(ctx),
        client: ctx.sender(),
        courier: option::none(),
        from_storage: object::id(from_storage),
        to_storage: object::id(to_storage),
        cargo_receipt: option::some(receipt),
        reward: reward_amount,
        client_deposit: client_balance,
        courier_deposit: balance::zero(),
        min_courier_deposit: effective_min_deposit,
        cargo_value,
        route,
        status: STATUS_OPEN,
        deadline: now + deadline_duration,
        pickup_deadline: 0,
        confirm_deadline: 0,
        dispute_deadline: 0,
        created_at: now,
    };

    let contract_id = object::id(&contract);

    event::emit(ContractCreated {
        contract_id,
        client: ctx.sender(),
        from_storage: object::id(from_storage),
        to_storage: object::id(to_storage),
        reward: reward_amount,
        deadline: now + deadline_duration,
    });

    transfer::share_object(contract);
    contract_id
}

// ============ Getters ============

public fun contract_status(c: &CourierContract): u8 { c.status }
public fun contract_reward(c: &CourierContract): u64 { c.reward }
public fun contract_client(c: &CourierContract): address { c.client }
public fun contract_deadline(c: &CourierContract): u64 { c.deadline }
public fun contract_min_deposit(c: &CourierContract): u64 { c.min_courier_deposit }
public fun contract_cargo_value(c: &CourierContract): u64 { c.cargo_value }
public fun contract_pickup_deadline(c: &CourierContract): u64 { c.pickup_deadline }
public fun contract_confirm_deadline(c: &CourierContract): u64 { c.confirm_deadline }
public fun contract_dispute_deadline(c: &CourierContract): u64 { c.dispute_deadline }
