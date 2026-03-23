# Plan 2: Logistics + Economy Layer (transport + fuel_station)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the transport module (tiered cross-galaxy transfer) and fuel_station module (AMM pricing + supplier revenue sharing), forming the economic backbone of AstroLogistics.

**Architecture:** Two modules in the existing `astrologistics` package. `transport` depends on `storage`, `threat_oracle`, `fuel_token`. `fuel_station` depends on `storage`, `fuel_token`. Both use Plan 1's foundation layer.

**Tech Stack:** Sui Move 2024 Edition, sui CLI 1.68.0, `sui move test`

**Spec:** `docs/superpowers/specs/2026-03-20-astrologistics-design.md` (sections 2.3 and 2.4)

**Prerequisite:** Plan 1 (foundation layer) must be implemented and passing all tests.

---

## Review Fixes (2026-03-21)

> 以下修正來自四路審核（Architecture + Developer + Red Team + Tester），實作時必須套用。

### Fix C2 (Critical): fuel_station 用 Balance\<FUEL\> 取代 burn_for_testing
- FuelStation 新增 `fuel_reserve: Balance<FUEL>` 欄位
- `supply_fuel` / `add_supply`：`balance::join(&mut station.fuel_reserve, coin::into_balance(fuel))` 取代 `coin::burn_for_testing(fuel)`
- `buy_fuel`：`coin::from_balance(balance::split(&mut station.fuel_reserve, amount), ctx)` 取代 `fuel_token::mint`
  - **移除 `treasury: &mut FuelTreasuryCap` 參數**
- `withdraw_supplier`：`coin::from_balance(balance::split(&mut station.fuel_reserve, fuel_share), ctx)` 取代 `fuel_token::mint`
  - **移除 `treasury: &mut FuelTreasuryCap` 參數**

### Fix H3 (High): accumulator 用 u128 防溢位
```move
// buy_fuel 中
station.acc_reward_per_share = station.acc_reward_per_share +
    (((supplier_pool as u128) * (fp as u128) / (station.total_supplied as u128)) as u64);

// claim_revenue 中
let pending = (((receipt.supply_record.amount as u128) *
    ((station.acc_reward_per_share - receipt.supply_record.reward_debt) as u128)) / (fp as u128)) as u64;
```

### Fix H4 (High): alpha 加上限
```move
// constants.move 新增
public fun max_alpha(): u64 { 10_000 }  // 10x in FP_SCALE

// create_station + update_pricing 中加入
const E_ALPHA_TOO_HIGH: u64 = 7;
assert!(alpha <= constants::max_alpha(), E_ALPHA_TOO_HIGH);
```

### Fix H5 (High): complete_transport 必須清理 from_storage
- `complete_transport` 新增 `from_storage: &mut Storage` 參數
- 新增 `storage::remove_cargo_for_transport(storage, receipt): Cargo`（`public(package)`）
  - 移除 ObjectBag 中的 Cargo + 清 live_receipts + 減 current_load
  - 回傳 Cargo 物件供目標 storage deposit
- 新 cargo 在 to_storage 保留原 value（不是 0）
- 消除 `consume_receipt_for_transport` — 改用 `remove_cargo_for_transport`

### Fix M3 (Medium): pay_fuel 只燒精確數量
```move
public fun pay_fuel(order: &mut TransportOrder, mut fuel: Coin<FUEL>, treasury: &mut FuelTreasuryCap) {
    assert!(order.status == 0, E_WRONG_STATUS);
    assert!(coin::value(&fuel) >= order.fuel_cost, E_FUEL_COST_TOO_LOW);
    let exact = coin::split(&mut fuel, order.fuel_cost, ctx);  // 需要 ctx
    fuel_token::burn(treasury, exact);
    // 退回多餘
    if (coin::value(&fuel) > 0) {
        transfer::public_transfer(fuel, ctx.sender());
    } else {
        coin::destroy_zero(fuel);
    };
    order.status = 1;
}
```
注意：`pay_fuel` 需要新增 `ctx: &mut TxContext` 參數。

### Fix M4 (Medium): claim_revenue 加前置檢查
```move
let pool_balance = balance::value(&station.revenue_pool);
let actual_payout = if (pending > pool_balance) { pool_balance } else { pending };
```

### Fix M5 (Low→Medium): complete_transport 保留原 cargo value
- 使用 Fix H5 的 `remove_cargo_for_transport` 取得原 Cargo，讀取其 value
- `storage::deposit(to_storage, cargo.item_type, cargo.weight, cargo.value, clock, ctx)`

### Fix Low: cancel_order 修 use-after-move
```move
// 修改前
object::delete(id);
event::emit(TransportCancelled { order_id: id.to_inner() });
// 修改後
let order_id = object::uid_to_inner(&id);
object::delete(id);
event::emit(TransportCancelled { order_id });
```

### Fix M9 (Medium): 補缺測試
1. `test_cancel_after_pay` → `#[expected_failure(abort_code = transport::E_WRONG_STATUS)]`
2. AMM boundary tests: empty station price, buy-last-unit, zero-claim
3. `test_add_supply_with_pending_rewards` — 驗證 auto-flush 正確
4. Scarce threshold test — supply below 30% 驗證 1.5× bonus

### Question Q2: transport 不直接使用 threat_oracle
- 確認：`danger_snapshot` 純粹由鏈下傳入，鏈上不做 oracle call
- spec 依賴圖中的 `transport → threat_oracle` 移除

---

## File Structure

```
move/sources/
├── transport.move          # TransportOrder, tiered transfer, fuel payment
├── fuel_station.move       # FuelStation, AMM pricing, supplier revenue
move/tests/
├── transport_tests.move
├── transport_monkey_tests.move
├── fuel_station_tests.move
├── fuel_station_monkey_tests.move
```

---

## Task 1: transport Module — Structs + create_order

**Files:**
- Create: `move/sources/transport.move`
- Create: `move/tests/transport_tests.move`

- [ ] **Step 1: Write failing test for create_order**

```move
#[test_only]
module astrologistics::transport_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, AdminCap, DepositReceipt};
use astrologistics::transport::{Self, TransportOrder};

#[test]
fun test_create_order_instant() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);

    // Setup: create two storages
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo in storage 1
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 500, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    // Create transport order (Instant tier)
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let order = transport::create_order(
            &s1,
            &s2,
            receipt,
            vector[1001, 1500, 2002],  // route
            15000,                      // fuel_cost (within min/max bounds for weight 500)
            800,                        // danger_snapshot
            0,                          // tier: Instant
            &clock,
            scenario.ctx(),
        );

        assert!(transport::order_tier(&order) == 0);
        assert!(transport::order_fuel_cost(&order) == 15000);
        assert!(transport::order_status(&order) == 0); // Created
        // Instant tier: earliest_complete_at = created_at (no delay)
        assert!(transport::order_earliest_complete_at(&order) == 1000);

        transfer::transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_create_order_standard_has_delay() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 5000);

        let order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002],
            5000,   // fuel_cost
            500,    // danger
            2,      // tier: Standard
            &clock,
            scenario.ctx(),
        );

        // Standard tier: earliest_complete_at = 5000 + 900_000 = 905_000
        assert!(transport::order_earliest_complete_at(&order) == 905_000);
        transfer::transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter transport_tests`
Expected: FAIL (module not found)

- [ ] **Step 3: Write transport module (structs + create_order + getters)**

```move
module astrologistics::transport;

use sui::clock::{Self, Clock};
use sui::event;
use astrologistics::storage::{Self, Storage, DepositReceipt};
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

public struct TransportOrder has key {
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
/// fuel_cost is validated against min/max bounds.
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

    // Read cargo weight from storage before locking receipt
    let cargo_id = storage::receipt_cargo_id(&receipt);
    let weight = storage::cargo_weight_by_id(from_storage, cargo_id);

    // Validate fuel_cost bounds
    let min_cost = constants::min_fuel_cost_per_weight() * weight;
    let max_cost = constants::max_fuel_cost_per_weight() * weight;
    assert!(fuel_cost >= min_cost, E_FUEL_COST_TOO_LOW);
    assert!(fuel_cost <= max_cost, E_FUEL_COST_TOO_HIGH);

    let now = clock::timestamp_ms(clock);
    let delay = tier_delay(tier);

    let order = TransportOrder {
        id: object::new(ctx),
        sender: ctx.sender(),
        from_storage: object::id(from_storage),
        to_storage: object::id(to_storage),
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
        from_storage: object::id(from_storage),
        to_storage: object::id(to_storage),
        tier,
        fuel_cost,
    });

    order
}

// ============ Getters ============

public fun order_tier(order: &TransportOrder): u8 { order.tier }
public fun order_fuel_cost(order: &TransportOrder): u64 { order.fuel_cost }
public fun order_status(order: &TransportOrder): u8 { order.status }
public fun order_earliest_complete_at(order: &TransportOrder): u64 { order.earliest_complete_at }
public fun order_sender(order: &TransportOrder): address { order.sender }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd move && sui move test --filter transport_tests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/transport.move move/tests/transport_tests.move
git commit -m "feat: transport module create_order with tier system"
```

---

## Task 2: transport — pay_fuel + complete_transport + cancel_order

**Files:**
- Modify: `move/sources/transport.move`
- Modify: `move/tests/transport_tests.move`

- [ ] **Step 1: Write failing tests**

Add to `transport_tests.move`:

```move
use sui::coin;
use astrologistics::fuel_token::{Self, FUEL, FuelTreasuryCap};

#[test]
fun test_full_transport_lifecycle_instant() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);

    // Setup storages + fuel treasury
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    // Create order + pay fuel + complete (Instant = no delay)
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let mut order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 0, // tier=Instant
            &clock, scenario.ctx(),
        );

        // Pay fuel
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel_token::mint(&mut treasury, 5000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury);
        assert!(transport::order_status(&order) == 1); // FuelPaid

        // Complete immediately (Instant tier, no delay)
        let new_receipt = transport::complete_transport(
            order, &mut s2, &clock, scenario.ctx(),
        );

        // Verify: cargo deposited in s2
        assert!(storage::available_capacity(&s2) < 10000);

        transfer::public_transfer(new_receipt, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = transport::E_TOO_EARLY)]
fun test_complete_before_delay_fails() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let mut s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        let mut order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 2, // tier=Standard (15min delay)
            &clock, scenario.ctx(),
        );

        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel_token::mint(&mut treasury, 5000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury);

        // Try complete at t=2000 (too early, need t=901_000)
        clock::set_for_testing(&mut clock, 2000);
        let new_receipt = transport::complete_transport(order, &mut s2, &clock, scenario.ctx());

        transfer::public_transfer(new_receipt, user);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_cancel_order_before_payment() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin);
        transfer::public_transfer(cap2, admin);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());

        let order = transport::create_order(
            &s1, &s2, receipt,
            vector[1001, 2002], 5000, 0, 0,
            &clock, scenario.ctx(),
        );

        // Cancel before paying fuel
        let returned_receipt = transport::cancel_order(order, scenario.ctx());
        transfer::public_transfer(returned_receipt, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd move && sui move test --filter transport_tests`
Expected: FAIL (pay_fuel / complete_transport / cancel_order not found)

- [ ] **Step 3: Add pay_fuel, complete_transport, cancel_order**

Add to `transport.move`:

```move
use sui::coin::{Self, Coin};
use astrologistics::fuel_token::{Self, FUEL, FuelTreasuryCap};

/// Pay fuel for the transport order. Burns FUEL tokens.
public fun pay_fuel(
    order: &mut TransportOrder,
    fuel: Coin<FUEL>,
    treasury: &mut FuelTreasuryCap,
) {
    assert!(order.status == 0, E_WRONG_STATUS);
    assert!(coin::value(&fuel) >= order.fuel_cost, E_FUEL_COST_TOO_LOW);

    fuel_token::burn(treasury, fuel);
    order.status = 1;

    event::emit(TransportPaid {
        order_id: object::id(order),
        fuel_amount: order.fuel_cost,
    });
}

/// Complete the transport. Withdraws cargo from source, deposits at destination.
/// Returns new DepositReceipt at destination.
public fun complete_transport(
    mut order: TransportOrder,
    to_storage: &mut Storage,
    clock: &Clock,
    ctx: &mut TxContext,
): DepositReceipt {
    assert!(order.status == 1, E_WRONG_STATUS);
    assert!(object::id(to_storage) == order.to_storage, E_STORAGE_MISMATCH);

    let now = clock::timestamp_ms(clock);
    assert!(now >= order.earliest_complete_at, E_TOO_EARLY);

    // Extract receipt from order
    let receipt = option::extract(&mut order.receipt);

    // Deposit at destination using the receipt's cargo info
    // Note: the cargo is still in from_storage's ObjectBag.
    // In a real implementation, we'd need to withdraw from source and deposit to dest.
    // For the transport module, we create a new receipt at the destination.
    // The source cargo is conceptually "teleported" — the receipt is the proof.
    let cargo_id = storage::receipt_cargo_id(&receipt);
    let weight = order.cargo_weight;

    // Create new deposit at destination
    let new_receipt = storage::deposit(
        to_storage,
        b"transported",
        weight,
        0, // value is preserved from original cargo
        clock,
        ctx,
    );

    let new_receipt_id = object::id(&new_receipt);

    // Destroy the old receipt (source claim is gone)
    storage::consume_receipt_for_transport(receipt);

    event::emit(TransportCompleted {
        order_id: object::id(&order),
        new_receipt_id,
    });

    // Destroy order
    let TransportOrder {
        id, sender: _, from_storage: _, to_storage: _, receipt: remaining,
        cargo_weight: _, route: _, fuel_cost: _, danger_snapshot: _,
        tier: _, earliest_complete_at: _, status: _, created_at: _,
    } = order;
    option::destroy_none(remaining);
    object::delete(id);

    new_receipt
}

/// Cancel order before fuel payment. Returns receipt.
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
    object::delete(id);

    event::emit(TransportCancelled { order_id: id.to_inner() });

    returned_receipt
}
```

Note: This requires adding a `consume_receipt_for_transport` helper to `storage.move`:

```move
/// Consume a receipt without withdrawing cargo (for transport teleportation).
/// Removes the live_receipt tracking.
public fun consume_receipt_for_transport(receipt: DepositReceipt) {
    let DepositReceipt { id, storage_id: _, cargo_id: _, depositor: _ } = receipt;
    // Note: live_receipts removal must happen via the Storage object.
    // For transport, the source storage's cargo is abandoned (teleported away).
    // The admin_reclaim mechanism handles cleanup of the source cargo.
    object::delete(id);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd move && sui move test --filter transport_tests`
Expected: PASS (5 tests total)

- [ ] **Step 5: Commit**

```bash
git add move/sources/transport.move move/sources/storage.move move/tests/transport_tests.move
git commit -m "feat: transport pay_fuel + complete_transport + cancel_order"
```

---

## Task 3: fuel_station Module — Core Structs + create_station + current_price

**Files:**
- Create: `move/sources/fuel_station.move`
- Create: `move/tests/fuel_station_tests.move`

- [ ] **Step 1: Write failing test**

```move
#[test_only]
module astrologistics::fuel_station_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use astrologistics::storage::{Self, Storage};
use astrologistics::fuel_token::{Self, FUEL, FuelTreasuryCap};
use astrologistics::fuel_station::{Self, FuelStation, StationCap};

#[test]
fun test_create_station() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    // Setup storage
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(
            &s,
            100,    // base_price
            500,    // alpha (0.5 in FP_SCALE)
            1000,   // owner_fee_bps (10%)
            scenario.ctx(),
        );
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    scenario.next_tx(admin);
    {
        let station = test_scenario::take_shared<FuelStation>(&scenario);
        // Full fuel: price = base_price * (1 + alpha * 0) = 100
        assert!(fuel_station::current_price(&station) == 100);
        let (current, max) = fuel_station::fuel_level(&station);
        assert!(current == 0 && max == 0); // no fuel supplied yet
        test_scenario::return_shared(station);
    };
    scenario.end();
}

#[test]
#[expected_failure]
fun test_create_station_fee_too_high() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        // 6000 > MAX_OWNER_FEE_BPS (5000) — should fail
        let station_cap = fuel_station::create_station(&s, 100, 500, 6000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter fuel_station_tests`
Expected: FAIL

- [ ] **Step 3: Write fuel_station module (core structs + create_station + pricing)**

```move
module astrologistics::fuel_station;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::sui::SUI;
use sui::event;
use astrologistics::storage::{Self, Storage};
use astrologistics::fuel_token::{Self, FUEL, FuelTreasuryCap};
use astrologistics::constants;

// ============ Error codes ============
const E_FEE_TOO_HIGH: u64 = 0;
const E_CAP_MISMATCH: u64 = 1;
const E_INSUFFICIENT_FUEL: u64 = 2;
const E_PRICE_EXCEEDS_MAX: u64 = 3;
const E_RECEIPT_MISMATCH: u64 = 4;
const E_NO_FUEL_SUPPLIED: u64 = 5;
const E_INSUFFICIENT_PAYMENT: u64 = 6;

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
    total_supplied: u64,
    acc_reward_per_share: u64,        // O(1) accumulator (FP_SCALE)
    revenue_pool: Balance<SUI>,       // collected SUI from fuel sales
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

public fun create_station(
    storage: &Storage,
    base_price: u64,
    alpha: u64,
    owner_fee_bps: u64,
    ctx: &mut TxContext,
): StationCap {
    assert!(owner_fee_bps <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);

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

/// AMM pricing: price = base_price * (FP + alpha * (FP - current * FP / max)) / FP
/// When no fuel supplied (max=0), price = base_price * (1 + alpha) (max scarcity)
public fun current_price(station: &FuelStation): u64 {
    let fp = constants::fp_scale();
    if (station.max_fuel == 0) {
        return station.base_price * (fp + station.alpha) / fp
    };
    let fill_ratio = station.current_fuel * fp / station.max_fuel;
    let scarcity = fp - fill_ratio;
    station.base_price * (fp + station.alpha * scarcity / fp) / fp
}

public fun fuel_level(station: &FuelStation): (u64, u64) {
    (station.current_fuel, station.max_fuel)
}

public fun station_id_from_cap(cap: &StationCap): ID { cap.station_id }
```

- [ ] **Step 4: Run tests**

Run: `cd move && sui move test --filter fuel_station_tests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/fuel_station.move move/tests/fuel_station_tests.move
git commit -m "feat: fuel_station core structs + create_station + AMM pricing"
```

---

## Task 4: fuel_station — supply_fuel + buy_fuel + claim_revenue

**Files:**
- Modify: `move/sources/fuel_station.move`
- Modify: `move/tests/fuel_station_tests.move`

- [ ] **Step 1: Write failing tests**

Add to `fuel_station_tests.move`:

```move
#[test]
fun test_supply_and_buy_fuel() {
    let admin = @0xAD;
    let supplier = @0xS1;
    let buyer = @0xB1;
    let mut scenario = test_scenario::begin(admin);

    // Setup
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    // Supplier adds fuel
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel_token::mint(&mut treasury, 10000, scenario.ctx());

        let receipt = fuel_station::supply_fuel(&mut station, fuel, scenario.ctx());

        let (current, max) = fuel_station::fuel_level(&station);
        assert!(current == 10000 && max == 10000);

        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };

    // Buyer buys fuel
    scenario.next_tx(buyer);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let price = fuel_station::current_price(&station);

        // Buy 100 units of fuel
        let payment = coin::mint_for_testing<SUI>(price * 100, scenario.ctx());
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);

        let fuel_out = fuel_station::buy_fuel(
            &mut station, payment, 100, price + 10, &mut treasury, scenario.ctx(),
        );

        assert!(coin::value(&fuel_out) == 100);
        let (current, _) = fuel_station::fuel_level(&station);
        assert!(current == 9900);

        coin::burn_for_testing(fuel_out);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };

    // Supplier claims revenue
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut receipt = test_scenario::take_from_sender<fuel_station::SupplierReceipt>(&scenario);

        let revenue = fuel_station::claim_revenue(&mut station, &mut receipt, scenario.ctx());
        assert!(coin::value(&revenue) > 0);

        coin::burn_for_testing(revenue);
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_shared(station);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter fuel_station_tests`
Expected: FAIL

- [ ] **Step 3: Add supply_fuel, buy_fuel, claim_revenue**

Add to `fuel_station.move`:

```move
/// Supply fuel to the station. Returns SupplierReceipt.
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

    // Burn the FUEL coin (it's now in the station's inventory)
    // Actually, we need to track fuel in the station, not burn it.
    // Use balance to store it.
    // For simplicity: we track fuel as u64 counters, and burn the coin.
    // When buyers buy, we mint new FUEL for them.
    coin::burn_for_testing(fuel); // TODO: proper FUEL accounting

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

/// Buy fuel from the station. Pays SUI, receives FUEL.
public fun buy_fuel(
    station: &mut FuelStation,
    mut payment: Coin<SUI>,
    amount: u64,
    max_price_per_unit: u64,
    treasury: &mut FuelTreasuryCap,
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

    // Update accumulator (O(1))
    if (station.total_supplied > 0) {
        let fp = constants::fp_scale();
        station.acc_reward_per_share = station.acc_reward_per_share +
            supplier_pool * fp / station.total_supplied;
    };

    // Add revenue to pool
    balance::join(&mut station.revenue_pool, coin::into_balance(paid));

    // Mint FUEL for buyer
    let fuel_out = fuel_token::mint(treasury, amount, ctx);

    event::emit(FuelPurchased {
        station_id: object::id(station),
        buyer: ctx.sender(),
        amount,
        price_paid: total_cost,
    });

    fuel_out
}

/// Claim accumulated revenue from the station.
public fun claim_revenue(
    station: &mut FuelStation,
    receipt: &mut SupplierReceipt,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(receipt.station_id == object::id(station), E_RECEIPT_MISMATCH);

    let fp = constants::fp_scale();
    let pending = receipt.supply_record.amount *
        (station.acc_reward_per_share - receipt.supply_record.reward_debt) / fp;

    // Update reward debt
    receipt.supply_record.reward_debt = station.acc_reward_per_share;

    // Pay out from revenue pool
    let payout = balance::split(&mut station.revenue_pool, pending);
    let payout_coin = coin::from_balance(payout, ctx);

    event::emit(RevenueClaimed {
        station_id: object::id(station),
        supplier: ctx.sender(),
        amount: pending,
    });

    payout_coin
}
```

- [ ] **Step 4: Run tests**

Run: `cd move && sui move test --filter fuel_station_tests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/fuel_station.move move/tests/fuel_station_tests.move
git commit -m "feat: fuel_station supply + buy + claim with O(1) accumulator"
```

---

## Task 5: fuel_station — add_supply + withdraw_supplier + update_pricing + update_fee

**Files:**
- Modify: `move/sources/fuel_station.move`
- Modify: `move/tests/fuel_station_tests.move`

- [ ] **Step 1: Write failing tests**

Add to `fuel_station_tests.move`:

```move
#[test]
fun test_withdraw_supplier() {
    let admin = @0xAD;
    let supplier = @0xS1;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    // Supply fuel
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel_token::mint(&mut treasury, 5000, scenario.ctx());
        let receipt = fuel_station::supply_fuel(&mut station, fuel, scenario.ctx());
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };

    // Withdraw supplier (exit)
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let receipt = test_scenario::take_from_sender<fuel_station::SupplierReceipt>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);

        let (revenue, fuel_back) = fuel_station::withdraw_supplier(
            &mut station, receipt, &mut treasury, scenario.ctx(),
        );

        // Should get back fuel (no sales happened, so revenue = 0)
        assert!(coin::value(&revenue) == 0);
        assert!(coin::value(&fuel_back) > 0);

        coin::burn_for_testing(revenue);
        coin::burn_for_testing(fuel_back);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };
    scenario.end();
}

#[test]
fun test_update_pricing() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let cap = test_scenario::take_from_sender<StationCap>(&scenario);

        fuel_station::update_pricing(&mut station, &cap, 200, 800);
        assert!(fuel_station::current_price(&station) == 200 * (1000 + 800) / 1000);

        fuel_station::update_fee(&mut station, &cap, 2000);
        // Should pass (2000 <= 5000)

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(station);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter fuel_station_tests`
Expected: FAIL

- [ ] **Step 3: Add remaining functions**

Add to `fuel_station.move`:

```move
/// Add more fuel to an existing SupplierReceipt
public fun add_supply(
    station: &mut FuelStation,
    receipt: &mut SupplierReceipt,
    fuel: Coin<FUEL>,
    ctx: &mut TxContext,
) {
    assert!(receipt.station_id == object::id(station), E_RECEIPT_MISMATCH);

    // Claim pending rewards first (to avoid losing them)
    let fp = constants::fp_scale();
    let pending = receipt.supply_record.amount *
        (station.acc_reward_per_share - receipt.supply_record.reward_debt) / fp;

    if (pending > 0) {
        let payout = balance::split(&mut station.revenue_pool, pending);
        transfer::public_transfer(coin::from_balance(payout, ctx), ctx.sender());
    };

    let amount = coin::value(&fuel);
    let is_scarce = station.max_fuel > 0 &&
        station.current_fuel * fp < station.max_fuel * constants::scarce_threshold();
    let effective_amount = if (is_scarce) {
        amount * constants::scarce_bonus() / fp
    } else {
        amount
    };

    station.current_fuel = station.current_fuel + amount;
    station.max_fuel = station.max_fuel + amount;
    station.total_supplied = station.total_supplied + effective_amount;

    receipt.supply_record.amount = receipt.supply_record.amount + effective_amount;
    receipt.supply_record.reward_debt = station.acc_reward_per_share;

    coin::burn_for_testing(fuel);

    event::emit(FuelSupplied {
        station_id: object::id(station),
        supplier: ctx.sender(),
        amount,
        is_scarce,
    });
}

/// Supplier exits: claims pending revenue + proportional fuel return
public fun withdraw_supplier(
    station: &mut FuelStation,
    receipt: SupplierReceipt,
    treasury: &mut FuelTreasuryCap,
    ctx: &mut TxContext,
): (Coin<SUI>, Coin<FUEL>) {
    assert!(receipt.station_id == object::id(station), E_RECEIPT_MISMATCH);

    let fp = constants::fp_scale();

    // Calculate pending revenue
    let pending = receipt.supply_record.amount *
        (station.acc_reward_per_share - receipt.supply_record.reward_debt) / fp;

    let revenue_coin = if (pending > 0 && balance::value(&station.revenue_pool) >= pending) {
        let payout = balance::split(&mut station.revenue_pool, pending);
        coin::from_balance(payout, ctx)
    } else {
        coin::zero<SUI>(ctx)
    };

    // Calculate proportional fuel to return
    let fuel_share = if (station.total_supplied > 0) {
        station.current_fuel * receipt.supply_record.amount / station.total_supplied
    } else {
        0
    };

    // Update station state
    station.current_fuel = station.current_fuel - fuel_share;
    station.total_supplied = station.total_supplied - receipt.supply_record.amount;

    // Mint FUEL to return
    let fuel_coin = fuel_token::mint(treasury, fuel_share, ctx);

    let receipt_id = object::id(&receipt);
    event::emit(SupplierWithdrawn {
        station_id: object::id(station),
        receipt_id,
        fuel_returned: fuel_share,
        revenue_claimed: pending,
    });

    // Destroy receipt
    let SupplierReceipt { id, station_id: _, supply_record: _ } = receipt;
    object::delete(id);

    (revenue_coin, fuel_coin)
}

/// Update pricing parameters (station owner only)
public fun update_pricing(station: &mut FuelStation, cap: &StationCap, base_price: u64, alpha: u64) {
    assert!(cap.station_id == object::id(station), E_CAP_MISMATCH);
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
```

- [ ] **Step 4: Run tests**

Run: `cd move && sui move test --filter fuel_station_tests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/fuel_station.move move/tests/fuel_station_tests.move
git commit -m "feat: fuel_station add_supply + withdraw_supplier + update_pricing"
```

---

## Task 6: Monkey Tests — transport + fuel_station Edge Cases

**Files:**
- Create: `move/tests/transport_monkey_tests.move`
- Create: `move/tests/fuel_station_monkey_tests.move`

- [ ] **Step 1: Write transport monkey tests**

```move
#[test_only]
module astrologistics::transport_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage};
use astrologistics::transport;

/// Monkey: fuel_cost below minimum should fail
#[test]
#[expected_failure(abort_code = transport::E_FUEL_COST_TOO_LOW)]
fun test_fuel_cost_below_minimum() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let c1 = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        let c2 = storage::create_storage(2, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(c1, admin);
        transfer::public_transfer(c2, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // fuel_cost = 1 (way below min = 10 * 100 = 1000)
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 1, 0, 0, &clock, scenario.ctx(),
        );
        transfer::transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey: fuel_cost above maximum should fail
#[test]
#[expected_failure(abort_code = transport::E_FUEL_COST_TOO_HIGH)]
fun test_fuel_cost_above_maximum() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let c1 = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        let c2 = storage::create_storage(2, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(c1, admin);
        transfer::public_transfer(c2, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // fuel_cost = 100_000_000 (above max = 100_000 * 100 = 10_000_000)
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 100_000_000, 0, 0, &clock, scenario.ctx(),
        );
        transfer::transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey: invalid tier (3) should fail
#[test]
#[expected_failure(abort_code = transport::E_INVALID_TIER)]
fun test_invalid_tier() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let c1 = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        let c2 = storage::create_storage(2, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(c1, admin);
        transfer::public_transfer(c2, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s1, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s1);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let order = transport::create_order(
            &s1, &s2, receipt, vector[1, 2], 5000, 0, 3, &clock, scenario.ctx(),
        );
        transfer::transfer(order, user);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Write fuel_station monkey tests**

```move
#[test_only]
module astrologistics::fuel_station_monkey_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use astrologistics::storage::{Self, Storage};
use astrologistics::fuel_token::{Self, FuelTreasuryCap};
use astrologistics::fuel_station::{Self, FuelStation, StationCap};

/// Monkey: buy more fuel than available
#[test]
#[expected_failure(abort_code = fuel_station::E_INSUFFICIENT_FUEL)]
fun test_buy_more_than_available() {
    let admin = @0xAD;
    let supplier = @0xS1;
    let buyer = @0xB1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(supplier);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel_token::mint(&mut t, 100, scenario.ctx());
        let r = fuel_station::supply_fuel(&mut st, fuel, scenario.ctx());
        transfer::public_transfer(r, supplier);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.next_tx(buyer);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let payment = coin::mint_for_testing(1_000_000, scenario.ctx());
        // Try to buy 200 but only 100 available
        let f = fuel_station::buy_fuel(&mut st, payment, 200, 10000, &mut t, scenario.ctx());
        coin::burn_for_testing(f);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.end();
}

/// Monkey: slippage protection — price exceeds max
#[test]
#[expected_failure(abort_code = fuel_station::E_PRICE_EXCEEDS_MAX)]
fun test_slippage_protection() {
    let admin = @0xAD;
    let supplier = @0xS1;
    let buyer = @0xB1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel_token::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        // High alpha = 900 means price spikes fast when scarce
        let sc = fuel_station::create_station(&s, 100, 900, 0, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(supplier);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel_token::mint(&mut t, 100, scenario.ctx());
        let r = fuel_station::supply_fuel(&mut st, fuel, scenario.ctx());
        transfer::public_transfer(r, supplier);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.next_tx(buyer);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let payment = coin::mint_for_testing(1_000_000, scenario.ctx());
        // Set max_price_per_unit very low (50) — actual price is higher
        let f = fuel_station::buy_fuel(&mut st, payment, 10, 50, &mut t, scenario.ctx());
        coin::burn_for_testing(f);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.end();
}

/// Monkey: update fee above cap should fail
#[test]
#[expected_failure(abort_code = fuel_station::E_FEE_TOO_HIGH)]
fun test_update_fee_above_cap() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let cap = test_scenario::take_from_sender<StationCap>(&scenario);
        // 6000 > 5000 cap — should fail
        fuel_station::update_fee(&mut st, &cap, 6000);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(st);
    };
    scenario.end();
}
```

- [ ] **Step 3: Run all tests**

Run: `cd move && sui move test`
Expected: ALL PASS

- [ ] **Step 4: Commit**

```bash
git add move/tests/transport_monkey_tests.move move/tests/fuel_station_monkey_tests.move
git commit -m "test: monkey tests for transport + fuel_station edge cases"
```

---

## Task 7: Full Build + Integration Verification

- [ ] **Step 1: Clean build**

Run: `cd move && sui move build`
Expected: Build Successful

- [ ] **Step 2: Run all tests**

Run: `cd move && sui move test`
Expected: ALL PASS (25+ tests across all modules)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: Plan 2 complete — transport (tiered) + fuel_station (AMM + O(1) revenue)"
```

---

## Summary

| Module | Tests | Key Patterns |
|--------|-------|-------------|
| `transport` | 6+ tests | Tiered transfer (Instant/Express/Standard), fuel burn, time delay enforcement, min/max cost validation |
| `fuel_station` | 8+ tests | AMM inventory pricing, MasterChef O(1) accumulator, scarce bonus, supplier exit, slippage protection |

**Next:** Plan 3 (courier_market) depends on Plans 1 + 2.
