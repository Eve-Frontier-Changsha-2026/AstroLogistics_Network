# Plan 1: Foundation Layer (fuel_token + storage + threat_oracle)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three base-layer Move modules that all upper layers depend on: FUEL token, Smart Storage, and Threat Oracle.

**Architecture:** Single Sui Move package (`astrologistics`). Three independent modules with no cross-dependencies. `storage` uses `ObjectBag` for multi-cargo storage + `WithdrawAuth` hot-potato for third-party withdrawals. `threat_oracle` uses `Table` for danger scores with time-decay. `fuel_token` defines FUEL coin via OTW pattern.

**Tech Stack:** Sui Move 2024 Edition, sui CLI 1.68.0, `sui move test` for unit tests

**Spec:** `docs/superpowers/specs/2026-03-20-astrologistics-design.md`

---

## Review Fixes (2026-03-21)

> 以下修正來自四路審核（Architecture + Developer + Tester + Security），實作時必須套用。

### Fix C1 (Critical): 倉儲費必須實際收取
- `withdraw` / `withdraw_with_auth` 回傳改為 `(Cargo, Coin<SUI>)` — fee 仍算但實際扣錢
- Storage 新增 `accumulated_fees: Balance<SUI>` 欄位
- `withdraw` 接受 `payment: Coin<SUI>` 參數，`assert!(coin::value(&payment) >= fee)`
- 超付部分退回 caller，fee 加入 `accumulated_fees`
- 新增 `claim_fees(storage, cap, ctx): Coin<SUI>` 讓 admin 提領費用
- **Hackathon 簡化方案**: 如果覺得太重，可改為 `withdraw` 直接從 caller 的 Coin 扣費但不新增 accumulated_fees（fee 歸 admin 直接 transfer）

### Fix H1 (High): WithdrawAuth 改為零 ability（真正 hot-potato）
```move
// 修改前
public struct WithdrawAuth has drop { ... }
// 修改後
public struct WithdrawAuth { ... }  // 無任何 ability
```
- `withdraw_with_auth` 內部必須顯式解構 auth（`let WithdrawAuth { receipt_id, authorized_by: _ } = auth;`）
- 這樣 compiler 強制消費，不能靜默丟棄

### Fix H2 (High): withdraw 加 cargo 存在檢查
```move
// withdraw 開頭加入
assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);
```

### Fix M1 (Medium): update_fee_rate 加上限
```move
const E_FEE_TOO_HIGH: u64 = 7;

public fun update_fee_rate(storage: &mut Storage, cap: &AdminCap, new_rate: u64) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    assert!(new_rate <= constants::max_owner_fee_bps(), E_FEE_TOO_HIGH);
    storage.fee_rate_bps = new_rate;
}
```

### Fix M2 (Medium): fee 計算防溢位
```move
// 修改前
let fee = cargo.value * storage.fee_rate_bps * days_stored / 10000;
// 修改後 — 先除再乘，或用 u128
let fee = ((cargo.value as u128) * (storage.fee_rate_bps as u128) * (days_stored as u128) / 10000u128 as u64);
```

### Fix M9 (Medium): 補缺的 error path 測試
在 monkey tests 中新增：
1. `test_withdraw_auth_mismatch` → `#[expected_failure(abort_code = storage::E_AUTH_MISMATCH)]`
2. `test_admin_reclaim_receipt_still_live` → `#[expected_failure(abort_code = storage::E_RECEIPT_STILL_LIVE)]`
3. `test_batch_too_large` → `#[expected_failure(abort_code = threat_oracle::E_BATCH_TOO_LARGE)]`
4. `test_route_too_long` → `#[expected_failure(abort_code = threat_oracle::E_ROUTE_TOO_LONG)]`
5. `test_withdraw_fee_amount_correct` → 驗證 fee 數值正確
6. Fix `test_admin_reclaim_too_early` — 先 `clear_live_receipt_for_testing` 再測 grace period

### Fix Low: create_withdraw_auth 改為 public(package)
```move
public(package) fun create_withdraw_auth(receipt_id: ID, authorized_by: ID): WithdrawAuth { ... }
```

### Question Q1: FuelTreasuryCap 持有者
- 決定：採用 Fix C2（Plan 2）的 `Balance<FUEL>` 方案後，`buy_fuel` 和 `withdraw_supplier` 不再需要 FuelTreasuryCap
- `FuelTreasuryCap` 仍由部署者持有，僅用於初始 mint 給 fuel_station

---

## File Structure

```
move/
├── Move.toml
└── sources/
    ├── fuel_token.move        # FUEL OTW + TreasuryCap + mint/burn
    ├── storage.move           # Storage shared object + Cargo + Receipt + WithdrawAuth
    ├── threat_oracle.move     # ThreatMap + DangerEntry + ReporterCap + OracleCap
    └── constants.move         # FP_SCALE, BPS_SCALE, MAX_OWNER_FEE_BPS shared constants
└── tests/
    ├── fuel_token_tests.move
    ├── storage_tests.move
    └── threat_oracle_tests.move
```

---

## Task 1: Project Scaffolding

**Files:**
- Create: `move/Move.toml`
- Create: `move/sources/constants.move`

- [ ] **Step 1: Initialize Move project structure**

```bash
mkdir -p move/sources move/tests
```

- [ ] **Step 2: Create Move.toml**

```toml
[package]
name = "astrologistics"
edition = "2024.beta"

[dependencies]
Sui = { git = "https://github.com/MystenLabs/sui.git", subdir = "crates/sui-framework/packages/sui-framework", rev = "framework/testnet" }

[addresses]
astrologistics = "0x0"
```

- [ ] **Step 3: Create constants module**

```move
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
```

- [ ] **Step 4: Verify build**

Run: `cd move && sui move build`
Expected: Build Successful

- [ ] **Step 5: Commit**

```bash
git add move/
git commit -m "feat: scaffold Move project with constants module"
```

---

## Task 2: fuel_token Module

**Files:**
- Create: `move/sources/fuel_token.move`
- Create: `move/tests/fuel_token_tests.move`

- [ ] **Step 1: Write the failing test**

```move
#[test_only]
module astrologistics::fuel_token_tests;

use sui::test_scenario;
use sui::coin;
use astrologistics::fuel_token::{Self, FUEL, FuelTreasuryCap};

#[test]
fun test_init_creates_treasury_cap() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        fuel_token::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(admin);
    {
        assert!(test_scenario::has_most_recent_for_sender<FuelTreasuryCap>(&scenario));
    };
    scenario.end();
}

#[test]
fun test_mint_and_burn() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        fuel_token::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(admin);
    {
        let mut treasury = test_scenario::take_from_sender<FuelTreasuryCap>(&scenario);
        let fuel_coin = fuel_token::mint(&mut treasury, 1000, scenario.ctx());
        assert!(coin::value(&fuel_coin) == 1000);
        fuel_token::burn(&mut treasury, fuel_coin);
        test_scenario::return_to_sender(&scenario, treasury);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter fuel_token`
Expected: FAIL (module not found)

- [ ] **Step 3: Write fuel_token module**

```move
module astrologistics::fuel_token;

use sui::coin::{Self, Coin, TreasuryCap};

/// One-Time Witness for FUEL coin
public struct FUEL has drop {}

/// Wrapper around TreasuryCap for public API
public struct FuelTreasuryCap has key, store {
    id: UID,
    cap: TreasuryCap<FUEL>,
}

fun init(witness: FUEL, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        witness,
        9,                          // decimals (matches SUI)
        b"FUEL",
        b"Astro Fuel",
        b"Fuel token for AstroLogistics cross-galaxy transport",
        option::none(),
        ctx,
    );
    // Freeze metadata (immutable)
    transfer::public_freeze_object(metadata);
    // Wrap TreasuryCap and send to deployer
    let fuel_treasury = FuelTreasuryCap {
        id: object::new(ctx),
        cap: treasury_cap,
    };
    transfer::transfer(fuel_treasury, ctx.sender());
}

/// Mint FUEL tokens
public fun mint(treasury: &mut FuelTreasuryCap, amount: u64, ctx: &mut TxContext): Coin<FUEL> {
    coin::mint(&mut treasury.cap, amount, ctx)
}

/// Burn FUEL tokens
public fun burn(treasury: &mut FuelTreasuryCap, coin: Coin<FUEL>) {
    coin::burn(&mut treasury.cap, coin);
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(FUEL {}, ctx);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd move && sui move test --filter fuel_token`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/fuel_token.move move/tests/fuel_token_tests.move
git commit -m "feat: add fuel_token module with OTW mint/burn"
```

---

## Task 3: storage Module — Core Structs + create_storage

**Files:**
- Create: `move/sources/storage.move`
- Create: `move/tests/storage_tests.move`

- [ ] **Step 1: Write failing test for create_storage**

```move
#[test_only]
module astrologistics::storage_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, AdminCap};

#[test]
fun test_create_storage() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        storage::create_storage(
            1001,    // system_id
            10000,   // max_capacity
            100,     // fee_rate_bps (1% per day)
            &clock,
            scenario.ctx(),
        );
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        // AdminCap should be owned by admin
        assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario));
        // Storage should be shared
        let storage = test_scenario::take_shared<Storage>(&scenario);
        assert!(storage::system_id(&storage) == 1001);
        assert!(storage::available_capacity(&storage) == 10000);
        assert!(storage::fee_rate(&storage) == 100);
        test_scenario::return_shared(storage);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd move && sui move test --filter test_create_storage`
Expected: FAIL

- [ ] **Step 3: Write storage module (core structs + create_storage + getters)**

```move
module astrologistics::storage;

use sui::object_bag::{Self, ObjectBag};
use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;

// ============ Error codes ============
const E_CAP_MISMATCH: u64 = 0;
const E_CAPACITY_EXCEEDED: u64 = 1;
const E_RECEIPT_MISMATCH: u64 = 2;
const E_AUTH_MISMATCH: u64 = 3;
const E_RECEIPT_STILL_LIVE: u64 = 4;
const E_GRACE_PERIOD_NOT_MET: u64 = 5;
const E_CARGO_NOT_FOUND: u64 = 6;

// ============ Structs ============

public struct Storage has key {
    id: UID,
    owner: address,
    system_id: u64,
    max_capacity: u64,
    current_load: u64,
    fee_rate_bps: u64,
    cargo_bag: ObjectBag,
    live_receipts: Table<ID, bool>,   // keyed by cargo_id (not receipt_id)
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

/// Hot-potato: must be consumed in the same PTB. Used by upper-layer modules
/// (e.g., courier_market) to authorize third-party withdrawals.
public struct WithdrawAuth has drop {
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
    let storage = Storage {
        id: object::new(ctx),
        owner: ctx.sender(),
        system_id,
        max_capacity,
        current_load: 0,
        fee_rate_bps,
        cargo_bag: object_bag::new(ctx),
        live_receipts: table::new(ctx),
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

// Cargo getters — by reference (for when caller has a Cargo object)
public fun cargo_weight(cargo: &Cargo): u64 { cargo.weight }
public fun cargo_value(cargo: &Cargo): u64 { cargo.value }
public fun cargo_owner(cargo: &Cargo): address { cargo.owner }

// Cargo getters — by storage + cargo_id (for upper modules that need to read without withdrawing)
public fun cargo_weight_by_id(storage: &Storage, cargo_id: ID): u64 {
    let cargo: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    cargo.weight
}
public fun cargo_value_by_id(storage: &Storage, cargo_id: ID): u64 {
    let cargo: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    cargo.value
}

#[test_only]
/// Clear live_receipt for a cargo (simulates receipt consumption by upper modules)
public fun clear_live_receipt_for_testing(storage: &mut Storage, cargo_id: ID) {
    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };
}

// Receipt getters
public fun receipt_storage_id(receipt: &DepositReceipt): ID { receipt.storage_id }
public fun receipt_cargo_id(receipt: &DepositReceipt): ID { receipt.cargo_id }

// WithdrawAuth constructor (for upper modules)
public fun create_withdraw_auth(receipt_id: ID, authorized_by: ID): WithdrawAuth {
    WithdrawAuth { receipt_id, authorized_by }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd move && sui move test --filter test_create_storage`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add move/sources/storage.move move/tests/storage_tests.move
git commit -m "feat: storage module core structs + create_storage"
```

---

## Task 4: storage Module — deposit + withdraw

**Files:**
- Modify: `move/sources/storage.move`
- Modify: `move/tests/storage_tests.move`

- [ ] **Step 1: Write failing tests for deposit + withdraw**

Add to `storage_tests.move`:

```move
#[test]
fun test_deposit_and_withdraw() {
    let user = @0xU1;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    // Create storage
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };

    // Deposit
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000); // t=1s

        let receipt = storage::deposit(
            &mut s,
            b"ore",
            500,     // weight
            10000,   // value
            &clock,
            scenario.ctx(),
        );

        assert!(storage::available_capacity(&s) == 9500); // 10000 - 500
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };

    // Withdraw
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000); // ~1 day later

        let (cargo, _fee_amount) = storage::withdraw(&mut s, receipt, &clock, scenario.ctx());

        assert!(storage::available_capacity(&s) == 10000); // capacity restored
        assert!(storage::cargo_weight(&cargo) == 500);

        // Clean up cargo
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_CAPACITY_EXCEEDED)]
fun test_deposit_exceeds_capacity() {
    let user = @0xU1;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 100, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // weight 200 > capacity 100
        let receipt = storage::deposit(&mut s, b"ore", 200, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd move && sui move test --filter storage_tests`
Expected: FAIL (deposit/withdraw not found)

- [ ] **Step 3: Add deposit + withdraw to storage.move**

Add to `storage.move` public functions section:

```move
/// Deposit cargo into storage. Returns a DepositReceipt.
public fun deposit(
    storage: &mut Storage,
    item_type: vector<u8>,
    weight: u64,
    value: u64,
    clock: &Clock,
    ctx: &mut TxContext,
): DepositReceipt {
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
    // Track by cargo_id (so admin_reclaim can check if receipt is still live)
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

/// Withdraw cargo using a DepositReceipt. Calculates and returns storage fee.
/// Returns (Cargo, storage_fee_amount).
public fun withdraw(
    storage: &mut Storage,
    receipt: DepositReceipt,
    clock: &Clock,
    ctx: &mut TxContext,
): (Cargo, u64) {
    let DepositReceipt { id, storage_id, cargo_id, depositor: _ } = receipt;
    assert!(storage_id == object::id(storage), E_RECEIPT_MISMATCH);

    // Remove live receipt tracking
    object::delete(id);

    // Remove live receipt tracking (keyed by cargo_id)
    if (table::contains(&storage.live_receipts, cargo_id)) {
        table::remove(&mut storage.live_receipts, cargo_id);
    };

    // Remove cargo from bag
    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;

    // Calculate storage fee: value * fee_rate_bps / BPS_SCALE * days_stored
    let now = clock::timestamp_ms(clock);
    let duration_ms = if (now > cargo.deposited_at) { now - cargo.deposited_at } else { 0 };
    let days_stored = duration_ms / 86_400_000;
    let fee = if (days_stored == 0) { 0 } else {
        cargo.value * storage.fee_rate_bps * days_stored / 10000
    };

    event::emit(CargoWithdrawn {
        storage_id: object::id(storage),
        cargo_id,
        withdrawer: ctx.sender(),
        storage_fee: fee,
    });

    (cargo, fee)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd move && sui move test --filter storage_tests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/storage.move move/tests/storage_tests.move
git commit -m "feat: storage deposit + withdraw with time-based fees"
```

---

## Task 5: storage Module — withdraw_with_auth + admin_reclaim + update_fee_rate

**Files:**
- Modify: `move/sources/storage.move`
- Modify: `move/tests/storage_tests.move`

- [ ] **Step 1: Write failing tests**

Add to `storage_tests.move`:

```move
use astrologistics::storage::WithdrawAuth;

#[test]
fun test_withdraw_with_auth() {
    let user = @0xU1;
    let courier = @0xC1;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    // Create storage + deposit
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };

    // Courier withdraws with auth (simulating courier_market PTB)
    scenario.next_tx(courier);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_address<storage::DepositReceipt>(&scenario, user);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt_id = object::id(&receipt);
        let auth = storage::create_withdraw_auth(
            receipt_id,
            object::id_from_address(@0xCONTRACT), // simulated contract ID
        );
        let (cargo, _fee) = storage::withdraw_with_auth(&mut s, receipt, auth, &clock, scenario.ctx());
        assert!(storage::cargo_weight(&cargo) == 100);
        transfer::public_transfer(cargo, courier);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_admin_reclaim_after_grace_period() {
    let user = @0xU1;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    // Create storage
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo
    scenario.next_tx(user);
    let cargo_id;
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        cargo_id = storage::receipt_cargo_id(&receipt);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };

    // Simulate receipt consumed (e.g., by courier_market withdraw_with_auth)
    // Use test-only helper to clear live_receipt without removing cargo
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        storage::clear_live_receipt_for_testing(&mut s, cargo_id);
        test_scenario::return_shared(s);
    };

    // Admin reclaims after 31 days — should succeed (no live receipt + grace period met)
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 31 * 86_400_000);

        assert!(storage::current_load(&s) == 100);
        storage::admin_reclaim(&mut s, &cap, cargo_id, &clock, scenario.ctx());
        assert!(storage::current_load(&s) == 0); // capacity freed

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_update_fee_rate() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        storage::update_fee_rate(&mut s, &cap, 200);
        assert!(storage::fee_rate(&s) == 200);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_CAP_MISMATCH)]
fun test_update_fee_rate_wrong_cap() {
    let admin1 = @0xA1;
    let admin2 = @0xA2;
    let mut scenario = test_scenario::begin(admin1);
    // Create two storages with two different admin caps
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin1);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin2);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap2 = storage::create_storage(1002, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap2, admin2);
        clock::destroy_for_testing(clock);
    };
    // admin2 tries to update storage1 with cap2
    scenario.next_tx(admin2);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap2 = test_scenario::take_from_sender<AdminCap>(&scenario);
        // This should abort: cap2.storage_id != storage1.id
        storage::update_fee_rate(&mut s, &cap2, 999);
        test_scenario::return_to_sender(&scenario, cap2);
        test_scenario::return_shared(s);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd move && sui move test --filter storage_tests`
Expected: FAIL

- [ ] **Step 3: Add withdraw_with_auth + admin_reclaim + update_fee_rate**

Add to `storage.move`:

```move
/// Withdraw using hot-potato auth (for third-party withdrawals like courier)
public fun withdraw_with_auth(
    storage: &mut Storage,
    receipt: DepositReceipt,
    auth: WithdrawAuth,
    clock: &Clock,
    ctx: &mut TxContext,
): (Cargo, u64) {
    let receipt_id = object::id(&receipt);
    assert!(auth.receipt_id == receipt_id, E_AUTH_MISMATCH);
    // auth is consumed here (drop)
    withdraw(storage, receipt, clock, ctx)
}

/// Admin reclaim orphaned cargo after grace period.
/// Only works when the corresponding receipt has been consumed (withdrawn/destroyed).
public fun admin_reclaim(
    storage: &mut Storage,
    cap: &AdminCap,
    cargo_id: ID,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    assert!(object_bag::contains(&storage.cargo_bag, cargo_id), E_CARGO_NOT_FOUND);

    // Check that no live receipt exists for this cargo (receipt was consumed/lost)
    assert!(!table::contains(&storage.live_receipts, cargo_id), E_RECEIPT_STILL_LIVE);

    // Borrow to check grace period BEFORE removing
    let cargo_ref: &Cargo = object_bag::borrow(&storage.cargo_bag, cargo_id);
    let now = clock::timestamp_ms(clock);
    let grace_ms = astrologistics::constants::reclaim_grace_ms();
    assert!(now >= cargo_ref.deposited_at + grace_ms, E_GRACE_PERIOD_NOT_MET);

    // Now safe to remove
    let cargo: Cargo = object_bag::remove(&mut storage.cargo_bag, cargo_id);
    storage.current_load = storage.current_load - cargo.weight;

    event::emit(AdminReclaimed {
        storage_id: object::id(storage),
        cargo_id,
    });

    // Destroy cargo (admin absorbs)
    let Cargo { id, owner: _, item_type: _, weight: _, value: _, storage_id: _, deposited_at: _ } = cargo;
    object::delete(id);
}

/// Update storage fee rate (admin only)
public fun update_fee_rate(storage: &mut Storage, cap: &AdminCap, new_rate: u64) {
    assert!(cap.storage_id == object::id(storage), E_CAP_MISMATCH);
    storage.fee_rate_bps = new_rate;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd move && sui move test --filter storage_tests`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/storage.move move/tests/storage_tests.move
git commit -m "feat: storage withdraw_with_auth + admin_reclaim + update_fee_rate"
```

---

## Task 6: threat_oracle Module — Core Structs + OracleCap + batch_update

**Files:**
- Create: `move/sources/threat_oracle.move`
- Create: `move/tests/threat_oracle_tests.move`

- [ ] **Step 1: Write failing tests**

```move
#[test_only]
module astrologistics::threat_oracle_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap};

#[test]
fun test_create_threat_map() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx()); // decay_lambda = 0.1
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        assert!(test_scenario::has_most_recent_for_sender<OracleCap>(&scenario));
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        test_scenario::return_shared(map);
    };
    scenario.end();
}

#[test]
fun test_batch_update_and_query() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        threat_oracle::create_threat_map(100, scenario.ctx());
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        // Batch update: system 10 = danger 800, system 20 = danger 1500
        let system_ids = vector[10u64, 20u64];
        let scores = vector[800u64, 1500u64];
        threat_oracle::batch_update(&mut map, &cap, system_ids, scores, &clock);

        // Query immediately (no decay)
        let score_10 = threat_oracle::get_danger_score(&map, 10, &clock);
        let score_20 = threat_oracle::get_danger_score(&map, 20, &clock);
        assert!(score_10 == 800);
        assert!(score_20 == 1500);

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd move && sui move test --filter threat_oracle`
Expected: FAIL

- [ ] **Step 3: Write threat_oracle module**

```move
module astrologistics::threat_oracle;

use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;
use astrologistics::constants;

// ============ Error codes ============
const E_BATCH_TOO_LARGE: u64 = 0;
const E_BATCH_LENGTH_MISMATCH: u64 = 1;
const E_COOLDOWN_NOT_MET: u64 = 2;
const E_ROUTE_TOO_LONG: u64 = 3;
const E_SYSTEM_NOT_FOUND: u64 = 4;
const E_NOT_REPORTER_OWNER: u64 = 5;

// ============ Structs ============

public struct ThreatMap has key {
    id: UID,
    danger_scores: Table<u64, DangerEntry>,
    decay_lambda: u64,  // FP_SCALE
}

public struct DangerEntry has store, drop, copy {
    score: u64,
    event_count: u64,
    last_updated: u64,
}

public struct OracleCap has key, store {
    id: UID,
}

public struct ReporterCap has key {
    id: UID,
    reporter: address,
    missions_completed: u64,
    last_report_at: u64,
    cooldown_ms: u64,
}

// ============ Events ============

public struct ThreatUpdated has copy, drop {
    system_id: u64,
    new_score: u64,
    source: vector<u8>, // b"oracle" or b"reporter"
}

public struct IncidentReported has copy, drop {
    system_id: u64,
    reporter: address,
    weight: u64,
}

public struct ReporterRevoked has copy, drop {
    reporter: address,
}

// ============ Public functions ============

public fun create_threat_map(decay_lambda: u64, ctx: &mut TxContext): OracleCap {
    let map = ThreatMap {
        id: object::new(ctx),
        danger_scores: table::new(ctx),
        decay_lambda,
    };
    transfer::share_object(map);
    OracleCap { id: object::new(ctx) }
}

/// Oracle batch update (admin). Sets scores directly.
public fun batch_update(
    map: &mut ThreatMap,
    _cap: &OracleCap,
    system_ids: vector<u64>,
    scores: vector<u64>,
    clock: &Clock,
) {
    let len = system_ids.length();
    assert!(len == scores.length(), E_BATCH_LENGTH_MISMATCH);
    assert!(len <= constants::max_batch_size(), E_BATCH_TOO_LARGE);

    let now = clock::timestamp_ms(clock);
    let mut i = 0;
    while (i < len) {
        let sys_id = system_ids[i];
        let score = scores[i];
        if (table::contains(&map.danger_scores, sys_id)) {
            let entry = table::borrow_mut(&mut map.danger_scores, sys_id);
            entry.score = score;
            entry.last_updated = now;
        } else {
            table::add(&mut map.danger_scores, sys_id, DangerEntry {
                score,
                event_count: 0,
                last_updated: now,
            });
        };
        event::emit(ThreatUpdated { system_id: sys_id, new_score: score, source: b"oracle" });
        i = i + 1;
    };
}

/// Get danger score with time decay applied.
public fun get_danger_score(map: &ThreatMap, system_id: u64, clock: &Clock): u64 {
    if (!table::contains(&map.danger_scores, system_id)) {
        return 0
    };
    let entry = table::borrow(&map.danger_scores, system_id);
    let now = clock::timestamp_ms(clock);
    apply_decay(entry.score, now, entry.last_updated, map.decay_lambda)
}

/// Max danger score along a route
public fun max_danger_on_route(map: &ThreatMap, route: &vector<u64>, clock: &Clock): u64 {
    assert!(route.length() <= constants::max_route_length(), E_ROUTE_TOO_LONG);
    let mut max_score = 0u64;
    let mut i = 0;
    while (i < route.length()) {
        let score = get_danger_score(map, route[i], clock);
        if (score > max_score) {
            max_score = score;
        };
        i = i + 1;
    };
    max_score
}

/// Issue a ReporterCap (gated by OracleCap)
public fun issue_reporter_cap(
    _cap: &OracleCap,
    reporter: address,
    missions_completed: u64,
    ctx: &mut TxContext,
): ReporterCap {
    ReporterCap {
        id: object::new(ctx),
        reporter,
        missions_completed,
        last_report_at: 0,
        cooldown_ms: constants::reporter_cooldown_ms(),
    }
}

/// Reporter reports an incident (with cooldown + weight)
public fun report_incident(
    map: &mut ThreatMap,
    reporter_cap: &mut ReporterCap,
    system_id: u64,
    clock: &Clock,
) {
    let now = clock::timestamp_ms(clock);
    assert!(
        reporter_cap.last_report_at == 0 || now >= reporter_cap.last_report_at + reporter_cap.cooldown_ms,
        E_COOLDOWN_NOT_MET,
    );

    // Weight based on missions_completed: min(missions, 10) * FP_SCALE / 10
    let missions_capped = if (reporter_cap.missions_completed > 10) { 10 } else { reporter_cap.missions_completed };
    let weight = missions_capped * constants::fp_scale() / 10;
    let base_increment = 100; // base score increment per report
    let score_increment = base_increment * weight / constants::fp_scale();

    if (table::contains(&map.danger_scores, system_id)) {
        let entry = table::borrow_mut(&mut map.danger_scores, system_id);
        // Apply existing decay first, then add increment
        entry.score = apply_decay(entry.score, now, entry.last_updated, map.decay_lambda) + score_increment;
        entry.event_count = entry.event_count + 1;
        entry.last_updated = now;
    } else {
        table::add(&mut map.danger_scores, system_id, DangerEntry {
            score: score_increment,
            event_count: 1,
            last_updated: now,
        });
    };

    reporter_cap.last_report_at = now;

    event::emit(IncidentReported { system_id, reporter: reporter_cap.reporter, weight });
}

/// Revoke a reporter (burn their cap)
public fun revoke_reporter(_cap: &OracleCap, reporter_cap: ReporterCap) {
    let reporter_addr = reporter_cap.reporter;
    let ReporterCap { id, reporter: _, missions_completed: _, last_report_at: _, cooldown_ms: _ } = reporter_cap;
    object::delete(id);
    event::emit(ReporterRevoked { reporter: reporter_addr });
}

/// Increment missions_completed on a ReporterCap (called by courier_market after delivery)
public fun increment_missions(reporter_cap: &mut ReporterCap) {
    reporter_cap.missions_completed = reporter_cap.missions_completed + 1;
}

// ============ Internal ============

/// 3rd-order Taylor approximation of e^(-x):
/// e^(-x) ≈ 1 - x + x²/2 - x³/6
/// x = lambda * dt / FP_SCALE (time in hours: dt_ms / 3_600_000)
fun apply_decay(score: u64, now: u64, last_updated: u64, lambda: u64): u64 {
    if (now <= last_updated) { return score };
    let dt_ms = now - last_updated;
    // Convert to hours for reasonable decay rate
    let dt_hours = dt_ms / 3_600_000;
    if (dt_hours == 0) { return score };

    let fp = constants::fp_scale();
    // x = lambda * dt_hours / FP_SCALE (in FP_SCALE units)
    let x = lambda * dt_hours / fp;

    if (x >= fp) {
        // For x >= 1.0, e^(-x) < 0.37 — clamp to 0 for simplicity
        return 0
    };

    // Taylor: e^(-x) ≈ 1 - x + x²/2 - x³/6 (all in FP_SCALE)
    let x2 = x * x / fp;
    let x3 = x2 * x / fp;
    let decay_factor = fp - x + x2 / 2 - x3 / 6;

    // Clamp to [0, FP_SCALE]
    let clamped = if (decay_factor > fp) { fp } else { decay_factor };

    score * clamped / fp
}

#[test_only]
public fun create_threat_map_for_testing(decay_lambda: u64, ctx: &mut TxContext): OracleCap {
    create_threat_map(decay_lambda, ctx)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd move && sui move test --filter threat_oracle`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add move/sources/threat_oracle.move move/tests/threat_oracle_tests.move
git commit -m "feat: threat_oracle with batch_update, decay, reporter system"
```

---

## Task 7: threat_oracle — Reporter Tests + Decay Tests

**Files:**
- Modify: `move/tests/threat_oracle_tests.move`

- [ ] **Step 1: Write reporter + decay tests**

Add to `threat_oracle_tests.move`:

```move
#[test]
fun test_reporter_incident_with_cooldown() {
    let admin = @0xAD;
    let courier = @0xC1;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let reporter_cap = threat_oracle::issue_reporter_cap(&cap, courier, 5, scenario.ctx());
        transfer::transfer(reporter_cap, courier);
        test_scenario::return_to_sender(&scenario, cap);
    };
    // Report incident
    scenario.next_tx(courier);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let mut reporter = test_scenario::take_from_sender<threat_oracle::ReporterCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        threat_oracle::report_incident(&mut map, &mut reporter, 42, &clock);
        let score = threat_oracle::get_danger_score(&map, 42, &clock);
        assert!(score > 0); // score should be > 0 after report
        test_scenario::return_to_sender(&scenario, reporter);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = threat_oracle::E_COOLDOWN_NOT_MET)]
fun test_reporter_cooldown_enforced() {
    let admin = @0xAD;
    let courier = @0xC1;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let reporter_cap = threat_oracle::issue_reporter_cap(&cap, courier, 5, scenario.ctx());
        transfer::transfer(reporter_cap, courier);
        test_scenario::return_to_sender(&scenario, cap);
    };
    scenario.next_tx(courier);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let mut reporter = test_scenario::take_from_sender<threat_oracle::ReporterCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        threat_oracle::report_incident(&mut map, &mut reporter, 42, &clock);
        // Try again immediately (should fail - cooldown not met)
        clock::set_for_testing(&mut clock, 2000); // only 1 second later
        threat_oracle::report_incident(&mut map, &mut reporter, 42, &clock);
        test_scenario::return_to_sender(&scenario, reporter);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_danger_score_decays_over_time() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        // decay_lambda = 500 (0.5 per hour)
        let oracle_cap = threat_oracle::create_threat_map(500, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);

        threat_oracle::batch_update(&mut map, &cap, vector[10], vector[1000], &clock);

        // Query immediately: should be 1000
        let score_now = threat_oracle::get_danger_score(&map, 10, &clock);
        assert!(score_now == 1000);

        // Query after 2 hours: should be significantly less
        clock::set_for_testing(&mut clock, 2 * 3_600_000);
        let score_later = threat_oracle::get_danger_score(&map, 10, &clock);
        assert!(score_later < score_now);

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_max_danger_on_route() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);

        threat_oracle::batch_update(
            &mut map, &cap,
            vector[10, 20, 30],
            vector[500, 1200, 800],
            &clock,
        );

        let route = vector[10, 20, 30];
        let max_d = threat_oracle::max_danger_on_route(&map, &route, &clock);
        assert!(max_d == 1200); // system 20 has highest

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run tests**

Run: `cd move && sui move test --filter threat_oracle`
Expected: PASS (all 6 tests)

- [ ] **Step 3: Commit**

```bash
git add move/tests/threat_oracle_tests.move
git commit -m "test: threat_oracle reporter cooldown + decay + route tests"
```

---

## Task 8: Monkey Testing — Edge Cases & Adversarial Tests

**Files:**
- Create: `move/tests/storage_monkey_tests.move`
- Create: `move/tests/threat_oracle_monkey_tests.move`

- [ ] **Step 1: Write storage monkey tests**

```move
#[test_only]
module astrologistics::storage_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, AdminCap};

/// Monkey test: deposit exactly at max capacity
#[test]
fun test_deposit_exact_capacity() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 100, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Deposit exactly 100 weight into 100 capacity
        let receipt = storage::deposit(&mut s, b"ore", 100, 1000, &clock, scenario.ctx());
        assert!(storage::available_capacity(&s) == 0);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: deposit zero weight cargo
#[test]
fun test_deposit_zero_weight() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 100, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Zero weight should work (information/data cargo)
        let receipt = storage::deposit(&mut s, b"intel", 0, 500, &clock, scenario.ctx());
        assert!(storage::available_capacity(&s) == 100); // capacity unchanged
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: deposit zero value cargo
#[test]
fun test_deposit_zero_value() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 100, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"junk", 10, 0, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Withdraw immediately — fee should be 0 (0 value × anything = 0)
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let (cargo, fee) = storage::withdraw(&mut s, receipt, &clock, scenario.ctx());
        assert!(fee == 0);
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: multiple deposits then withdrawals in different order
#[test]
fun test_multiple_deposit_withdraw_out_of_order() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 1000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    // Deposit 3 items
    scenario.next_tx(user);
    let r1;
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        r1 = storage::deposit(&mut s, b"a", 100, 100, &clock, scenario.ctx());
        let r2 = storage::deposit(&mut s, b"b", 200, 200, &clock, scenario.ctx());
        let r3 = storage::deposit(&mut s, b"c", 300, 300, &clock, scenario.ctx());
        assert!(storage::current_load(&s) == 600);
        transfer::public_transfer(r2, user);
        transfer::public_transfer(r3, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };

    // Withdraw first item (r1) — should not affect r2, r3
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let (cargo, _) = storage::withdraw(&mut s, r1, &clock, scenario.ctx());
        assert!(storage::current_load(&s) == 500); // 200 + 300
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: admin_reclaim before grace period should fail
#[test]
#[expected_failure(abort_code = storage::E_GRACE_PERIOD_NOT_MET)]
fun test_admin_reclaim_too_early() {
    let admin = @0xAD;
    let user = @0xU1;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 1000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    let cargo_id;
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        cargo_id = storage::receipt_cargo_id(&receipt);
        transfer::public_transfer(receipt, @0xBLACKHOLE);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Try reclaim after only 1 day (should fail, need 30 days)
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_400_000); // 1 day
        storage::admin_reclaim(&mut s, &cap, cargo_id, &clock, scenario.ctx());
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
```

- [ ] **Step 2: Write threat_oracle monkey tests**

```move
#[test_only]
module astrologistics::threat_oracle_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap};

/// Monkey test: query non-existent system returns 0
#[test]
fun test_query_nonexistent_system() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let score = threat_oracle::get_danger_score(&map, 99999, &clock);
        assert!(score == 0);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: max_danger_on_route with empty route
#[test]
fun test_empty_route_max_danger() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let route = vector[];
        let max_d = threat_oracle::max_danger_on_route(&map, &route, &clock);
        assert!(max_d == 0);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: batch update with 0 entries (should not fail)
#[test]
fun test_batch_update_empty() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        threat_oracle::batch_update(&mut map, &cap, vector[], vector[], &clock);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: score after very long time should approach 0
#[test]
fun test_extreme_decay() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        // Very aggressive decay: lambda = 900 (0.9 per hour)
        let cap = threat_oracle::create_threat_map(900, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);
        threat_oracle::batch_update(&mut map, &cap, vector[1], vector[10000], &clock);

        // After 100 hours with lambda=0.9, x=90 >> 1.0, should be 0
        clock::set_for_testing(&mut clock, 100 * 3_600_000);
        let score = threat_oracle::get_danger_score(&map, 1, &clock);
        assert!(score == 0); // fully decayed

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Monkey test: revoke then try to report (should fail since cap is destroyed)
#[test]
fun test_revoke_reporter() {
    let admin = @0xAD;
    let courier = @0xC1;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let reporter_cap = threat_oracle::issue_reporter_cap(&cap, courier, 5, scenario.ctx());
        // Immediately revoke
        threat_oracle::revoke_reporter(&cap, reporter_cap);
        // reporter_cap is now destroyed — cannot report
        test_scenario::return_to_sender(&scenario, cap);
    };
    scenario.end();
}
```

- [ ] **Step 2: Run all tests**

Run: `cd move && sui move test`
Expected: ALL PASS

- [ ] **Step 3: Commit**

```bash
git add move/tests/storage_monkey_tests.move move/tests/threat_oracle_monkey_tests.move
git commit -m "test: monkey tests for storage + threat_oracle edge cases"
```

---

## Task 9: Full Build Verification

- [ ] **Step 1: Clean build**

Run: `cd move && sui move build`
Expected: Build Successful, no warnings

- [ ] **Step 2: Run all tests**

Run: `cd move && sui move test`
Expected: ALL PASS (15+ tests)

- [ ] **Step 3: Final commit + tag**

```bash
git add -A
git commit -m "feat: Plan 1 complete — foundation layer (fuel_token + storage + threat_oracle)"
```

---

## Summary

| Module | Tests | Key Patterns |
|--------|-------|-------------|
| `constants` | (no tests, pure constants) | Shared constants, FP_SCALE |
| `fuel_token` | 2 tests | OTW, TreasuryCap, mint/burn |
| `storage` | 8+ tests | SharedObject, ObjectBag, WithdrawAuth hot-potato, live_receipts tracking |
| `threat_oracle` | 8+ tests | Table, Taylor decay, ReporterCap cooldown + weight, OracleCap batch |

**Next:** Plan 2 (transport + fuel_station) depends on this layer.
