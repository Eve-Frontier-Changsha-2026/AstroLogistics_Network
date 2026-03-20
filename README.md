# 專案名稱：AstroLogistics_Network (跨星系儲存與全域燃料物流網)

> 📜 **[EVE Frontier 專案憲法與開發準則](https://github.com/Eve-Frontier-Changsha-2026/Constitution/blob/master/EVE_Frontier_Project_Constitution.md)**
> 本專案的世界觀設定與底層相依資源，均遵從此憲法文檔之規範。


## 📌 概念簡介
這個專案旨在打造 EVE Frontier 中的「宇宙級 UPS 與燃料庫」。我們利用 **Smart Assemblies** 將儲存箱 (Storage) 轉化為 Sui 上的 Shared Object，並融合燃料與能量經濟，建立一個橫跨星系的去中心化物流、能源配送、物資轉運和點對點的任務網。

## 🎯 解決痛點與核心循環
- **物資與燃料跨星系傳送**：玩家將貨品放入 A 星系 Smart Storage，透過上鏈與扣除高階燃料，在 B 星系解鎖提領。同時支援燃料的儲存、轉換、販售或借貸。
- **快遞任務市場**：低階物流可產生「快遞任務合約 (Courier Contract)」，交由其他運輸玩家實飛完成，儲存箱建造者從中抽取手續費分潤。
- **工業採集與製造**：玩家採集原礦後，可在燃料網絡的工業節點進行精煉成燃料品級資源，供應龐大艦隊所需。
- **戰略衝突點（摧毀）**：戰略上可以攻擊對手的關鍵燃料樞紐，造成其整個戰線能源短缺；系統同時記錄燃料戰爭的鏈上歷史。

## 🔗 與 Sui / World Contracts 的結合
- 每個燃料桶、電池、倉儲箱用 Sui 物件表示，擁有明確所有權與狀態（容量、品質、位置）。
- 使用 World Contracts 為樞紐寫邏輯：例如依照庫存自動調整價格（AMM 式）、支援「能源借貸」，以未來產量抵押，條件紀錄上鏈。
- 外部 dApp 使用 @evefrontier/dapp-kit 的 GraphQL / hooks 繪製「燃料熱度圖」及「最佳補給路線」。
- 支援 zkLogin + sponsored gas，玩家用 email 登入即可查詢與下單。

## 🏆 得獎潛力
- **完美對齊官方願景**：高度貼合「A Toolkit for Civilization」，能源與物流是文明基礎世界經濟中樞。
- **具備全域性**：物流路線必然跨星系，所有玩家都會受影響。
- **長期演化潛力**：之後可擴充碳排放、能源稅、封鎖制裁等玩法，形成富有敘事性的經濟戰。
