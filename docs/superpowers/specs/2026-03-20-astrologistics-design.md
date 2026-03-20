# AstroLogistics Network — 功能設計規格書

> 日期：2026-03-20
> 範圍：全功能原型（跨星系傳送 + 燃料站 AMM + 快遞任務市場）
> 憲法依據：EVE Frontier 專案憲法（收集→建設→摧毀循環、等價交換、資訊不對稱、可組合性）

---

## 1. 架構總覽

模組化分層架構，單一 Sui package（6 個 module）。所有 module 對外函式用 `public`，為未來拆 package 預留切割面。

```
┌─────────────────────────────────────────┐
│  courier_market  （快遞任務市場）         │  ← 應用層
├─────────────────────────────────────────┤
│  fuel_station    （燃料站 AMM + 補貨）    │  ← 經濟層
├─────────────────────────────────────────┤
│  transport       （跨星系傳送邏輯）       │  ← 物流層
├─────────────────────────────────────────┤
│  storage         （Smart Storage 物件）   │  ← 基礎層
│  threat_oracle   （危險指數預言機）       │  ← 基礎層
│  fuel_token      （FUEL 代幣定義）       │  ← 基礎層
└─────────────────────────────────────────┘
```

依賴方向：上層 → 下層，下層不依賴上層。

```
courier_market ──→ storage, fuel_station, threat_oracle
fuel_station   ──→ storage, fuel_token
transport      ──→ storage, threat_oracle, fuel_token
storage        ──→ (無依賴)
threat_oracle  ──→ (無依賴)
fuel_token     ──→ (無依賴)
```

> **注意**：`transport` 和 `courier_market` 是兩條平行的物流路徑。
> - `transport`：玩家自助跨星系傳送（付燃料，分三級：瞬間/快速/標準）
> - `courier_market`：委託其他玩家實飛運送（P2P 快遞，最經濟）
> 兩者都透過 `storage` 的存取介面操作貨物，但互不依賴。
> 形成完整的「價格-時間光譜」：瞬間(最貴) → 快速 → 標準 → 快遞實飛(最便宜)。

### 常數定義

所有 module 共用的定點數標準：

```
const FP_SCALE: u64 = 1000;      // 定點數標準比例：1000 = 1.0（用於 alpha、danger 等）
const BPS_SCALE: u64 = 10000;    // basis points 比例
const MAX_OWNER_FEE_BPS: u64 = 5000;  // 站主抽成上限 50%
```

### Struct Abilities 規範

| Struct | Abilities | 說明 |
|--------|-----------|------|
| `Storage` | `key` | Shared Object，不可轉讓 |
| `Cargo` | `key, store` | 可 wrap 進 Storage（需 store） |
| `AdminCap` | `key, store` | 可轉讓（= 賣站） |
| `DepositReceipt` | `key, store` | 可轉讓（可交給快遞員/交易）、可 wrap 進 Contract |
| `ThreatMap` | `key` | Shared Object，不可轉讓 |
| `OracleCap` | `key, store` | 可轉讓（管理權移交） |
| `ReporterCap` | `key` | **僅 key，不可轉讓**（綁定地址） |
| `TransportOrder` | `key` | Owned，不可轉讓（僅建立者操作） |
| `FuelStation` | `key` | Shared Object |
| `StationCap` | `key, store` | 可轉讓 |
| `SupplierReceipt` | `key, store` | 可轉讓（分潤權可交易） |
| `CourierContract` | `key` | Shared Object |
| `CourierBadge` | `key` | 僅 key，不可轉讓（一次性、綁定快遞員） |
| `WithdrawAuth` | `drop` | Hot-potato 授權憑證（見 storage 模組） |

---

## 2. Module 設計

### 2.0 fuel_token — 基礎層

**職責**：定義 FUEL 代幣類型，管理鑄造與銷毀。

**物件模型**：
- `FUEL` (OTW) — One-Time Witness，用於 `coin::create_currency`
- `FuelTreasuryCap` (Owned) — 鑄造/銷毀權限

**核心邏輯**：

```move
// init 函式中建立幣種
public struct FUEL has drop {}

fun init(witness: FUEL, ctx: &mut TxContext) {
    let (treasury_cap, metadata) = coin::create_currency(
        witness, 9, b"FUEL", b"Astro Fuel", b"...", option::none(), ctx
    );
    // treasury_cap 轉給部署者
    // metadata 設為 immutable
}
```

**公開介面**：

| 函式 | 說明 |
|------|------|
| `mint(cap, amount) → Coin<FUEL>` | 鑄造燃料（由 fuel_station 調用） |
| `burn(cap, coin)` | 銷毀燃料（transport 支付時銷毀） |

**設計決策**：
- 獨立 module 定義 FUEL，解耦代幣邏輯與業務邏輯
- `FuelTreasuryCap` 由系統管理者持有，未來可改為 DAO 控制
- 9 位小數精度，與 SUI 對齊

---

### 2.1 storage — 基礎層

**職責**：Smart Storage 倉庫管理、貨物存取、所有權控制。

**物件模型**：
- `Storage` (Shared Object) — 倉庫本體，使用 `ObjectBag` 存放多個 Cargo
- `Cargo` (key, store → wrap 進 Storage 的 ObjectBag) — 貨物
- `AdminCap` (Owned) — 站主管理權限，綁定特定 Storage
- `DepositReceipt` (Owned) — 提貨憑證，提領時銷毀
- `WithdrawAuth` (drop) — Hot-potato 授權憑證，用於第三方代提

**核心欄位**：

```
Storage {
    id: UID,
    owner: address,
    system_id: u64,
    max_capacity: u64,
    current_load: u64,
    fee_rate_bps: u64,           // 按時長計費：每日費率 (bps of cargo.value)
    cargo_bag: ObjectBag,        // 存放 Cargo 物件
    live_receipts: Table<ID, bool>,  // 追蹤 receipt 是否仍存活
    created_at: u64,
}

AdminCap {
    id: UID,
    storage_id: ID,
}

Cargo {
    id: UID,
    owner: address,
    item_type: String,
    weight: u64,
    value: u64,
    storage_id: ID,
    deposited_at: u64,
}

DepositReceipt {
    id: UID,
    storage_id: ID,
    cargo_id: ID,
    depositor: address,
}

/// Hot-potato：由 courier_market 等上層模組建立，用於授權第三方提貨
/// 必須在同一交易中消費（drop ability），不會持有在任何帳戶中
WithdrawAuth {
    receipt_id: ID,
    authorized_by: ID,           // 授權來源（如 CourierContract ID）
}
```

**公開介面**：

| 函式 | 說明 |
|------|------|
| `create_storage(system_id, max_capacity, fee_rate_bps) → AdminCap` | 建站 |
| `deposit(storage, item_type, weight, value, clock) → DepositReceipt` | 存貨（Cargo 放入 ObjectBag，live_receipts 記錄） |
| `withdraw(storage, receipt, clock) → (Cargo, Coin<SUI>)` | 提領（銷毀 Receipt，結算倉儲費，移除 live_receipts） |
| `withdraw_with_auth(storage, receipt, auth: WithdrawAuth, clock) → (Cargo, Coin<SUI>)` | 持 hot-potato 授權代提（驗證 auth.receipt_id 匹配，消費 auth） |
| `admin_reclaim(storage, cap, cargo_id, clock)` | 站主回收（grace period 30 天 + live_receipts 中無對應 receipt） |
| `cargo_weight(storage, cargo_id) → u64` | 查詢貨物重量 |
| `cargo_value(storage, cargo_id) → u64` | 查詢貨物價值 |
| `available_capacity(storage) → u64` | 查詢剩餘容量 |
| `fee_rate(storage) → u64` | 查詢費率 |
| `system_id(storage) → u64` | 查詢星系 ID |
| `update_fee_rate(storage, cap, new_rate)` | 站主調整費率 |

**倉儲費計算（withdraw 時結算）**：

```
storage_fee = cargo.value × fee_rate_bps / BPS_SCALE × days_stored
days_stored = (now - cargo.deposited_at) / 86_400_000   // ms → days
```

**設計決策**：
- 使用 `ObjectBag` 而非 struct field wrap — 支持存放多個異質 Cargo
- `WithdrawAuth` 是 hot-potato（只有 `drop`），上層模組建立後必須在同一 PTB 中消費，courier 永遠不會持有 Receipt，消除反向依賴 + 防止 courier 繞過合約直接提貨
- `live_receipts: Table<ID, bool>` 追蹤 receipt 存活狀態，`admin_reclaim` 只能回收無存活 receipt 的 Cargo
- 倉儲費按時長計費（現實映射：倉儲業者按天/月收費），withdraw 時一次結算
- `cargo_weight` / `cargo_value` 公開 getter，供上層 module 讀取

---

### 2.2 threat_oracle — 基礎層

**職責**：星系危險指數管理、時間衰減、情報回報。

**物件模型**：
- `ThreatMap` (Shared Object) — 全域威脅地圖
- `OracleCap` (Owned) — 系統管理者批量更新權限 + 反垃圾後盾 + 可撤銷 ReporterCap
- `ReporterCap` (key only, 不可轉讓) — 快遞員情報回報權限

**核心欄位**：

```
ThreatMap {
    id: UID,
    danger_scores: Table<u64, DangerEntry>,
    decay_lambda: u64,                         // 衰減係數（FP_SCALE）
}

DangerEntry {
    score: u64,           // FP_SCALE (1000 = 1.0)
    event_count: u64,
    last_updated: u64,
}

ReporterCap {
    id: UID,
    reporter: address,
    missions_completed: u64,     // 累計完成任務數，影響回報權重
    last_report_at: u64,
    cooldown_ms: u64,
}
```

**回報權重公式**：

```
report_weight = min(missions_completed, 10) / 10    // 老手(10+次)全權重，新手按比例
score_increment = BASE_INCREMENT × report_weight
```

**時間衰減近似（三階 Taylor 展開）**：

```
e^(-x) ≈ 1 - x + x²/2 - x³/6    (x = lambda × dt / FP_SCALE)
結果 clamp 到 [0, FP_SCALE]
```

**公開介面**：

| 函式 | 說明 |
|------|------|
| `batch_update(map, cap, updates)` | 管理者批量更新（上限 100 條） |
| `report_incident(map, reporter_cap, system_id, clock)` | 快遞員回報（檢查冷卻 + 權重計算） |
| `revoke_reporter(map, oracle_cap, reporter_cap)` | 撤銷惡意回報者的 ReporterCap（銷毀） |
| `issue_reporter_cap(oracle_cap, reporter: address, missions: u64) → ReporterCap` | 由 OracleCap 授權發行 ReporterCap |
| `get_danger_score(map, system_id, clock) → u64` | 查詢（含衰減，FP_SCALE 格式） |
| `max_danger_on_route(map, route, clock) → u64` | 路徑最大危險值（assert route.length() ≤ 50） |

**設計決策**：
- `ReporterCap` 僅 `key`（不可轉讓），綁定地址 + 冷卻時間 + missions_completed 權重
- `issue_reporter_cap` 由 `OracleCap` 控制發行 — courier_market 完成送達時調用此函式（需要 OracleCap reference）
- `revoke_reporter` 可銷毀惡意 reporter 的 cap
- batch_update 上限 100 條，防止 gas 超限
- max_danger_on_route 限制路徑長度 ≤ 50，防止 gas 超限
- 時間衰減用三階 Taylor 近似，clamp 結果，gas 可預測

---

### 2.3 transport — 物流層

**職責**：跨星系物資傳送，分三級速度（瞬間/快速/標準）。

**傳送分級（現實映射：空運/快遞/海運）**：

| 等級 | 倍率 | 等待時間 | 現實映射 |
|------|------|----------|----------|
| Instant（瞬間） | ×3.0 | 0 min | FedEx 同日達 / 空運 |
| Express（快速） | ×1.5 | 5 min | 隔日達 / 快遞 |
| Standard（標準） | ×1.0 | 15 min | 標準配送 / 海運 |

加上 courier_market 的實飛（最便宜、時間不定），形成四級物流光譜。

**物件模型**：
- `TransportOrder` (Owned) — 傳送訂單，完成後銷毀

**核心欄位**：

```
TransportOrder {
    id: UID,
    sender: address,
    from_storage: ID,
    to_storage: ID,
    receipt: Option<DepositReceipt>,
    route: vector<u64>,
    fuel_cost: u64,
    danger_snapshot: u64,           // FP_SCALE 格式
    tier: u8,                       // 0=Instant, 1=Express, 2=Standard
    earliest_complete_at: u64,      // created_at + TIER_DELAY[tier]
    status: u8,                     // 0=Created, 1=FuelPaid, 2=Completed
    created_at: u64,
}

const TIER_MULTIPLIER: vector<u64> = [3000, 1500, 1000];  // FP_SCALE
const TIER_DELAY_MS: vector<u64> = [0, 300_000, 900_000]; // 0, 5min, 15min
const MIN_FUEL_COST_PER_WEIGHT: u64 = 10;
const MAX_FUEL_COST_PER_WEIGHT: u64 = 100_000;
```

**運費公式（鏈下計算）**：

```
base_fuel = base_rate × ln(1 + distance) × cargo_weight × (1 + β × max_danger)
fuel_cost = base_fuel × TIER_MULTIPLIER[tier] / FP_SCALE
```

**鏈上驗證**：

```
assert!(fuel_cost >= MIN_FUEL_COST_PER_WEIGHT × cargo_weight, E_FUEL_COST_TOO_LOW);
assert!(fuel_cost <= MAX_FUEL_COST_PER_WEIGHT × cargo_weight, E_FUEL_COST_TOO_HIGH);
```

**公開介面**：

| 函式 | 說明 |
|------|------|
| `create_order(from, to, receipt, route, fuel_cost, danger_snapshot, tier) → TransportOrder` | 建立訂單（驗證 fuel_cost 範圍 + 設定 earliest_complete_at） |
| `pay_fuel(order, fuel: Coin<FUEL>, treasury: &mut FuelTreasuryCap)` | 支付燃料（銷毀 FUEL coin） |
| `complete_transport(order, to_storage, clock) → DepositReceipt` | 完成傳送（assert clock ≥ earliest_complete_at） |
| `cancel_order(order) → DepositReceipt` | 取消（僅限 FuelPaid 前） |

**設計決策**：
- 傳送分三級：`tier` 決定倍率和等待時間。Instant 最貴但零等待，Standard 最便宜但等 15 分鐘
- `complete_transport` 驗證 `clock >= earliest_complete_at`，非 Instant 等級必須等待
- `pay_fuel` 銷毀 FUEL coin（燃料被消耗），與 fuel_station 的 buy_fuel 形成「買燃料 → 用燃料」閉環
- 鏈上驗證 fuel_cost 上下限，防止零成本傳送和前端被劫持的天價收費
- Receipt by value 移入防止雙重提領

**Events**：

```
TransportCreated { order_id, sender, from_storage, to_storage, tier, fuel_cost }
TransportPaid { order_id, fuel_amount }
TransportCompleted { order_id, new_receipt_id }
TransportCancelled { order_id }
```

---

### 2.4 fuel_station — 經濟層

**職責**：燃料自動定價、補貨分潤（O(1) 累加器）、緊缺獎勵、供應商退出。

**物件模型**：
- `FuelStation` (Shared Object) — 燃料站本體
- `StationCap` (Owned) — 站主管理權限，綁定特定 FuelStation
- `SupplierReceipt` (Owned, 持久) — 補貨者分潤憑證

**核心欄位**：

```
FuelStation {
    id: UID,
    storage_id: ID,
    owner: address,
    max_fuel: u64,
    current_fuel: u64,
    base_price: u64,
    alpha: u64,                       // 稀缺係數（FP_SCALE）
    owner_fee_bps: u64,              // ≤ MAX_OWNER_FEE_BPS (5000)
    total_supplied: u64,             // 所有供應商累計補貨總量
    acc_reward_per_share: u64,       // 累計每單位供應量的分潤（O(1) 累加器）
    treasury_cap_id: ID,             // 關聯的 FuelTreasuryCap
}

StationCap {
    id: UID,
    station_id: ID,
}

SupplyRecord {
    amount: u64,                     // 該 supplier 的補貨量
    reward_debt: u64,                // 進場時的 acc_reward_per_share 快照
}

SupplierReceipt {
    id: UID,
    station_id: ID,
    supply_record: SupplyRecord,     // 內嵌分潤記錄
}
```

**定價公式（鏈上執行）**：

```
price = base_price × (FP_SCALE + alpha × (FP_SCALE - current_fuel × FP_SCALE / max_fuel)) / FP_SCALE
```

**分潤邏輯（O(1) 累加器模式，類似 MasterChef）**：

```
每筆售出 revenue：
├── owner_cut    = revenue × owner_fee_bps / BPS_SCALE
└── supplier_pool = revenue - owner_cut
    └── acc_reward_per_share += supplier_pool × FP_SCALE / total_supplied

領取時：
    pending = receipt.supply_record.amount × (acc_reward_per_share - receipt.supply_record.reward_debt) / FP_SCALE

緊缺獎勵：current_fuel < max_fuel × 30% 時，supply_fuel 的 amount 額外 ×1.5 計入 supply_record
```

**公開介面**：

| 函式 | 說明 |
|------|------|
| `create_station(storage, base_price, alpha, owner_fee_bps) → StationCap` | 建站（assert owner_fee_bps ≤ MAX_OWNER_FEE_BPS） |
| `buy_fuel(station, payment, amount, max_price_per_unit) → Coin<FUEL>` | 買燃料（滑點保護 + 更新 acc_reward_per_share） |
| `supply_fuel(station, fuel: Coin<FUEL>) → SupplierReceipt` | 補貨（緊缺時 ×1.5 加權） |
| `add_supply(station, receipt, fuel: Coin<FUEL>)` | 追加補貨到現有 Receipt（避免 Receipt 膨脹） |
| `claim_revenue(station, receipt) → Coin<SUI>` | 領取分潤（O(1) 計算） |
| `withdraw_supplier(station, receipt) → (Coin<SUI>, Coin<FUEL>)` | 供應商退出（領取未領分潤 + 退回未售燃料佔比 + 銷毀 Receipt） |
| `update_pricing(station, cap, base_price, alpha)` | 調整定價 |
| `update_fee(station, cap, owner_fee_bps)` | 調整抽成（assert ≤ MAX_OWNER_FEE_BPS） |
| `current_price(station) → u64` | 查詢當前價格 |
| `fuel_level(station) → (u64, u64)` | 查詢庫存 |

**設計決策**：
- 分潤用 `acc_reward_per_share` 累加器（MasterChef 模式），每次 buy_fuel 只更新一個全局值，O(1) 常數 gas
- `SupplyRecord` 內嵌在 `SupplierReceipt` 中（非 Table），Receipt 轉讓時分潤權一起轉
- `add_supply` 避免同一供應商建立多個 Receipt 導致 state 膨脹
- `withdraw_supplier` 讓供應商可退出（領分潤 + 退燃料），防止 rug pull
- `owner_fee_bps ≤ 5000`（50% 上限），保護供應商
- `FUEL` 代幣由 `fuel_token` module 定義，station 透過 TreasuryCap 鑄造

**Events**：

```
StationCreated { station_id, storage_id, owner, base_price }
FuelPurchased { station_id, buyer, amount, price_paid }
FuelSupplied { station_id, supplier, amount, is_scarce }
RevenueClaimed { station_id, supplier, amount }
SupplierWithdrawn { station_id, receipt_id, fuel_returned, revenue_claimed }
PricingUpdated { station_id, base_price, alpha }
```

---

### 2.5 courier_market — 應用層

**職責**：快遞任務發布/接單/追蹤/結算，雙邊押金，確認期機制。

**物件模型**：
- `CourierContract` (Shared Object) — 快遞合約
- `CourierBadge` (key only, 不可轉讓) — 快遞員代提貨授權

**核心欄位**：

```
CourierContract {
    id: UID,
    client: address,
    courier: Option<address>,
    from_storage: ID,
    to_storage: ID,
    cargo_receipt: Option<DepositReceipt>,  // by value 鎖入
    reward: u64,
    client_deposit: Balance<SUI>,
    courier_deposit: Balance<SUI>,
    min_courier_deposit: u64,               // 強制 >= cargo.value
    cargo_value: u64,                       // 快照，用於驗證押金
    route: vector<u64>,
    status: u8,                    // 0=Open, 1=Accepted, 2=InDelivery, 3=PendingConfirm, 4=Delivered
    deadline: u64,                 // 全程 deadline
    pickup_deadline: u64,          // 接單後取貨的 sub-deadline
    confirm_deadline: u64,         // 送達後確認期 deadline
    created_at: u64,
}

CourierBadge {
    id: UID,
    contract_id: ID,
    courier: address,
}
```

**生命週期與資金流**：

```
[Open]            發單人鎖入 reward + cancel_penalty → client_deposit
                  cargo_receipt by value 移入
                  min_courier_deposit 自動設為 max(用戶指定值, cargo_value)
    ↓
[Accepted]        快遞員鎖入 ≥ min_courier_deposit → courier_deposit
                  獲得 CourierBadge
                  pickup_deadline 啟動（例如 2 小時）
    ↓
[InDelivery]      快遞員持 CourierBadge 觸發 pickup_and_deliver
                  系統透過 WithdrawAuth hot-potato 從 from_storage 提貨
                  → 直接存入 to_storage（同一 PTB，courier 不持有 Receipt）
    ↓
[PendingConfirm]  等待客戶確認（confirm_deadline，例如 24 小時）
                  客戶可 confirm_delivery 或 raise_dispute
    ↓
[Delivered]       結算：
                  reward → 快遞員（扣站主 fee）
                  courier_deposit → 退還快遞員
                  client_deposit 剩餘 → 退還發單人
                  CourierBadge → 銷毀
                  快遞員獲得 ReporterCap（透過 OracleCap 授權發行）
```

**超時處理（permissionless，含 0.5% keeper bounty）**：

| 階段 | 超時結果 |
|------|----------|
| Open 超過 deadline | 發單人取回全部 client_deposit + cargo_receipt |
| Accepted 超過 pickup_deadline | courier_deposit 賠給發單人 + cargo_receipt 歸還 |
| InDelivery 超過 deadline | courier_deposit 賠給發單人（貨物已在 to_storage） |
| PendingConfirm 超過 confirm_deadline | **自動視為確認**，進入 Delivered 結算 |

**爭議處理（Hackathon 簡化版）**：

```
[PendingConfirm] 客戶 raise_dispute →
    [Disputed] 雙方資金凍結
    → OracleCap 持有者調用 resolve_dispute(contract, oracle_cap, ruling)
    → ruling: 0 = 客戶勝（courier_deposit 賠客戶）, 1 = 快遞員勝（正常結算）
    → 或 2 = 各退一半 (split)
```

**公開介面**：

| 函式 | 說明 |
|------|------|
| `create_contract(from, to, receipt, reward, cancel_penalty, min_courier_deposit, route, deadline) → ID` | 發布任務（assert min_courier_deposit >= cargo.value） |
| `accept_contract(contract, deposit, clock) → CourierBadge` | 接單（設 pickup_deadline） |
| `pickup_and_deliver(contract, badge, from_storage, to_storage, clock)` | 取貨+存入目的地（hot-potato WithdrawAuth，原子性，courier 不持有 Receipt） |
| `confirm_delivery(contract, clock)` | 客戶確認收貨 → 進入結算 |
| `raise_dispute(contract, clock)` | 客戶發起爭議（僅 PendingConfirm） |
| `resolve_dispute(contract, oracle_cap, ruling)` | OracleCap 仲裁 |
| `settle(contract, threat_map, oracle_cap, clock) → (Coin<SUI>, ReporterCap)` | 結算（Delivered 狀態觸發） |
| `cancel_by_client(contract) → (DepositReceipt, Coin<SUI>)` | 發單人取消（僅 Open） |
| `claim_timeout(contract, clock) → Coin<SUI>` | 超時清算（0.5% keeper bounty） |

**設計決策**：
- **Hot-potato 代提**：`pickup_and_deliver` 在同一 PTB 中建立 `WithdrawAuth` → 調用 `storage::withdraw_with_auth` → 調用 `storage::deposit` 到目的 Storage。courier 全程不持有 Receipt 或 Cargo，消除「courier 繞過合約直接提貨」的攻擊
- `min_courier_deposit` 強制 `>= cargo.value`，確保 courier 經濟激勵永遠傾向完成任務
- 合併 PickedUp + InTransit → `InDelivery`（原 InTransit 無觸發函式，為死狀態）
- 加 `PendingConfirm` 確認期（現實映射：簽收確認）
- `pickup_deadline` sub-deadline 防止 accept 後不取貨的 griefing
- `confirm_deadline` 超時自動確認，防止客戶不確認鎖死快遞員資金
- 爭議由 OracleCap 仲裁（Hackathon 簡化），未來可改為 DAO 投票
- `ReporterCap` 透過 `threat_oracle::issue_reporter_cap(oracle_cap, ...)` 發行，courier_market 需要 OracleCap reference

**Events**：

```
ContractCreated { contract_id, client, from_storage, to_storage, reward, deadline }
ContractAccepted { contract_id, courier, deposit_amount }
CargoPickedUpAndDelivered { contract_id, from_storage, to_storage }
DeliveryConfirmed { contract_id }
DisputeRaised { contract_id, client }
DisputeResolved { contract_id, ruling }
ContractSettled { contract_id, courier_reward, reporter_cap_id }
TimeoutClaimed { contract_id, stage, keeper, bounty }
```

---

## 3. 鏈上 vs 鏈下分工

| 邏輯 | 位置 | 原因 |
|------|------|------|
| 燃料定價 `base × (1 + α × ratio)` | 鏈上 | 整數四則運算，Gas 低 |
| 分潤累加器 `acc_reward_per_share` | 鏈上 | O(1) 整數運算，需要原子性 |
| 押金鎖定 / 退還 / 賠付 | 鏈上 | 資金操作必須鏈上 |
| 倉儲費結算 | 鏈上 | 時長 × 費率，整數乘除 |
| 傳送等級等待時間 | 鏈上 | `assert clock >= earliest_complete_at` |
| 運費上下限校驗 | 鏈上 | `MIN/MAX_FUEL_COST_PER_WEIGHT × weight` |
| 運費精確公式 `ln() × weight × danger × tier` | 鏈下 | 涉及浮點、對數 |
| 路徑規劃 / 最短路 | 鏈下 | 圖算法不適合鏈上 |
| 星系座標 / 距離計算 | 鏈下 | EVE 座標為有符號大數 |
| 危險指數時間衰減 | 鏈上 | 三階 Taylor 定點數近似 |

---

## 4. 安全考量

### 4.1 已解決的攻擊向量

| 攻擊 | 防禦 |
|------|------|
| 零成本傳送 | `MIN_FUEL_COST_PER_WEIGHT` 鏈上校驗 |
| 天價運費（前端劫持） | `MAX_FUEL_COST_PER_WEIGHT` 鏈上上限 |
| DepositReceipt 雙重提領 | Receipt by value 移入 Order/Contract |
| Courier 繞過合約直接提貨 | Hot-potato `WithdrawAuth` 模式，courier 不持有 Receipt |
| Courier 偷貨（貨值 > 押金） | 強制 `min_courier_deposit >= cargo.value` |
| 任意 Cap 改任意物件 | 所有 Cap 內含目標 ID，操作時 assert 匹配 |
| SupplierReceipt 轉讓後分潤錯亂 | SupplyRecord 內嵌 Receipt，隨 Receipt 轉移 |
| 買燃料被前跑 | `max_price_per_unit` 滑點保護 |
| 站主 rug pull 供應商 | `owner_fee_bps ≤ 50%` + `withdraw_supplier` 退出機制 |
| O(N) 分潤 gas 爆炸 | `acc_reward_per_share` O(1) 累加器 |
| ReporterCap 刷情報 | key only（不可轉讓）+ 冷卻 + missions_completed 權重 + revoke_reporter |
| 超時合約無人清算 | 0.5% keeper bounty |
| Storage 容量永久佔滿 | `admin_reclaim` 30 天 + live_receipts 檢查 |
| Accept 後不取貨 griefing | `pickup_deadline` sub-deadline |
| 客戶不確認鎖死快遞員 | `confirm_deadline` 超時自動確認 |

### 4.2 已知限制（Hackathon 階段可接受）

| 限制 | 影響 | 未來方案 |
|------|------|----------|
| 運費無精確鏈上驗證 | 理論上可低報（但有下限） | OracleCap 簽章驗證 |
| ThreatMap 單一 Shared Object | 高併發排序延遲 | 按星系區域分片 |
| 爭議仲裁中心化 | OracleCap 單點仲裁 | DAO 投票仲裁 |
| Cargo.value 自行申報 | 可低報價值壓低押金要求 | 鏈上價格預言機 |
| FuelStation 1:1 Storage 未強制 | 可建多個 station 指向同一 storage | 加 registry / dynamic field 檢查 |

---

## 5. 前端模組（Hackathon 範圍）

### 5.1 物流任務看板
- 顯示所有 Open 的 CourierContract
- 篩選：按目的地、報酬、危險等級
- 發布任務 / 接單操作
- 傳送等級選擇器（Instant / Express / Standard / Courier）

### 5.2 燃料站管理介面
- 站主：調整定價參數、查看營收
- 補貨者：補貨、領取分潤、退出
- 買家：購買燃料（含滑點設定）、查看價格走勢

### 5.3 燃料熱度圖
- 星系地圖上顯示各燃料站庫存/價格
- 危險指數熱度圖疊加
- 最佳補給路線建議（鏈下算）

---

## 6. Event 總覽

所有 module 的 Event 定義（供前端索引）：

| Module | Events |
|--------|--------|
| storage | `StorageCreated`, `CargoDeposited`, `CargoWithdrawn`, `AdminReclaimed` |
| threat_oracle | `ThreatUpdated`, `IncidentReported`, `ReporterRevoked` |
| transport | `TransportCreated`, `TransportPaid`, `TransportCompleted`, `TransportCancelled` |
| fuel_station | `StationCreated`, `FuelPurchased`, `FuelSupplied`, `RevenueClaimed`, `SupplierWithdrawn`, `PricingUpdated` |
| courier_market | `ContractCreated`, `ContractAccepted`, `CargoPickedUpAndDelivered`, `DeliveryConfirmed`, `DisputeRaised`, `DisputeResolved`, `ContractSettled`, `TimeoutClaimed` |

---

## 7. 未來擴展方向（不在 Hackathon 範圍）

- 情報付費查詢市場（ReporterCap 持有者販售情報）
- 能源借貸（以未來產量抵押）
- 碳排放 / 能源稅機制
- 封鎖制裁（DAO 投票禁止特定星系貿易）
- 拆分為多 Package（已預留 public 介面）
- OracleCap 簽章驗證運費防作弊
- ThreatMap 分片（按星系區域）
- 燃料品質分級（regular / premium）
- 多段運輸中轉站支援
- DAO 仲裁取代 OracleCap 中心化仲裁
