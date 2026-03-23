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
├── guild (Guild, GuildMemberCap)              ← v3 new
├── storage (Cargo, DepositReceipt, WithdrawAuth, AdminCap, +guild_id, +encrypted_coords)
├── threat_oracle (ThreatMap, OracleCap, ReporterCap)
├── transport (TransportOrder, uses storage + fuel)
├── fuel_station (FuelStation, AMM pricing, uses storage + fuel)
├── courier_market (CourierContract, CourierBadge, +GuildBonusInfo, uses storage + threat_oracle + guild)
└── seal_policy (seal_approve_guild_member, seal_approve_courier)  ← v3 new
```

## 測試統計 (v3)
| Module | Unit | Monkey | Integration | Total |
|--------|------|--------|-------------|-------|
| fuel | 2 | 0 | - | 2 |
| storage | 12 | 12 | - | 24 |
| threat_oracle | 6 | 7 | - | 13 |
| transport | 7 | 6 | - | 13 |
| fuel_station | 8 | 7 | - | 15 |
| courier_market | 15 | 12 | - | 27 |
| guild | 5 | 12 | - | 17 |
| seal_policy | 7 | 0 | - | 7 |
| **integration** | - | - | 18 | 18 |
| **Total** | **62** | **56** | **18** | **138** |

## Contract v3 Implementation (2026-03-23)

### 新增模組
- **guild.move**: Guild shared object + GuildMemberCap (key-only, non-transferable)
  - EPascalCase error codes（新 module 風格）
  - `test_fill_guild_to_capacity` test-only helper 用 `sui::address::from_u256` 動態生成地址
- **seal_policy.move**: entry functions for Seal decrypt approval
  - `seal::approve(id)` 是 TODO — Seal SDK dependency 待後續加入
  - Access control 邏輯完整（guild member + courier badge）

### 修改模組（全部 dynamic_field 擴展，upgrade safe）
- **storage.move**: `GuildIdKey` (guild_id), `EncryptedCoordsKey` (encrypted coords), `withdraw_as_guild_member` (30% discount), `create_private_storage` + `share_storage`
- **courier_market.move**: `GuildBonusKey`/`GuildBonusInfo`, `create_contract_with_guild_bonus`, `settle_as_guild_member`, dynamic_field cleanup on settle/resolve_dispute/claim_timeout/cancel_by_client
- **constants.move**: `guild_fee_discount_bps(3000)`, `max_guild_members(100)`, `max_guild_name_length(128)`

### 已知限制
- SUI test framework 不支持跨 tx 把 owned object 轉為 shared — 用 `#[test_only]` helper workaround
- `#[error]` attribute 與 `expected_failure(abort_code = ...)` 不相容 — guild.move 用 EPascalCase 但無 `#[error]`
- Seal SDK 整合待完成（entry function signature 可能需調整 `id: vector<u8>` 參數）

### Upgrade 注意事項
- 所有修改在 compatible upgrade 限制內
- courier_market 的 4 個刪除 UID 的函式都加了 `mut contract` + dynamic_field cleanup
- 新增 3 個 getter: `badge_contract_id`, `status_accepted`, `status_pending_confirm`

---

## Frontend dApp Brainstorming (2026-03-23) — 進行中

### 設計決策（已確認）

**1. 目標使用者：所有玩家**
- 每個玩家建立自己的 Storage（owned object）
- Bounty Board 讓玩家廣播運送需求，其他玩家接單
- 雙方質押代幣後才揭露 Storage 座標

**2. Owned → Shared 轉換（不可逆）**
- Storage 預設為 owned object（只有自己用）
- 玩家決定開放 → 呼叫 `share_storage` → 永久轉 shared（SUI 限制，不可逆）
- 符合 EVE Frontier 遊戲精神：開放是有意義的永久決策
- Owner 獲得固定手續費分潤

**3. Access Control 三層模型**
| 角色 | Storage 存取 | 條件 |
|------|-------------|------|
| Owner | 完全控制 | 永遠 |
| 公會成員 | 可使用（折扣手續費） | Storage 已轉 shared + guild_id 匹配 |
| 非公會玩家 | 只能透過 Bounty 接單運送 | Storage 已轉 shared + 持有 CourierBadge |

**4. 公會系統**
- Storage 存 `guild_id: Option<ID>`，由 owner 用 AdminCap 更新
- 換公會時 → 更新 guild_id → 舊成員立刻失去存取，新成員立刻獲得
- GuildMemberCap 做本地驗證，Guild shared object 做 admin 管理
- 公會權限管理不在 scope 內（簡化）

**5. Bounty 獎勵差異**
- 公會成員接單 → 獲得完整獎勵
- 非公會接單 → 獎勵稍少，差額退回 Bounty 發起者
- 激勵加入公會，同時不完全排斥外部玩家

**6. Dark Forest + SUI Seal（完整整合）**
- Storage 座標不存明文，用 SUI Seal 加密存鏈上
- 兩層 Seal policy：
  - 公會成員 → `policy: has_guild_member_cap(guild_id)` → 隨時可解密同公會 Storage 座標
  - Bounty 接單者 → `policy: has_courier_badge(contract_id)` → 雙方質押完成後才能解密
- 前端完整整合 Seal SDK（不用 placeholder）

**7. 技術棧（EVE Frontier 官方）**
- React + Vite + TypeScript
- `@evefrontier/dapp-kit` (封裝 wallet、GraphQL、smart object hooks)
- `@mysten/dapp-kit-react` + `@mysten/sui`
- Radix UI（EVE scaffold 預設）
- pnpm（scaffold 指定）
- 參考 scaffold: `https://github.com/evefrontier/builder-scaffold`
- 嵌入遊戲內瀏覽器：`?tenant=utopia&itemId=...`
- 外部瀏覽器也可獨立開啟

**8. 前端頁面（全部保留）**
1. Dashboard — 我的 Storage 列表、Cargo 清單
2. Star Map — 星系地圖視覺化（加密座標解密後顯示）
3. Bounty Board — 運送需求列表，接單/開單
4. Transport — 自運介面（跨星系傳送到自己的 Storage）
5. Fuel Station — 買/賣 FUEL、價格曲線
6. Guild — 建會、加入、公會 Storage 共享
7. Threat Map — 星系危險指數視覺化

### Data Layer 分析

**eve-eyes indexer（EVE 世界資料）**
- Endpoint: `https://eve-eyes.d0v.xyz`
- Auth: `x-api-key: <REDACTED>`
- `GET /api/indexer/transaction-blocks` — 交易紀錄（filter: network, senderAddress, status, digest, checkpoint）
- `GET /api/indexer/move-calls` — Move call 紀錄（filter: packageId, moduleName, functionName, senderAddress）
- Pages 1-3 公開，page 4+ 需 auth
- **重要**：只索引 EVE world contracts（`0xd12a70c...`），不索引我們的 AstroLogistics package

**資料來源 mapping**
| 資料需求 | 來源 |
|---------|------|
| 星系座標/constellation | eve-eyes indexer（EVE world data） |
| 玩家角色/船隻 | eve-eyes + EVE dApp Kit |
| 我們的合約即時狀態 | SUI RPC / GraphQL 直讀 shared objects |
| 我們的合約歷史事件 | SUI Events API (`suix_queryEvents`) |
| FUEL 價格歷史 | SUI Events → 前端聚合 |
| Courier 信譽統計 | SUI Events → 按 address 聚合 settle/dispute |

### 合約需要的修改（新 chat 處理）

1. **Storage module**：
   - 新增 `guild_id: Option<ID>` field（需 upgrade）
   - 新增 `set_storage_guild(storage, cap, guild_id)` function
   - Owned → Shared 轉換機制（`share_storage` function）
   - 公會成員折扣手續費邏輯

2. **Guild module（新 module）**：
   - `Guild` shared object + `GuildMemberCap` owned object
   - 建會、加入、退出、踢人

3. **courier_market module**：
   - `guild_discount_bps` field on CourierContract
   - settle 時根據 courier 公會身份調整獎勵

4. **SUI Seal 整合**：
   - Storage 座標加密存儲
   - Seal policy：公會成員 / CourierBadge 持有者可解密

### Brainstorming 狀態
- [x] 目標使用者
- [x] Owned → Shared 轉換
- [x] Access Control / Guild 系統
- [x] Bounty 獎勵機制
- [x] Dark Forest + Seal
- [x] 技術棧
- [x] 頁面範圍
- [x] Data Layer 分析
- [x] 設計 spec 撰寫 → 直接寫 implementation plan（brainstorming 已足夠詳細）
- [x] Plan review (generic + move-code-quality + security-guard + red-team)
- [x] Implementation plan — `docs/superpowers/plans/2026-03-23-plan4-contract-v3-guild-seal.md`
- [ ] Plan 執行（開新 chat）

---

## Contract v3 Plan Review Summary (2026-03-23)

### Plan Review 結果
- **Generic reviewer**: 3 High + 3 Medium → 全部修復
- **Move Code Quality**: 2 Critical + 11 improvements → 新 module 採用 Move 2024 style
- **Security Guard**: capability usage audit PASS
- **Red Team (8 rounds)**: 1 exploited + 3 suspicious + 5 defended

### Red Team Accepted Risks
- **RT-V3-1**: Guild revocation griefing — leader 可在 settle 前 remove courier，courier 失去 guild_bonus 但保留 base reward。Hackathon accept，mainnet 需 snapshot membership at accept time。
- **RT-V3-2**: Stale GuildMemberCap 累積 — SUI owned object 無法遠端刪除。提供 `destroy_stale_cap` 讓用戶自行清理。

### Move Code Quality 決策
- 新 module (guild.move, seal_policy.move): 採用 EPascalCase error codes + `#[error]` + method syntax + `..` destructure
- 舊 module 修改 (storage.move, courier_market.move): 保持現有 SCREAMING_SNAKE_CASE 風格一致性
- 全面風格統一延至 v4

---

## 文件位置
- Spec: `docs/superpowers/specs/2026-03-20-astrologistics-design.md`
- Plan 1: `docs/superpowers/plans/2026-03-21-plan1-foundation-layer.md`
- Plan 2: `docs/superpowers/plans/2026-03-21-plan2-logistics-economy-layer.md`
- Plan 3: `docs/superpowers/plans/2026-03-21-plan3-courier-market.md`
- Plan 4 (v3): `docs/superpowers/plans/2026-03-23-plan4-contract-v3-guild-seal.md`
- Plan 5 (frontend): `docs/superpowers/plans/2026-03-23-plan5-frontend-dapp.md`
- Constitution: `../../Constitution/EVE_Frontier_Project_Constitution.md`

---

## Frontend Plan 5 Review Summary (2026-03-23)

### Review Results
- **3 HIGH** + **7 MEDIUM** + **7 LOW** → all fixed

### Key Fixes
| Issue | Problem | Fix |
|-------|---------|-----|
| H-1 | CourierContract is shared, `getOwnedObjects` won't find it | Changed to `queryEvents(ContractCreated)` |
| H-2 | Status 3='Settled' wrong, statuses 5/6 don't exist | Fixed to `0=Open, 3=Delivered`, removed 5/6 |
| H-3 | `tx.pure.string()` for `vector<u8>` | Added comment explaining BCS wire format compatibility |
| M-3 | `cancelPenalty` field doesn't exist on-chain | Changed to `clientDeposit` (combined balance) |
| M-4 | `Guild.members` is Table, not array | Changed to `memberTableId` + getDynamicFields |
| L-3/4 | Missing PTB builders | Added `buildUpdateFeeRate` + `buildSetEncryptedCoords` |

### Plan Structure
- 19 tasks, ~90 steps
- Tech stack: React 19 + Vite 8 + @mysten/dapp-kit-react ^2.0.1 + Tailwind 4.2
- Reference scaffold: `../../Bounty_Escrow_Protocol/frontend/`
- 8 pages: Dashboard, StorageDetail, BountyBoard, ContractDetail, FuelStation, Transport, Guild, ThreatMap

### SUI Frontend Gotchas (for implementation)
- **Type refs**: `ORIGINAL_PACKAGE_ID` for struct types, `PACKAGE_ID` for function calls
- **Shared objects**: CourierContract, Guild, Storage (after share), FuelStation, ThreatMap — use `getObject` not `getOwnedObjects`
- **Owned objects**: AdminCap, GuildMemberCap, CourierBadge, SupplierReceipt, TransportOrder, DepositReceipt — use `getOwnedObjects`
- **Dynamic fields**: guild_id on Storage, GuildBonusInfo on CourierContract, OwnerFees on FuelStation, Guild.members Table — need `getDynamicFieldObject`/`getDynamicFields`
- **Auto-transfer**: SUI runtime auto-transfers returned objects with `key+store` to tx sender
- **Event discovery**: CourierContract IDs found via `queryEvents(ContractCreated)`, not object queries
