# Plan 3: Application Layer (courier_market)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the courier_market module — P2P courier task marketplace with dual deposits, hot-potato delivery, confirmation period, dispute resolution, and timeout cleanup.

**Architecture:** Single module in the existing `astrologistics` package. Depends on `storage` (WithdrawAuth hot-potato), `threat_oracle` (issue ReporterCap via OracleCap), `fuel_station` (fee deduction). Uses `CourierContract` as Shared Object + `CourierBadge` as one-time Owned Object.

**Tech Stack:** Sui Move 2024 Edition, sui CLI 1.68.0, `sui move test`

**Spec:** `docs/superpowers/specs/2026-03-20-astrologistics-design.md` (section 2.5)

**Prerequisite:** Plan 1 + Plan 2 must be implemented and passing all tests.

---

## Review Fixes (2026-03-21)

> 以下修正來自四路審核（Architecture + Red Team + Security + Tester），實作時必須套用。

### Fix C3 (Critical): 修所有 use-after-delete
`claim_timeout` 所有分支 + `resolve_dispute` 中：
```move
// 修改前
object::delete(id);
event::emit(TimeoutClaimed { contract_id: object::uid_to_inner(&id), ... });
// 修改後
let contract_id = object::uid_to_inner(&id);
object::delete(id);
event::emit(TimeoutClaimed { contract_id, ... });
```

### Fix C4 (Critical): claim_timeout PENDING_CONFIRM 分支修 post-destructure 存取
```move
// destructure 時 bind reward 變數
let CourierContract {
    id, client, courier, from_storage: _, to_storage: _,
    cargo_receipt, reward, client_deposit, courier_deposit,  // ← bind reward
    min_courier_deposit: _, cargo_value: _, route: _, status: _,
    deadline: _, pickup_deadline: _, confirm_deadline: _, created_at: _,
} = contract;
// 後面用 reward 變數取代 contract.reward
let reward_payout = balance::split(&mut client_bal, reward);
```

### Fix H6 (High): 處理 withdraw_with_auth 回傳的 fee Coin
```move
// pickup_and_deliver 中
let (cargo, fee_coin) = storage::withdraw_with_auth(from_storage, receipt, auth, clock, ctx);
// fee 歸 client
transfer::public_transfer(fee_coin, contract.client);
```
注意：需要在 extract receipt 之前讀 `contract.client`。

### Fix H7 (High): pickup_deadline 封頂在 deadline
```move
// accept_contract 中
let raw_pickup = now + PICKUP_DEADLINE_MS;
contract.pickup_deadline = if (raw_pickup < contract.deadline) { raw_pickup } else { contract.deadline };
```

### Fix H8 (High): 防 ReporterCap farming
- `create_contract` 新增 `const MIN_CONTRACT_REWARD: u64 = 1000;`
- `assert!(coin::value(&reward) >= MIN_CONTRACT_REWARD, E_REWARD_TOO_LOW);`
- 經濟門檻讓 self-contracting spam 不划算

### Fix M6 (Medium): 移除 STATUS_IN_DELIVERY 死狀態
- 刪除 `const STATUS_IN_DELIVERY: u8 = 2;`
- 重新編號：PENDING_CONFIRM=2, DELIVERED=3, DISPUTED=4
- 刪除 `claim_timeout` 中的 STATUS_IN_DELIVERY 分支

### Fix M7 (Medium): Dispute 加 timeout
- CourierContract 新增 `dispute_deadline: u64` 欄位（初始 0）
- `raise_dispute` 設定 `contract.dispute_deadline = now + 72 * 3_600_000` (72小時)
- `claim_timeout` 新增 STATUS_DISPUTED 分支：超時自動判 courier 勝（auto-resolve ruling=1）

### Fix M8 (Medium): Cargo 搬運方案
使用 Plan 2 Fix H5 的 `storage::remove_cargo_for_transport`（`public(package)`）：
- `pickup_and_deliver` 改用 `remove_cargo_for_transport` 取 Cargo
- 然後用 `storage::deposit_cargo(to_storage, cargo, clock, ctx)` 存入目標
  - 或繼續用 `storage::deposit` 重建（但保留 value）
- 不需要額外的 `destroy_cargo` public 函式

### Fix Low: from_storage != to_storage 驗證
```move
// create_contract 中
const E_SAME_STORAGE: u64 = 9;
assert!(object::id(from_storage) != object::id(to_storage), E_SAME_STORAGE);
```

### Fix M10 (Medium): 補完測試 stub
- Task 2-7 的測試必須提供完整 test body（不能只寫 `// ...`）
- 實作時按 TDD 流程逐步補完

### Question Q3: Open timeout bounty = 0
- 確認刻意：Open 狀態沒有 courier deposit 可抽 bounty
- keeper 動機來自 gas refund 或 altruism

---

## File Structure

```
move/sources/
├── courier_market.move          # CourierContract, CourierBadge, full lifecycle
move/tests/
├── courier_market_tests.move
├── courier_market_monkey_tests.move
```

---

## Task 1: courier_market — Structs + create_contract

**Files:**
- Create: `move/sources/courier_market.move`
- Create: `move/tests/courier_market_tests.move`

- [ ] **Step 1: Write failing test**

```move
#[test_only]
module astrologistics::courier_market_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use astrologistics::storage::{Self, Storage, AdminCap, DepositReceipt};
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap};
use astrologistics::courier_market::{Self, CourierContract};

#[test]
fun test_create_contract() {
    let admin = @0xAD;
    let client = @0xC1;
    let mut scenario = test_scenario::begin(admin);

    // Setup: storage + threat map
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
        clock::destroy_for_testing(clock);
    };

    // Client deposits cargo
    scenario.next_tx(client);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 200, 8000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, client);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    // Client creates courier contract
    scenario.next_tx(client);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let cancel_penalty = coin::mint_for_testing<SUI>(2000, scenario.ctx());

        let contract_id = courier_market::create_contract(
            &s1,
            &s2,
            receipt,
            reward,
            cancel_penalty,
            8000,                  // min_courier_deposit (>= cargo.value)
            vector[1001, 2002],    // route
            86_400_000,            // deadline (1 day)
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };

    // Verify contract exists as shared object
    scenario.next_tx(client);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        assert!(courier_market::contract_status(&contract) == 0); // Open
        assert!(courier_market::contract_reward(&contract) == 5000);
        test_scenario::return_shared(contract);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter courier_market_tests`
Expected: FAIL

- [ ] **Step 3: Write courier_market module (structs + create_contract + getters)**

```move
module astrologistics::courier_market;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::clock::{Self, Clock};
use sui::event;
use astrologistics::storage::{Self, Storage, DepositReceipt, WithdrawAuth};
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap, ReporterCap};
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

// Status constants
const STATUS_OPEN: u8 = 0;
const STATUS_ACCEPTED: u8 = 1;
const STATUS_IN_DELIVERY: u8 = 2;
const STATUS_PENDING_CONFIRM: u8 = 3;
const STATUS_DELIVERED: u8 = 4;
const STATUS_DISPUTED: u8 = 5;

// Minimum deadline: 1 hour
const MIN_DEADLINE_MS: u64 = 3_600_000;
// Pickup sub-deadline: 2 hours
const PICKUP_DEADLINE_MS: u64 = 7_200_000;
// Confirm deadline: 24 hours
const CONFIRM_DEADLINE_MS: u64 = 86_400_000;

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
    created_at: u64,
}

public struct CourierBadge has key {
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
```

- [ ] **Step 4: Run tests**

Run: `cd move && sui move test --filter courier_market_tests`
Expected: PASS (1 test)

- [ ] **Step 5: Commit**

```bash
git add move/sources/courier_market.move move/tests/courier_market_tests.move
git commit -m "feat: courier_market structs + create_contract"
```

---

## Task 2: courier_market — accept_contract + cancel_by_client

- [ ] **Step 1: Write failing tests**

Add to `courier_market_tests.move`:

```move
#[test]
fun test_accept_contract() {
    // ... (setup similar to test_create_contract, then courier accepts)
    // Verify: status = Accepted, CourierBadge created, pickup_deadline set
}

#[test]
fun test_cancel_by_client_open() {
    // ... (setup, create contract, then client cancels)
    // Verify: receipt returned, deposit returned
}

#[test]
#[expected_failure(abort_code = courier_market::E_DEPOSIT_TOO_LOW)]
fun test_accept_deposit_too_low() {
    // ... (courier tries to accept with deposit < min_courier_deposit)
}
```

- [ ] **Step 2: Add accept_contract + cancel_by_client**

```move
/// Courier accepts the contract. Locks deposit, receives CourierBadge.
public fun accept_contract(
    contract: &mut CourierContract,
    deposit: Coin<SUI>,
    clock: &Clock,
    ctx: &mut TxContext,
): CourierBadge {
    assert!(contract.status == STATUS_OPEN, E_WRONG_STATUS);
    assert!(coin::value(&deposit) >= contract.min_courier_deposit, E_DEPOSIT_TOO_LOW);

    let now = clock::timestamp_ms(clock);
    contract.courier = option::some(ctx.sender());
    contract.status = STATUS_ACCEPTED;
    contract.pickup_deadline = now + PICKUP_DEADLINE_MS;
    balance::join(&mut contract.courier_deposit, coin::into_balance(deposit));

    let badge = CourierBadge {
        id: object::new(ctx),
        contract_id: object::id(contract),
        courier: ctx.sender(),
    };

    event::emit(ContractAccepted {
        contract_id: object::id(contract),
        courier: ctx.sender(),
        deposit_amount: coin::value(&deposit),
    });

    badge
}

/// Client cancels contract (only Open status).
public fun cancel_by_client(
    contract: CourierContract,
    ctx: &mut TxContext,
): (DepositReceipt, Coin<SUI>) {
    assert!(contract.status == STATUS_OPEN, E_WRONG_STATUS);
    assert!(contract.client == ctx.sender(), E_NOT_CLIENT);

    let CourierContract {
        id, client: _, courier: _, from_storage: _, to_storage: _,
        mut cargo_receipt, reward: _, client_deposit, courier_deposit,
        min_courier_deposit: _, cargo_value: _, route: _, status: _,
        deadline: _, pickup_deadline: _, confirm_deadline: _, created_at: _,
    } = contract;

    let receipt = option::extract(&mut cargo_receipt);
    option::destroy_none(cargo_receipt);
    let refund = coin::from_balance(client_deposit, ctx);
    balance::destroy_zero(courier_deposit);
    object::delete(id);

    (receipt, refund)
}
```

- [ ] **Step 3: Run tests** → PASS
- [ ] **Step 4: Commit**

---

## Task 3: courier_market — pickup_and_deliver (hot-potato)

- [ ] **Step 1: Write failing test**

```move
#[test]
fun test_pickup_and_deliver() {
    // Full flow: create contract → accept → pickup_and_deliver
    // Verify: cargo moved from storage1 to storage2, status = PendingConfirm
}
```

- [ ] **Step 2: Implement pickup_and_deliver**

```move
/// Courier picks up cargo and delivers to destination in one atomic PTB.
/// Uses WithdrawAuth hot-potato — courier never holds the DepositReceipt.
public fun pickup_and_deliver(
    contract: &mut CourierContract,
    badge: &CourierBadge,
    from_storage: &mut Storage,
    to_storage: &mut Storage,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(contract.status == STATUS_ACCEPTED, E_WRONG_STATUS);
    assert!(badge.contract_id == object::id(contract), E_BADGE_MISMATCH);
    assert!(badge.courier == ctx.sender(), E_NOT_COURIER);
    assert!(object::id(from_storage) == contract.from_storage, E_STORAGE_MISMATCH);
    assert!(object::id(to_storage) == contract.to_storage, E_STORAGE_MISMATCH);

    // Extract receipt from contract
    let receipt = option::extract(&mut contract.cargo_receipt);
    let cargo_id = storage::receipt_cargo_id(&receipt);

    // Create WithdrawAuth hot-potato
    let auth = storage::create_withdraw_auth(
        object::id(&receipt),
        object::id(contract),
    );

    // Withdraw from source (hot-potato consumed here)
    let (cargo, _fee) = storage::withdraw_with_auth(from_storage, receipt, auth, clock, ctx);

    // Deposit to destination
    let weight = storage::cargo_weight(&cargo);
    let value = storage::cargo_value(&cargo);
    // Transfer cargo object to destination storage
    let new_receipt = storage::deposit(
        to_storage,
        *storage::cargo_item_type(&cargo), // need getter
        weight,
        value,
        clock,
        ctx,
    );

    // Store new receipt back in contract for proof
    contract.cargo_receipt = option::some(new_receipt);

    // Destroy the original cargo (it's been re-deposited at destination)
    storage::destroy_cargo(cargo);

    let now = clock::timestamp_ms(clock);
    contract.status = STATUS_PENDING_CONFIRM;
    contract.confirm_deadline = now + CONFIRM_DEADLINE_MS;

    event::emit(CargoPickedUpAndDelivered {
        contract_id: object::id(contract),
        from_storage: contract.from_storage,
        to_storage: contract.to_storage,
    });
}
```

Note: Requires adding to `storage.move`:
- `public fun cargo_item_type(cargo: &Cargo): &vector<u8>`
- `public fun destroy_cargo(cargo: Cargo)` — test_only or public with restrictions

- [ ] **Step 3: Run tests** → PASS
- [ ] **Step 4: Commit**

---

## Task 4: courier_market — confirm_delivery + settle

- [ ] **Step 1: Write failing tests**
- [ ] **Step 2: Implement**

```move
/// Client confirms delivery. Transitions to Delivered.
public fun confirm_delivery(
    contract: &mut CourierContract,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(contract.status == STATUS_PENDING_CONFIRM, E_WRONG_STATUS);
    assert!(contract.client == ctx.sender(), E_NOT_CLIENT);
    contract.status = STATUS_DELIVERED;
    event::emit(DeliveryConfirmed { contract_id: object::id(contract) });
}

/// Settle the contract. Pays courier, returns deposits, issues ReporterCap.
public fun settle(
    contract: CourierContract,
    badge: CourierBadge,
    oracle_cap: &OracleCap,
    clock: &Clock,
    ctx: &mut TxContext,
): (Coin<SUI>, ReporterCap) {
    assert!(contract.status == STATUS_DELIVERED, E_WRONG_STATUS);
    assert!(badge.contract_id == object::id(&contract), E_BADGE_MISMATCH);

    let courier_addr = badge.courier;
    let CourierBadge { id: badge_id, contract_id: _, courier: _ } = badge;
    object::delete(badge_id);

    let CourierContract {
        id, client, courier: _, from_storage: _, to_storage: _,
        cargo_receipt, reward, client_deposit, courier_deposit,
        min_courier_deposit: _, cargo_value: _, route: _, status: _,
        deadline: _, pickup_deadline: _, confirm_deadline: _, created_at: _,
    } = contract;

    // Return remaining receipt to client (destination receipt)
    if (option::is_some(&cargo_receipt)) {
        let r = option::destroy_some(cargo_receipt);
        transfer::public_transfer(r, client);
    } else {
        option::destroy_none(cargo_receipt);
    };

    // Pay courier: reward from client_deposit
    let mut client_bal = client_deposit;
    let reward_payout = balance::split(&mut client_bal, reward);
    let courier_reward = coin::from_balance(reward_payout, ctx);

    // Return remaining client deposit to client
    if (balance::value(&client_bal) > 0) {
        transfer::public_transfer(coin::from_balance(client_bal, ctx), client);
    } else {
        balance::destroy_zero(client_bal);
    };

    // Return courier deposit
    transfer::public_transfer(coin::from_balance(courier_deposit, ctx), courier_addr);

    // Issue ReporterCap
    let reporter_cap = threat_oracle::issue_reporter_cap(oracle_cap, courier_addr, 1, ctx);

    let reporter_cap_id = object::id(&reporter_cap);
    event::emit(ContractSettled {
        contract_id: object::uid_to_inner(&id),
        courier_reward: reward,
        reporter_cap_id,
    });

    object::delete(id);
    (courier_reward, reporter_cap)
}
```

- [ ] **Step 3: Run tests** → PASS
- [ ] **Step 4: Commit**

---

## Task 5: courier_market — raise_dispute + resolve_dispute

- [ ] **Step 1: Write failing tests**
- [ ] **Step 2: Implement**

```move
/// Client raises dispute during PendingConfirm.
public fun raise_dispute(
    contract: &mut CourierContract,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(contract.status == STATUS_PENDING_CONFIRM, E_WRONG_STATUS);
    assert!(contract.client == ctx.sender(), E_NOT_CLIENT);
    contract.status = STATUS_DISPUTED;
    event::emit(DisputeRaised {
        contract_id: object::id(contract),
        client: ctx.sender(),
    });
}

/// OracleCap holder resolves dispute.
/// ruling: 0 = client wins, 1 = courier wins, 2 = split
public fun resolve_dispute(
    contract: CourierContract,
    badge: CourierBadge,
    _oracle_cap: &OracleCap,
    ruling: u8,
    ctx: &mut TxContext,
) {
    assert!(contract.status == STATUS_DISPUTED, E_WRONG_STATUS);

    let courier_addr = badge.courier;
    let CourierBadge { id: badge_id, contract_id: _, courier: _ } = badge;
    object::delete(badge_id);

    let CourierContract {
        id, client, courier: _, from_storage: _, to_storage: _,
        cargo_receipt, reward: _, client_deposit, courier_deposit,
        min_courier_deposit: _, cargo_value: _, route: _, status: _,
        deadline: _, pickup_deadline: _, confirm_deadline: _, created_at: _,
    } = contract;

    // Handle receipt
    if (option::is_some(&cargo_receipt)) {
        let r = option::destroy_some(cargo_receipt);
        if (ruling == 0) {
            transfer::public_transfer(r, client);
        } else {
            transfer::public_transfer(r, courier_addr);
        };
    } else {
        option::destroy_none(cargo_receipt);
    };

    if (ruling == 0) {
        // Client wins: client gets both deposits
        let mut all = client_deposit;
        balance::join(&mut all, courier_deposit);
        transfer::public_transfer(coin::from_balance(all, ctx), client);
    } else if (ruling == 1) {
        // Courier wins: normal settlement
        transfer::public_transfer(coin::from_balance(client_deposit, ctx), courier_addr);
        transfer::public_transfer(coin::from_balance(courier_deposit, ctx), courier_addr);
    } else {
        // Split: each gets their own deposit back
        transfer::public_transfer(coin::from_balance(client_deposit, ctx), client);
        transfer::public_transfer(coin::from_balance(courier_deposit, ctx), courier_addr);
    };

    event::emit(DisputeResolved { contract_id: object::uid_to_inner(&id), ruling });
    object::delete(id);
}
```

- [ ] **Step 3: Run tests** → PASS
- [ ] **Step 4: Commit**

---

## Task 6: courier_market — claim_timeout (all stages)

- [ ] **Step 1: Write failing tests**

```move
#[test]
fun test_timeout_open() { /* Open past deadline → client gets full refund + receipt */ }

#[test]
fun test_timeout_accepted_no_pickup() { /* Accepted past pickup_deadline → courier deposit → client */ }

#[test]
fun test_timeout_pending_confirm() { /* PendingConfirm past confirm_deadline → auto-confirm */ }
```

- [ ] **Step 2: Implement claim_timeout**

```move
/// Permissionless timeout claim. Returns keeper bounty (0.5% of forfeited deposit).
public fun claim_timeout(
    contract: CourierContract,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<SUI> {
    let now = clock::timestamp_ms(clock);
    let keeper = ctx.sender();
    let status = contract.status;

    let CourierContract {
        id, client, courier, from_storage: _, to_storage: _,
        cargo_receipt, reward: _, client_deposit, courier_deposit,
        min_courier_deposit: _, cargo_value: _, route: _, status: _,
        deadline, pickup_deadline, confirm_deadline, created_at: _,
    } = contract;

    // Handle receipt
    let receipt_opt = cargo_receipt;

    if (status == STATUS_OPEN) {
        // Open timeout: client gets everything back
        assert!(now >= deadline, E_NOT_TIMED_OUT);
        if (option::is_some(&receipt_opt)) {
            transfer::public_transfer(option::destroy_some(receipt_opt), client);
        } else { option::destroy_none(receipt_opt); };
        transfer::public_transfer(coin::from_balance(client_deposit, ctx), client);
        balance::destroy_zero(courier_deposit);
        object::delete(id);
        event::emit(TimeoutClaimed { contract_id: object::uid_to_inner(&id), stage: status, keeper, bounty: 0 });
        return coin::zero(ctx)

    } else if (status == STATUS_ACCEPTED) {
        // Accepted timeout (no pickup): courier deposit → client
        assert!(now >= pickup_deadline, E_NOT_TIMED_OUT);
        if (option::is_some(&receipt_opt)) {
            transfer::public_transfer(option::destroy_some(receipt_opt), client);
        } else { option::destroy_none(receipt_opt); };

        let courier_val = balance::value(&courier_deposit);
        let bounty_amount = courier_val * constants::keeper_bounty_bps() / constants::bps_scale();
        let bounty = balance::split(&mut courier_deposit, bounty_amount);
        let mut all_to_client = client_deposit;
        balance::join(&mut all_to_client, courier_deposit);
        transfer::public_transfer(coin::from_balance(all_to_client, ctx), client);
        object::delete(id);
        event::emit(TimeoutClaimed { contract_id: object::uid_to_inner(&id), stage: status, keeper, bounty: bounty_amount });
        return coin::from_balance(bounty, ctx)

    } else if (status == STATUS_IN_DELIVERY) {
        // InDelivery timeout: courier deposit → client
        assert!(now >= deadline, E_NOT_TIMED_OUT);
        if (option::is_some(&receipt_opt)) {
            transfer::public_transfer(option::destroy_some(receipt_opt), client);
        } else { option::destroy_none(receipt_opt); };

        let courier_val = balance::value(&courier_deposit);
        let bounty_amount = courier_val * constants::keeper_bounty_bps() / constants::bps_scale();
        let bounty = balance::split(&mut courier_deposit, bounty_amount);
        let mut all_to_client = client_deposit;
        balance::join(&mut all_to_client, courier_deposit);
        transfer::public_transfer(coin::from_balance(all_to_client, ctx), client);
        object::delete(id);
        event::emit(TimeoutClaimed { contract_id: object::uid_to_inner(&id), stage: status, keeper, bounty: bounty_amount });
        return coin::from_balance(bounty, ctx)

    } else if (status == STATUS_PENDING_CONFIRM) {
        // PendingConfirm timeout: auto-confirm (courier wins)
        assert!(now >= confirm_deadline, E_NOT_TIMED_OUT);
        let courier_addr = option::destroy_some(courier);
        if (option::is_some(&receipt_opt)) {
            transfer::public_transfer(option::destroy_some(receipt_opt), client);
        } else { option::destroy_none(receipt_opt); };

        // Normal settlement: reward → courier, deposits returned
        let mut client_bal = client_deposit;
        let reward_payout = balance::split(&mut client_bal, contract.reward);
        transfer::public_transfer(coin::from_balance(reward_payout, ctx), courier_addr);
        if (balance::value(&client_bal) > 0) {
            transfer::public_transfer(coin::from_balance(client_bal, ctx), client);
        } else {
            balance::destroy_zero(client_bal);
        };
        transfer::public_transfer(coin::from_balance(courier_deposit, ctx), courier_addr);
        object::delete(id);
        event::emit(TimeoutClaimed { contract_id: object::uid_to_inner(&id), stage: status, keeper, bounty: 0 });
        return coin::zero(ctx)

    } else {
        abort E_WRONG_STATUS
    }
}
```

- [ ] **Step 3: Run tests** → PASS
- [ ] **Step 4: Commit**

---

## Task 7: Monkey Tests — courier_market Edge Cases

**Files:**
- Create: `move/tests/courier_market_monkey_tests.move`

- [ ] **Step 1: Write monkey tests**

```move
#[test_only]
module astrologistics::courier_market_monkey_tests;

// Test cases:
// 1. Courier deposit exactly at minimum (boundary)
// 2. Deadline = minimum (1 hour)
// 3. Cancel after accept (should fail — wrong status)
// 4. Double accept (should fail — wrong status)
// 5. Pickup after pickup_deadline expired (should fail via claim_timeout)
// 6. Confirm by non-client (should fail)
// 7. Settle without confirming (should fail — wrong status)
// 8. claim_timeout before deadline (should fail)
```

- [ ] **Step 2: Run all tests**

Run: `cd move && sui move test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add move/tests/courier_market_monkey_tests.move
git commit -m "test: courier_market monkey tests"
```

---

## Task 8: Full Build + All Tests

- [ ] **Step 1: Clean build**

Run: `cd move && sui move build`
Expected: Build Successful

- [ ] **Step 2: Run ALL tests**

Run: `cd move && sui move test`
Expected: ALL PASS (40+ tests across 6 modules)

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "feat: Plan 3 complete — courier_market with dual deposits, hot-potato, disputes"
```

---

## Summary

| Module | Tests | Key Patterns |
|--------|-------|-------------|
| `courier_market` | 12+ tests | Shared Object lifecycle, dual deposits (costly signaling), WithdrawAuth hot-potato, PendingConfirm + dispute, permissionless timeout with keeper bounty, ReporterCap issuance via OracleCap |

**After all 3 plans are complete:** 6 modules, 40+ tests, ready for devnet deployment.
