# AstroLogistics Network — Notes

## Testnet Deployment (2026-03-21)

### Deployment Artifacts
| Item | ID |
|------|----|
| **PackageID** | `0x564d32c9ce29b9f75c1821311aded4b84ee6d912c39e434309b9803e19f5f25c` |
| **UpgradeCap** | `0x9168f9fa6394a46cdb2f415f1845dbb8277ece93787a55af70c5772203c8d877` |
| **FuelTreasuryCap** | `0x077592721b6425e85c5c2cfbb8bef7a479719e07b83878a30aa6c07c1428bfbc` |
| **MetadataCap** | `0xcf227ade195ee4d367c633e2a991453f46350348cad1f1fb820fb5180eac2f8d` |
| **Tx Digest** | `6L9UWDodHpAxyUo8WoimgLwhE2BRfyRcFhyv5ZvKWD5Y` |
| **Network** | testnet |
| **Deployer** | `0x1509b5fdf09296b2cf749a710e36da06f5693ccd5b2144ad643b3a895abcbc4c` |
| **Gas** | ~0.176 SUI |
| **Modules** | constants, courier_market, fuel, fuel_station, storage, threat_oracle, transport |

### Post-Deploy 注意事項
- UpgradeCap 目前在 deployer 地址，mainnet 前應轉到 multisig
- FuelTreasuryCap 控制 FUEL mint/burn，是高權限物件
- MetadataCap 控制 FUEL coin metadata 修改

## Testnet Initialization (2026-03-21)

### Init Artifacts (via `scripts/src/init-testnet.ts`)
| Item | ID |
|------|----|
| **ThreatMap** (shared) | `0xed6223a66967c994c781139af5bfe779a75309bbe6aea365ea00f58d68504f71` |
| **OracleCap** | `0xf3fd216ef4a86d818ba2aec607735f1ee079ffe40810d1f4c8de874b85cccd35` |
| **Storage1** (shared, system_id=1) | `0x1fcf2620712dad4745c8c2e4be10e5e3ffc6688b8a6c5dd8f5581d6223e7614c` |
| **Storage2** (shared, system_id=2) | `0x2a97c1b681a0420e8023e18b24230e23fb18cbfbc1962f06ab9edc24f59d7bcb` |
| **AdminCap1** | `0x60b9678a56c9cfa20e249434f958fbee8a9a1307acf8bca01ea51654ad63c1c3` |
| **AdminCap2** | `0x910553b99d112e29e2d73f4c0337d1a4085afc4997570a68b78d28189edcce13` |
| **FuelStation1** (shared) | `0x6d9f65c5a91e9d3f5b3f44d1bb0d6cff9fa9d96233973691e0f7f98479652238` |
| **FuelStation2** (shared) | `0xecacfc19504df97bbbe164e499902d4fd7e015332fe54bc02aa0974c0f7eb3d6` |
| **StationCap1** | `0x34d473c59e1392a17d4f18951913fb823ad26e2a4f80b43f6025026d601467b0` |
| **StationCap2** | `0x9ae8070f65295a37176fece37548f9945a67f144060b5174383d0920a95b387d` |
| **FUEL Coin** (1000 FUEL) | `0xd224aa0864e16457ea10affc198bfc11c8beea78db79535f377ed40786cec16c` |
| TX1 Digest | `Cm3A48quBugu6SR52hakqLEeZ6cZDvcopC2BCsMGmkHZ` |
| TX2 Digest | `AHJfQP2T3QcTPAjUPm6cmreNPfH6pt8sS5FAvt3u9Rxa` |

### Init Parameters
- decay_lambda: 100 (0.1x)
- Storage1: system_id=1, max_capacity=1M, fee=2%
- Storage2: system_id=2, max_capacity=500K, fee=3%
- FuelStation: base_price=100, alpha=1.0x, owner_fee=5%
- FUEL mint: 1000 FUEL (1e12 raw, 9 decimals)

### Smoke Test Results (6/6 PASS)
| # | Test | Digest |
|---|------|--------|
| 1 | Deposit cargo → Storage1 | `GWWHkyVZ...` |
| 2 | Supply FUEL → FuelStation1 | `FhgtzLZE...` |
| 3 | Buy FUEL (SUI→FUEL) | `6UrPJXq1...` |
| 4 | Create transport + pay fuel | `78PqbWK7...` |
| 5 | Complete transport (S1→S2) | `CWDUjj7b...` |
| 6 | Withdraw cargo from S2 | `2hN1RYwc...` |

### Script 位置
- Init: `scripts/src/init-testnet.ts`
- Smoke: `scripts/src/smoke-test.ts`
- Object IDs: `scripts/src/testnet-objects.json`

## Security Audit (2026-03-22)

### CRITICAL
- **C-1 Unscoped OracleCap**: `create_threat_map()` is `public fun` — anyone can mint an OracleCap and use it to call `settle()` / `resolve_dispute()`. Complete dispute bypass.
  - **Fix**: Gate `create_threat_map` behind admin cap, or add `threat_map_id` to OracleCap and verify in courier_market.

### HIGH
- **H-1**: `resolve_dispute()` missing `badge.contract_id` check — wrong badge can be used
- **H-2**: `buy_fuel()` `price * amount` overflow (no u128)
- **H-3**: Owner fee trapped in `revenue_pool` — no `claim_owner_fees()` function
- **H-4**: `resolve_dispute(ruling=2)` sends receipt to courier, should go to client
- **H-5**: `deposit()` allows zero-value cargo — breaks courier economic model, enables ReporterCap farming

### MEDIUM
- **M-1**: `max_fuel` never decreases on `withdraw_supplier` — AMM price inflation
- **M-2**: Scarce bonus gaming (self-dealing supplier/buyer)
- **M-3**: `pickup_and_deliver()` no deadline check
- **M-4**: `accept_contract()` no deadline check for expired contracts
- **M-5**: `complete_transport()` no sender auth check

### 修復完成 (2026-03-22)
所有 P0/P1/P2 fixes 已實施，97 tests PASS。

#### 修復摘要
| ID | 修法 | 模組 |
|----|------|------|
| C-1 | `create_threat_map()` → abort (disabled), 加 `#[test_only]` helper | threat_oracle |
| H-1 | `resolve_dispute()` 加 `badge.contract_id` check | courier_market |
| H-2 | `buy_fuel()` 用 u128 防 overflow | fuel_station |
| H-3 | `dynamic_field` 追蹤 owner_cut, 加 `claim_owner_fees()` | fuel_station |
| H-4 | `resolve_dispute(ruling=2)` receipt 改送 client | courier_market |
| H-5 | `deposit()` 拒絕 weight=0 或 value=0 | storage |
| M-1 | `withdraw_supplier()` 減少 `max_fuel` | fuel_station |
| M-3 | `pickup_and_deliver()` 加 deadline check | courier_market |
| M-4 | `accept_contract()` 拒絕已過期 contract | courier_market |
| M-5 | `complete_transport()` 加 sender auth | transport |
| M-2 | Accepted risk — scarce bonus gaming | — |

#### Upgrade 注意事項
- 所有修復都在 compatible upgrade 限制內（不改 struct layout、不改 public fn signature）
- H-3 用 `dynamic_field` 繞過 struct freeze 限制
- C-1 用 abort 禁用 function，加 `#[test_only]` 保持 test 可用
- Upgrade 後需重新跑 smoke test（init 物件已存在，不需重建）
- 新增 `claim_owner_fees()` 需要前端/script 呼叫才能取回 owner fee

---

## Red Team Notes (Pre-Implementation, 2026-03-20)

### Critical Findings (已修復)
1. **admin_reclaim 設計缺陷** → 修正：live_receipts Table<ID, bool> 追蹤 receipt 存活狀態
2. **ReporterCap Sybil Farm** → 修正：min_contract_reward (H8)，但仍需觀察是否足夠
3. **Timeout Griefing** → 修正：MIN_DEADLINE_MS + pickup_deadline cap (H7)

### High Severity (已修復)
- owner_fee_bps capped at 50% (constants::max_owner_fee_bps)
- fuel_cost bounds: min/max per weight unit
- alpha capped at max_alpha (10x)

### Medium Severity (已修復)
- courier min_courier_deposit >= cargo_value (enforced)
- transport order: cancel_order only for Created status
- PendingConfirm + dispute + timeout 機制

### 未完全解決 / 需持續觀察
- storage capacity DoS（無 deposit fee，可用 junk 填滿）— 目前靠 weight > 0 限制
- ReporterCap farming 門檻（min_contract_reward=1000）是否足夠？mainnet 前需評估
- transport Created status 無 timeout — 依賴 DepositReceipt 被鎖定在 order 中，cancel 可回收

---

## 關鍵設計決策

- **瞬間傳送合法**：鏈上資產是數據，「傳送」只是改欄位。憲法禁止的是「免費瞬移」，不是瞬移本身。燃料成本 = 等價交換。
- **Hot-potato WithdrawAuth**：courier 永不持有 DepositReceipt，消除「courier 繞過合約直接提貨」攻擊
- **O(1) 分潤**：用 MasterChef 累加器模式 (acc_reward_per_share)，避免 O(N) 迭代
- **live_receipts keyed by cargo_id**：讓 admin_reclaim 能查詢特定 cargo 是否仍有活躍 receipt
- **ReporterCap key only**：不可轉讓，綁定地址 + 冷卻 + missions_completed 權重
- **remove_cargo_for_transport**：package-level fn，transport/courier 共用，不走 withdraw（不收 fee）

## 架構總覽

```
constants (pure fns)
├── fuel (FUEL coin, OTW)
├── storage (Cargo, DepositReceipt, WithdrawAuth, AdminCap)
├── threat_oracle (ThreatMap, OracleCap, ReporterCap)
├── transport (TransportOrder, uses storage + fuel)
├── fuel_station (FuelStation, AMM pricing, uses storage + fuel)
└── courier_market (CourierContract, CourierBadge, uses storage + threat_oracle)
```

## 測試統計
| Module | Unit | Monkey | Integration | Total |
|--------|------|--------|-------------|-------|
| fuel | 2 | 0 | - | 2 |
| storage | 9 | 10 | - | 19 |
| threat_oracle | 6 | 7 | - | 13 |
| transport | 7 | 6 | - | 13 |
| fuel_station | 8 | 7 | - | 15 |
| courier_market | 12 | 12 | - | 24 |
| **integration** | - | - | 12 | 12 |
| **Total** | **44** | **42** | **12** | **97** |

## 文件位置
- Spec: `docs/superpowers/specs/2026-03-20-astrologistics-design.md`
- Plan 1: `docs/superpowers/plans/2026-03-21-plan1-foundation-layer.md`
- Plan 2: `docs/superpowers/plans/2026-03-21-plan2-logistics-economy-layer.md`
- Plan 3: `docs/superpowers/plans/2026-03-21-plan3-courier-market.md`
- Constitution: `../../Constitution/EVE_Frontier_Project_Constitution.md`
