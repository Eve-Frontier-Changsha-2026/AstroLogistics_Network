# AstroLogistics Network — 手動 QA 測試計畫

> 以使用者實際操作情境為主的測試步驟。每個場景模擬真實玩家行為。

## 前置條件

| 項目 | 說明 |
|------|------|
| 網路 | SUI Testnet |
| 錢包 | 安裝 SUI Wallet 瀏覽器擴充套件，已切換到 Testnet |
| 餘額 | 帳戶至少有 1 SUI（測試 gas） |
| 部署 | 合約已部署到 testnet（v3 PackageID `0x3407...706a`） |
| 初始化 | ThreatMap、Storage x2、FuelStation x2、FUEL 已初始化 |
| 前端 | `pnpm dev` 啟動在 `http://localhost:5173` |

### Testnet 已部署的 Shared Objects

| 物件 | ID |
|------|----|
| Storage 1 | `0x1fcf...614c` |
| Storage 2 | `0x2a97...7bcb` |
| FuelStation 1 | `0x6d9f...2238` |
| FuelStation 2 | `0xecac...b3d6` |
| ThreatMap | `0xed62...4f71` |
| Guild | `0x6b1d...75c4` |

---

## 測試帳戶建議

| 角色 | 用途 | 需求 |
|------|------|------|
| **帳戶 A**（Storage Owner） | 建 Storage、存貨、發 Bounty | 持有 AdminCap、SUI、FUEL |
| **帳戶 B**（Courier） | 接單、運送、領獎金 | 持有 SUI（做押金） |
| **帳戶 C**（Guild Leader） | 建公會、管理成員 | 持有 SUI |

> 可用同一個錢包切換帳戶，或用不同瀏覽器。

---

## 場景 1：首次進入 — 錢包連接

### 1.1 未連接錢包時的畫面

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 開啟 `http://localhost:5173` | 看到 Dashboard 頁面 |
| 2 | 觀察頁面內容 | 顯示 WalletGuard 提示「請連接錢包」（或類似文字），主要功能區域被遮蔽 |
| 3 | 點擊導航欄的各個頁面連結 | 所有頁面都顯示「需要連接錢包」的提示 |

### 1.2 連接錢包

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊 Connect Wallet 按鈕 | 彈出錢包選擇對話框 |
| 2 | 選擇 SUI Wallet | 錢包擴充套件跳出授權確認 |
| 3 | 確認授權 | 頁面顯示已連接狀態，顯示截短的地址（如 `0x1509...bc4c`） |
| 4 | Dashboard 頁面載入資料 | 顯示 FUEL 餘額、Storage 數量、Contract 數量 |

### 1.3 斷開錢包

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊已連接的地址 / Disconnect | 錢包斷開 |
| 2 | 觀察頁面 | 回到 WalletGuard 提示狀態 |

---

## 場景 2：Storage 管理（倉庫擁有者流程）

### 2.1 建立新 Storage

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Dashboard 頁面點擊「Create Storage」按鈕 | 顯示交易確認（或直接跳出錢包簽名） |
| 2 | 在錢包中確認簽名 | TransactionToast 顯示 loading 狀態 |
| 3 | 等待交易完成 | Toast 顯示成功 + Tx Digest（可點擊） |
| 4 | 觀察 Dashboard | Storage 數量 +1，列表中出現新建立的 Storage |

### 2.2 進入 Storage 詳情

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Dashboard 點擊某個 Storage 卡片 | 跳轉到 `/storage/:storageId` |
| 2 | 觀察 Storage 資訊面板 | 顯示：Storage ID、Owner、System ID、容量（當前/最大）、Fee Rate、是否 Shared |
| 3 | 觀察管理按鈕 | 因為是 Owner，應看到：Share Storage、Set Guild、Update Fee Rate、Claim Fees |

### 2.3 存入貨物（Deposit）

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Storage Detail 頁面找到 Deposit 表單 | 看到 Item Type、Weight、Value 輸入欄 |
| 2 | 填入：Item Type = `ore`、Weight = `100`、Value = `1000` | 欄位正確顯示輸入值 |
| 3 | 點擊「Deposit」按鈕 | 錢包跳出簽名請求 |
| 4 | 確認簽名 | Toast 顯示成功 |
| 5 | 觀察頁面 | 容量數值增加，Receipt 列表出現新的 DepositReceipt |

### 2.4 提取貨物（Withdraw）

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Receipt 列表找到剛才存入的 Receipt | 看到 Receipt 資訊和「Withdraw」按鈕 |
| 2 | 點擊「Withdraw」按鈕 | 錢包跳出簽名（自動計算手續費） |
| 3 | 確認簽名 | Toast 顯示成功 |
| 4 | 觀察頁面 | Receipt 消失，容量數值減少 |

### 2.5 共享 Storage（不可逆操作）

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Storage Detail 找到「Share Storage」按鈕（紅色 danger） | 按鈕可見 |
| 2 | 點擊按鈕 | **彈出確認對話框**，警告此操作不可逆 |
| 3 | 確認 | 錢包簽名 → Toast 成功 |
| 4 | 觀察頁面 | Shared 狀態從 「No - Owned」變為「Yes」 |
| 5 | 重新載入頁面 | Share Storage 按鈕消失（已不可再操作） |

### 2.6 設定 Guild ID

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Set Guild 表單輸入一個 Guild ID（如 `0x6b1d...75c4`） | 欄位顯示輸入值 |
| 2 | 點擊「Set Guild」按鈕 | 錢包簽名 → Toast 成功 |
| 3 | 重新載入頁面 | Storage 資訊中顯示 Guild ID |

### 2.7 更新手續費率

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Update Fee Rate 表單輸入新費率（如 `300` = 3%） | 欄位顯示 |
| 2 | 點擊「Update Fee」按鈕 | 錢包簽名 → Toast 成功 |
| 3 | 觀察頁面 | Fee Rate 顯示更新後的值（3.00%） |

---

## 場景 3：FUEL 交易（Fuel Station）

### 3.1 瀏覽 Fuel Station

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊導航欄「Fuel Station」 | 跳轉到 `/fuel` |
| 2 | 觀察頁面 | 預設選中 Station 1，顯示：Fuel Level、Base Price、Owner Fee、Total Supplied |
| 3 | 點擊「Station 2」切換 | 資料刷新為 Station 2 的數值 |
| 4 | 觀察「My FUEL Balance」 | 顯示當前帳戶的 FUEL 餘額 |

### 3.2 購買 FUEL（SUI → FUEL）

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Buy FUEL 表單填入：Amount = `100000000000`（100 FUEL raw）、Max Price = `200`、Payment = `1000000000`（1 SUI） | 欄位正確顯示 |
| 2 | 點擊「Buy」按鈕 | 錢包簽名請求 |
| 3 | 確認簽名 | Toast 顯示成功 |
| 4 | 觀察 My FUEL Balance | 餘額增加 |
| 5 | 觀察 Station Fuel Level | 數量減少（賣出了 FUEL） |

### 3.3 供應 FUEL 到 Station（Supplier 流程）

> 此操作需要先持有 FUEL（透過 3.2 購買或 mint）

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | （如果有 Supply 表單）填入供應量 | 欄位顯示 |
| 2 | 點擊「Supply」按鈕 | 錢包簽名 → Toast 成功 |
| 3 | 觀察頁面 | Supplier Receipt 列表出現新 receipt |
| 4 | Station Fuel Level 增加 | 數量增加 |

### 3.4 Supplier 提領與提取

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Supplier Receipt 列表找到自己的 receipt | 看到「Claim」和「Withdraw」按鈕 |
| 2 | 點擊「Claim」（領取分潤） | 錢包簽名 → Toast 成功 |
| 3 | 點擊「Withdraw」（紅色，取回全部供應） | 錢包簽名 → Toast 成功 |
| 4 | 觀察頁面 | Receipt 消失，Station Fuel Level 減少 |

---

## 場景 4：運送（Transport — 自運模式）

### 4.1 建立運送訂單

> 前置：帳戶在某個 Storage 中有 DepositReceipt

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊導航欄「Transport」 | 跳轉到 `/transport` |
| 2 | 在 Create Transport Order 表單填入：| |
| | - From Storage ID = `0x1fcf...614c`（Storage 1） | 欄位顯示 |
| | - To Storage ID = `0x2a97...7bcb`（Storage 2） | 欄位顯示 |
| | - Receipt：從下拉選單選擇一個 DepositReceipt | 下拉正確列出 |
| | - Fuel Cost = `100000000000` | 欄位顯示 |
| | - Tier = `Instant`（下拉選 0） | 下拉顯示 |
| 3 | 點擊「Create Order」 | 錢包簽名 → Toast 成功 |
| 4 | 觀察訂單列表 | 新訂單出現，狀態為 Created |

### 4.2 完成運送

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 找到狀態為 Paid 的訂單 | 看到「Complete」按鈕 |
| 2 | 點擊「Complete」 | 錢包簽名 → Toast 成功 |
| 3 | 觀察狀態 | 變為 Completed |
| 4 | 到目標 Storage Detail 頁面 | 貨物已轉移到目標 Storage |

### 4.3 取消訂單

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 找到狀態為 Created 的訂單 | 看到「Cancel」按鈕（紅色） |
| 2 | 點擊「Cancel」 | 錢包簽名 → Toast 成功 |
| 3 | 觀察狀態 | 變為 Cancelled |

---

## 場景 5：Bounty Board（委託運送完整流程）

> 這是最複雜的場景，需要兩個帳戶配合：Client（發單者）+ Courier（接單者）

### 5.1 Client 發布運送委託

**使用帳戶 A（Client）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊導航欄「Bounty Board」 | 跳轉到 `/bounty` |
| 2 | 在 Create Contract 表單填入：| |
| | - From Storage ID = `0x1fcf...614c` | 欄位顯示 |
| | - To Storage ID = `0x2a97...7bcb` | 欄位顯示 |
| | - Receipt = 從下拉選單選一個 | 正確列出自己的 Receipt |
| | - Reward = `1000000000`（1 SUI） | 欄位顯示 |
| | - Cancel Penalty = `500000000`（0.5 SUI） | 欄位顯示 |
| | - Min Courier Deposit = `1000000000`（1 SUI） | 欄位顯示 |
| | - Deadline Duration = `86400000`（24 小時） | 欄位顯示 |
| 3 | 點擊「Create Contract」 | 錢包簽名 → Toast 成功 |
| 4 | 觀察 Bounty 列表 | 新 Contract 出現，狀態為 **Open** |
| 5 | 點擊該 Contract 進入詳情 | 跳轉到 `/bounty/:contractId` |
| 6 | 觀察詳情頁 | 顯示：Reward、Client 地址（= 我的）、Courier = None、狀態 = Open |

### 5.2 Courier 接單

**切換到帳戶 B（Courier）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 前往 `/bounty/:contractId`（同一個 Contract） | 頁面載入 Contract 詳情 |
| 2 | 因為不是 Client，看到「Accept Contract」按鈕 | 按鈕可見 |
| 3 | 填入 Deposit 金額 = `1000000000`（≥ Min Courier Deposit） | 欄位顯示 |
| 4 | 點擊「Accept Contract」 | 錢包簽名 → Toast 成功 |
| 5 | 觀察狀態 | 變為 **Accepted** |
| 6 | 觀察 Courier 欄位 | 顯示帳戶 B 的地址 |
| 7 | 觀察 Deadline | 顯示倒計時（24 小時後到期） |

### 5.3 Courier 取貨並配送

**繼續使用帳戶 B（Courier）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 頁面顯示「Pickup & Deliver」按鈕 | 按鈕可見（只有 Courier 看得到） |
| 2 | 點擊「Pickup & Deliver」 | 錢包簽名 → Toast 成功 |
| 3 | 觀察狀態 | 變為 **PendingConfirm** |

### 5.4 Client 確認收貨（Happy Path）

**切換回帳戶 A（Client）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 前往同一個 Contract 詳情頁 | 狀態為 PendingConfirm |
| 2 | 看到兩個按鈕：「Confirm Delivery」和「Raise Dispute」 | 兩個按鈕都可見 |
| 3 | 點擊「Confirm Delivery」 | 錢包簽名 → Toast 成功 |
| 4 | 觀察狀態 | 變為 **Settled**（或顯示已完成） |
| 5 | 帳戶 B 獲得 Reward（1 SUI）+ 取回押金 | 可到帳戶 B 查看餘額變化 |

### 5.5 Client 發起爭議（Dispute Path）

> 替代場景：5.4 改為 Dispute

**使用帳戶 A（Client）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 PendingConfirm 狀態的 Contract 詳情頁 | 看到「Raise Dispute」按鈕（紅色） |
| 2 | 點擊「Raise Dispute」 | 錢包簽名 → Toast 成功 |
| 3 | 觀察狀態 | 變為 **Disputed** |
| 4 | 等待 Oracle 裁決（需 OracleCap 持有者操作） | — |

### 5.6 Client 取消委託

**使用帳戶 A（Client），Contract 狀態為 Open**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Open 狀態的 Contract 詳情頁 | 看到「Cancel Contract」按鈕（紅色） |
| 2 | 點擊「Cancel Contract」 | 錢包簽名 → Toast 成功 |
| 3 | 觀察 | Contract 狀態更新，Reward 退回 Client |

### 5.7 逾時領取（Claim Timeout）

> 情境：Courier 接單後在 Deadline 前未完成

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 等待 Deadline 過期（或使用短 deadline 測試） | Deadline 倒計時歸零 |
| 2 | 觀察 Contract 詳情 | 出現「Claim Timeout」按鈕 |
| 3 | 點擊「Claim Timeout」 | 錢包簽名 → Toast 成功 |
| 4 | 觀察 | Courier 押金罰沒，Client 取回貨物 + 罰金 |

---

## 場景 6：公會系統（Guild）

### 6.1 建立公會

**使用帳戶 C（Guild Leader）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊導航欄「Guild」 | 跳轉到 `/guild` |
| 2 | 因為沒有 GuildMemberCap，顯示「Create Guild」表單 | 表單可見 |
| 3 | 輸入 Guild Name = `Star Haulers` | 欄位顯示 |
| 4 | 點擊「Create Guild」 | 錢包簽名 → Toast 成功 |
| 5 | 頁面刷新 | 顯示 Guild 資訊：名稱、Leader 地址、Member Count = 1 |

### 6.2 新增成員

**繼續使用帳戶 C（Leader）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Add Member 表單輸入帳戶 A 的地址 | 欄位顯示 |
| 2 | 點擊「Add Member」 | 錢包簽名 → Toast 成功 |
| 3 | 觀察 Member Count | 變為 2 |

### 6.3 成員檢視

**切換到帳戶 A**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 前往 `/guild` | 因為有 GuildMemberCap，顯示 Guild 資訊 |
| 2 | 觀察顯示 | 看到 Guild 名稱、Leader 地址（帳戶 C）、自己是成員 |
| 3 | 看到「Leave Guild」按鈕（紅色） | 按鈕可見（非 Leader） |
| 4 | **不看到** Add/Remove Member 表單 | 只有 Leader 才有管理表單 |

### 6.4 移除成員

**切換回帳戶 C（Leader）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Remove Member 表單輸入帳戶 A 的地址 | 欄位顯示 |
| 2 | 點擊「Remove」按鈕（紅色） | 錢包簽名 → Toast 成功 |
| 3 | 觀察 Member Count | 變為 1 |

### 6.5 成員離開

**使用帳戶 A（已是成員時）**

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在 Guild 頁面點擊「Leave Guild」 | **彈出確認對話框** |
| 2 | 確認 | 錢包簽名 → Toast 成功 |
| 3 | 觀察頁面 | 回到「Create Guild」表單狀態（不再是任何公會成員） |

---

## 場景 7：Threat Map 查詢

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 點擊導航欄「Threats」 | 跳轉到 `/threats` |
| 2 | 觀察 ThreatMap 資訊 | 顯示 Decay Lambda、Map ID |
| 3 | 在 Query 表單輸入 System ID = `1` | 欄位顯示 |
| 4 | 點擊「Query」 | 查詢 dynamic field |
| 5 | 觀察結果 | 顯示 System ID、Value Type、Field ID |
| 6 | 輸入不存在的 System ID（如 `999`） | 顯示「找不到資料」或空結果 |

---

## 場景 8：端到端完整流程（Full E2E）

> 模擬一個完整的太空物流作業

### 流程：存貨 → 買燃料 → 發委託 → 接單 → 配送 → 確認

| 步驟 | 帳戶 | 頁面 | 操作 | 驗證 |
|------|------|------|------|------|
| 1 | A | Dashboard | Create Storage | Storage 列表 +1 |
| 2 | A | Storage Detail | Deposit: ore, 100, 1000 | Receipt 出現 |
| 3 | A | Fuel Station | Buy FUEL: 100 FUEL, 1 SUI | FUEL 餘額 > 0 |
| 4 | A | Bounty Board | Create Contract: S1→S2, 1 SUI reward | Open 狀態 |
| 5 | B | Contract Detail | Accept: deposit 1 SUI | Accepted 狀態 |
| 6 | B | Contract Detail | Pickup & Deliver | PendingConfirm 狀態 |
| 7 | A | Contract Detail | Confirm Delivery | Settled 狀態 |
| 8 | A | Storage 2 Detail | 檢查貨物 | 貨物已在 Storage 2 |
| 9 | B | Dashboard | 檢查餘額 | 收到 Reward + 取回押金 |

---

## 場景 9：錯誤與邊界情況

### 9.1 錢包餘額不足

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 嘗試用 0 SUI 餘額的帳戶 Buy FUEL | 錢包報 InsufficientGas 或交易失敗 |
| 2 | 觀察 Toast | 顯示錯誤訊息（非白畫面） |

### 9.2 重複操作

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 在交易進行中（Toast 顯示 loading）再點一次按鈕 | 按鈕應 disabled 或不重複送出 |
| 2 | 快速連點「Deposit」按鈕 5 次 | 只送出一次交易 |

### 9.3 無效輸入

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | Deposit 表單：Weight = `0`、Value = `0` | 交易失敗（合約拒絕 zero value），Toast 顯示錯誤 |
| 2 | Create Contract：Reward = `0` | 交易失敗 |
| 3 | Accept Contract：Deposit < Min Courier Deposit | 交易失敗 |
| 4 | 在 Storage ID 欄位輸入 `abc`（非 hex） | 交易失敗，顯示錯誤 |

### 9.4 權限不符

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 用帳戶 B 進入帳戶 A 的 Storage Detail | 不應看到 Share/Set Guild/Update Fee 等管理按鈕 |
| 2 | 用非 Client 帳戶在 Open 狀態的 Contract 頁面 | 不應看到「Cancel Contract」按鈕 |
| 3 | 用非 Courier 帳戶在 Accepted 狀態的 Contract 頁面 | 不應看到「Pickup & Deliver」按鈕 |

### 9.5 網路中斷

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 開啟 DevTools → Network → Offline | 模擬斷網 |
| 2 | 嘗試操作任何頁面 | 顯示錯誤 UI，不會白畫面 |
| 3 | 恢復網路 | 頁面可重新載入並正常運作 |

### 9.6 頁面直接輸入 URL

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 直接前往 `/storage/0xinvalid` | 顯示錯誤或「找不到 Storage」 |
| 2 | 直接前往 `/bounty/0x000...000` | 顯示錯誤或空狀態 |
| 3 | 直接前往 `/nonexistent-route` | 顯示 404 或重導到 Dashboard |

---

## 場景 10：UI / UX 檢查

### 10.1 響應式（Responsive）

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 視窗縮小到 375px 寬（手機） | 導航欄收合或變為漢堡選單，內容不溢出 |
| 2 | 視窗放大到 1920px | 佈局正常，不過度拉伸 |
| 3 | 檢查表單在手機寬度下 | 輸入欄位可用，按鈕可點擊 |

### 10.2 Loading 狀態

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 開啟 DevTools → Network → Slow 3G | 模擬慢網 |
| 2 | 前往各個頁面 | 每個頁面都顯示 LoadingSpinner，不會閃爍空白 |
| 3 | 觀察交易送出時的按鈕狀態 | 按鈕顯示 loading / disabled，不可重複點擊 |

### 10.3 地址顯示

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | 觀察所有顯示 Object ID / Address 的地方 | 長地址應被截短（如 `0x1509...bc4c`） |
| 2 | 滑鼠移到截短地址上 | 顯示完整地址 tooltip |
| 3 | 點擊複製按鈕（如果有） | 複製到剪貼簿 |

### 10.4 狀態徽章（StatusBadge）顏色

| 狀態 | 預期顏色 |
|------|----------|
| Open | 綠色 / 藍色 |
| Accepted | 黃色 / 橙色 |
| PendingConfirm | 黃色 |
| Delivered | 藍色 |
| Disputed | 紅色 |
| Created | 灰色 / 藍色 |
| Completed | 綠色 |
| Cancelled | 灰色 / 紅色 |

---

## 場景 11：跨頁面導航一致性

| 步驟 | 操作 | 預期結果 |
|------|------|----------|
| 1 | Dashboard → 點 Storage → 回上一頁 | 回到 Dashboard，資料仍在 |
| 2 | Bounty Board → 點 Contract → 瀏覽器上一頁 | 回到 Bounty Board |
| 3 | 在 Contract Detail 頁面按 F5 重新整理 | 頁面正常載入（SPA 路由不 404） |
| 4 | 複製 `/storage/0x1fcf...614c` URL 開新分頁 | 直接載入該 Storage 的詳情 |

---

## 測試結果記錄表

| 場景 | 子場景 | Pass / Fail | 備註 |
|------|--------|-------------|------|
| 1. 錢包連接 | 1.1 未連接 | | |
| | 1.2 連接 | | |
| | 1.3 斷開 | | |
| 2. Storage 管理 | 2.1 建立 | | |
| | 2.2 詳情 | | |
| | 2.3 Deposit | | |
| | 2.4 Withdraw | | |
| | 2.5 Share（不可逆）| | |
| | 2.6 Set Guild | | |
| | 2.7 Update Fee | | |
| 3. Fuel Station | 3.1 瀏覽 | | |
| | 3.2 Buy FUEL | | |
| | 3.3 Supply | | |
| | 3.4 Claim/Withdraw | | |
| 4. Transport | 4.1 Create Order | | |
| | 4.2 Complete | | |
| | 4.3 Cancel | | |
| 5. Bounty 委託 | 5.1 Client 發單 | | |
| | 5.2 Courier 接單 | | |
| | 5.3 Pickup & Deliver | | |
| | 5.4 Confirm Delivery | | |
| | 5.5 Dispute | | |
| | 5.6 Cancel | | |
| | 5.7 Claim Timeout | | |
| 6. Guild | 6.1 建立 | | |
| | 6.2 新增成員 | | |
| | 6.3 成員檢視 | | |
| | 6.4 移除成員 | | |
| | 6.5 離開 | | |
| 7. Threat Map | 查詢 | | |
| 8. Full E2E | 9 步完整流程 | | |
| 9. 邊界情況 | 9.1 餘額不足 | | |
| | 9.2 重複操作 | | |
| | 9.3 無效輸入 | | |
| | 9.4 權限不符 | | |
| | 9.5 網路中斷 | | |
| | 9.6 直接 URL | | |
| 10. UI/UX | 10.1 響應式 | | |
| | 10.2 Loading | | |
| | 10.3 地址顯示 | | |
| | 10.4 狀態顏色 | | |
| 11. 導航 | 一致性 | | |
