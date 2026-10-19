# Clipline 0.3.0 標記驗證

本紀錄區分可重跑的 production assertions／建置結果與主代理使用 CUA 的真實原生操作。原生測試只使用自行產生的 2400×1600 中英文字、RGB、棋盤與安全 QR fixture；沒有使用私人截圖。2026-10-20 已備份 0.2.0，於使用者正常退出後安裝並啟動 0.3.0；正式掛圖入口與退出保護的最後原生檢查仍待完成。

## 程式與發行檢查

Task 4 將 `Markup.shared.requestClose()` 接入 `applicationShouldTerminate`：拒絕關閉回傳 `terminateCancel`，保留／捨棄成功才回傳 `terminateNow`。既有 thumbnail `onSaved`、錄影 Trim、capture cancellation、Inbox 與信號還原路徑不變。此簡單映射與先前已使用同一 API 的 harness 一致，正式 App 的原生退出仍待主代理驗收。

| 檢查 | 結果 |
|---|---|
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/test.sh` | 11 capture/OCR＋38 annotation checks、editor focused assertions 全通過 |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift scripts/check-strings.swift` | 205 keys／12 語系通過 |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/build-app.sh` | arm64 與 x86_64 release 編譯／連結成功；`build/Clipline.app` 為 0.3.0（build 1） |
| `lipo -archs build/Clipline.app/Contents/MacOS/Clipline` | `x86_64 arm64` |
| `codesign --verify --deep --strict build/Clipline.app` | 通過（ad-hoc 簽章；未 notarize） |

完整測試保留 11 項 capture/OCR 檢查（含真 Vision、真 ddddocr、失敗／取消與私有 PNG 儲存），另執行 `scripts/test-annotations.sh` 的 38 項 model／renderer／Canvas 檢查，以及 `scripts/test-annotation-editor.sh` 的設定、原生控制項、真 Vision QR、原檔 alias、未 Return 的備註與 Undo／Redo 回歸 assertions。這些 assertions 不代替真滑鼠、鍵盤與輸入法驗收。

## 已觀察的原生操作

以下為主代理使用 CUA 操作 production-linked harness 的實際觀察；每項標明測試版本，未將模型測試當成真實桌面驗收。

| 操作 | 實際觀察與版本 |
|---|---|
| 矩形拖曳與回存 | 首版：對齊原圖，顯示 8 handles；Finish 只回呼一次，實際輸出有紅框、沒有選取 UI |
| 步驟與歷史 | 首版：建立 1／2／3、刪除第二個後重編號、CmdZ 復原並啟用 Redo |
| 原生文字 | 首版：多行正體中文／英文貼上；文字子選取 CmdC 優先複製文字；Esc 結束文字後留窗 |
| QR／Vision OCR | 首版：安全 payload `CLIPLINE-ANNOTATION-QA`，未開網址；Vision 顯示可選中英與數字結果 |
| Dirty 關閉 | 首版：Cancel 保留編輯器；Discard 後 callback 0，原檔 SHA256 前後相同 |
| 修正版版面 | `3b1b446`：置中緊湊主列、A／下拉文字共槽、相鄰尺寸／設定／釘選；Step 兩列與圓形預覽；來源白框 |
| 精確裁切／Option OCR／PNG 另存 | `7cdadbd`：尺寸面板設 X=290、Y=440、380×80；按住 Option 點 OCR 得 `0123456789`；另存 PNG 後尺寸與實際像素確認只含裁切數字與白底，無範圍外影像／QR／handles；原文件保持開啟 |
| 未 Return 備註→退出保留 | `7cdadbd`：總覽改成「總覽尚未按 Return 的新文字」，不按 Return，CmdQ→保留變更；實際圖片含最新文字與 24px 字級，appendix 一次，2400×1654，沒有 handles；harness 正常結束 |

`3b1b446` 曾實際丟失尚未 Return 的總覽文字，備註字級也未影響輸出；上述 `7cdadbd` 原生回歸已覆核該流程。程式 assertions 同時驗證最新備註進入 render／save／dirty 判斷，及相同選取物經鍵盤 Undo／Redo 後 inspector 的顏色、線寬與文字同步。

### 工具與視窗原生回歸（`7cdadbd`）

- 實際拖曳橢圓、反向箭頭、畫筆、螢光筆皆正常；橡皮擦移除筆畫而保留原圖，聚光燈圈外變暗，Undo 正常還原。
- 棋盤高對比圖的模糊／黑色實色／馬賽克各有可辨識效果；非連結放大鏡的來源點移到數字後，原目的位置顯示放大的 5678。
- 表情貼圖與泡泡中文字正常顯示，Esc 結束文字編輯。
- 分享開啟原生選單後取消，沒有選擇傳送目的地；複製按鈕顯示「已複製圖片」。
- JPEG 另存實際解碼為 2400×1600 JPEG，畫面包含正確標記且沒有控制點；但檔名誤留 `.png`，已列入最終修正波，不能視為完整另存 PASS。
- 設定隱藏圓形後工具列即時更新，重設恢復。實際將視窗縮至 1706×1356 像素，水平捲到最右可操作分享／另存／複製／關閉，Fit 可看到完整原圖。
- 另存後 CmdQ 仍詢問是否回存原圖，選「捨棄變更」正常退出。

### 最終修正與安裝（`cf07879`）

- 最終整體審查與限定修正複審皆通過，沒有 OPEN finding。實線／虛線／曲線備註箭頭保留方向；裁切提交後共用整數像素邊界；無 Edit 選單的真 NSWindow 測試確認 inspector／備註總覽欄位優先處理文字複製與復原；格式切換同步 NSSavePanel 類型與檔名。
- 修正版原生 JPEG 另存到 `/private/tmp/clipline-native-fixed.jpg`，實際檔名與 JPEG bytes 一致，2400×1600。負斜率備註從右上拖到左下，取消選取後確認編號 1 在右上箭尾，箭頭指向左下；備註文字欄 CmdZ 恢復原文字且保留標記。
- 最終 `scripts/test.sh`：11 capture、38 annotation、editor assertions 全通過；雙架構 App 與 harness 建置成功。未新增語系 keys，先前 205 keys／12 語系結果仍適用。
- 安裝版 binary SHA256 `b6e6369937674e8a91e360285a524e79949e75a7e2820fbd3dccc86cb99b22b9` 與已測試建置相同，嚴格 codesign 通過，程序路徑 `/Applications/Clipline.app/Contents/MacOS/Clipline`。舊版已備份到專案 `build/annotation-update-backup/`。
- 安裝版 `/Applications/Clipline.app/Contents/Resources/ddddocr_worker.py` 與 source SHA 相同，既有獨立 Python runtime 實際回傳 `0123456789`。

## 尚待主代理原生驗收

- 部分樣式／裁切比例預設目前只有 production assertions，未逐個原生操作。
- 真實中文輸入法組字／候選視窗；目前中文證據是原生貼上與選取。
- 最終 0.3.0 production App 的正常退出保護、掛圖長按入口、縮圖刷新，以及實際安裝後回歸。
- Intel 實機與 Intel ddddocr runtime。Universal binary／交叉編譯不能證明 Intel 原生操作已驗收。

上述未驗項目不以編譯、交叉建置或單元測試代替；正式入口的原生結果會在觸發後補記。
