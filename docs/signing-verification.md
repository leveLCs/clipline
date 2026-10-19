# Clipline 0.3.1 固定簽章驗證

2026-10-20。這次只修改建置與更新防護，未改動 OCR、掛圖或標記功能。

## 原因與修正

原 0.3.0 使用 ad-hoc 簽章，macOS 的 designated requirement（DR）包含該次建置的 CDHash；重新建置會改變 App 身分。現在使用已獲使用者授權建立的 Apple Development 憑證，固定公開指紋與 DR，私鑰留在鑰匙圈，沒有匯出或提交到版本庫。

共用設定位於 `~/Library/Application Support/Clipline/Signing/identity.json`，權限為 0600。不同 checkout／worktree 使用同一份設定。建置前先確認固定身分可用；無憑證、過期、衝突的身分覆寫都會停止，沒有 ad-hoc fallback。

`verify-update` 要求候選與已安裝版本都符合固定憑證、bundle ID、資源封印及每個架構的 DR。每週一 10:00 的既有 Tendedero 同步排程已更新：建置前檢查憑證、執行簽章測試且不能有 skip，建置後與安裝前再次驗證兩份 App，安裝後驗證正式路徑的 App。初次 ad-hoc 遷移不能當作往後更新的例外。

## 可重跑驗證

| 檢查 | 結果 |
|---|---|
| `/usr/bin/python3 Tests/SigningTests.py` | 8 項通過、0 skip；使用真實 codesign 與隔離 fixture |
| 無設定的建置 | 在編譯／替換舊產物前停止；不接受 `SIGN_IDENTITY=-` 繞過 |
| 不同程式內容、同一身分 | 更新驗證通過；ad-hoc 候選與已安裝版本均被拒絕 |
| 修改資源、錯誤 bundle ID、身分覆寫 | 均被拒絕 |
| 放寬 DR、其他架構放寬 DR、重新設定其他身分 | 均被拒絕；原設定保留 |
| `scripts/test.sh`（macOS 26.5 SDK） | 11 capture/OCR、38 annotation checks 及 editor assertions 全通過 |
| 0.3.1 build 1／2 建置 | arm64、x86_64 編譯及嚴格簽章驗證通過 |
| 獨立程式審查 | 修正非原生架構 DR 檢查後複審通過 |

無身分時偷偷 ad-hoc 簽署，以及只比較原生架構 DR 的問題，都曾由對應測試先重現，再確認修正後通過。

## 正式安裝與權限驗收

兩次安裝均在使用者確認正常退出後進行；舊 App 先備份，再驗證暫存副本與安裝結果。未修改 TCC 資料庫、使用者截圖或設定。正式路徑保持 `/Applications/Clipline.app`，bundle ID 保持 `io.github.leveLCs.Clipline`。

| 階段 | 證據 |
|---|---|
| ad-hoc → 0.3.1 build 1 | 明確執行初次遷移；使用者回覆「OCR 正常，Clipline 已退出」 |
| build 1 → build 2 | 真實 App CDHash 不同；憑證與兩個架構的 DR 相同；安裝前後簽章驗證通過 |
| build 2 啟動 | 程序路徑確認為 `/Applications/Clipline.app/Contents/MacOS/Clipline` |
| 更新後 OCR 與權限 | 使用者實際按 ⌘⇧2 後回覆「OCR 正常，沒有再要求授權」；未再移除／重加權限，保留 App 開啟 |

build 2 安裝版 binary SHA256：`e459f070200211645782b77fe6e55ec436814d780412c21c9503fd4938f0fcc9`。

本機回復副本與完整測試輸出位於忽略版控的 `build/signing-verification/`：`Clipline-replaced-adhoc.app`、`Clipline-signed-build-1.app`、`tests.log`、`app-tests.log`、`state.json`。

## 限制

憑證有效至 2027-10-20 01:04（台灣時間）。到期前需明確續證，確認新舊 DR 相容後再遷移；不可刪除設定來繞過檢查。這是本機 Apple Development 簽章，未做公證發行。未在 Intel 實機驗收，也不保證 macOS 自身的定期隱私提醒永不出現。
