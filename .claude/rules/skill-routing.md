# SUI Skill Routing

- 本檔只在處理 Sui Move / 合約相關工作時適用。
- 遇到對應任務時，**必須先調用對應的 skill**，不要跳過直接寫 code。

## 路由表

| 任務 | Skill |
|------|-------|
| Move 合約開發 | `sui-developer`（含品質檢查） |
| Move 測試 | `sui-tester`（含 gas tracking） |
| SUI 架構設計 | `sui-architect` |
| 部署（devnet→testnet→mainnet） | `sui-deployer` |
| 安全審計 | `sui-security-guard` + `sui-red-team` |
| Move 程式碼品質檢查 | `move-code-quality` |
| SUI SDK/CLI 疑問 | `sui-docs-query`（先查最新文件，不依賴過期資訊） |
| Seal 加密 | `sui-seal` |
| Kiosk NFT | `sui-kiosk` |
| DeepBook DEX | `sui-deepbook` |
| 鏈上合約反編譯/分析 | `sui-decompile` |
| SuiNS 域名 | `sui-suins` |
| 跨鏈橋接 | `sui-nautilus` |
| Gas 分析優化 | `sui-dev-agents:gas` |

## 複合任務（有 fullstack 時追加）

| 任務 | Skill |
|------|-------|
| 前端 dApp | `sui-frontend` + `sui-ts-sdk` |
| zkLogin | `sui-zklogin` |
| Passkey | `sui-passkey` |
| 前後端整合 / TS type generation | `sui-fullstack-integration` |

## Build & Test

- Move 改動後必跑 `sui move test` 再 commit
- 部署前跑 `sui move build` 確認無錯誤

## Red Team (Move Contracts)

- 核心合約（auth、金流、access control）→ 用 `sui-red-team` skill
- 列出 ≤5 攻擊向量：access control bypass、integer overflow、object manipulation、economic exploit、DoS
