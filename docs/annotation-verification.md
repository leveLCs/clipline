# Clipline 0.3.0 標記驗證

本紀錄區分可重跑的 production assertions／建置結果與主代理使用 CUA 的真實原生操作。原生測試只使用自行產生的 2400×1600 中英文字、RGB、棋盤與安全 QR fixture；沒有使用私人截圖。0.3.0 尚未安裝；既有安裝版 0.2.0 保持原狀。

## 程式與發行檢查

Task 4 將 `Markup.shared.requestClose()` 接入 `applicationShouldTerminate`：拒絕關閉回傳 `terminateCancel`，保留／捨棄成功才回傳 `terminateNow`。既有 thumbnail `onSaved`、錄影 Trim、capture cancellation、Inbox 與信號還原路徑不變。此簡單映射與先前已使用同一 API 的 harness 一致，正式 App 的原生退出仍待主代理驗收。

| 檢查 | 結果 |
|---|---|
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/test.sh` | 11 capture/OCR＋36 annotation checks、editor focused assertions 全通過 |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift scripts/check-strings.swift` | 205 keys／12 語系通過 |
| `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/build-app.sh` | arm64 與 x86_64 release 編譯／連結成功；`build/Clipline.app` 為 0.3.0（build 1） |
| `lipo -archs build/Clipline.app/Contents/MacOS/Clipline` | `x86_64 arm64` |
| `codesign --verify --deep --strict build/Clipline.app` | 通過（ad-hoc 簽章；未 notarize） |

完整測試保留 11 項 capture/OCR 檢查（含真 Vision、真 ddddocr、失敗／取消與私有 PNG 儲存），另執行 `scripts/test-annotations.sh` 的 36 項 model／renderer／Canvas 檢查，以及 `scripts/test-annotation-editor.sh` 的設定、原生控制項、真 Vision QR、原檔 alias、未 Return 的備註與 Undo／Redo 回歸 assertions。這些 assertions 不代替真滑鼠、鍵盤與輸入法驗收。

## 已觀察的原生操作

以下依主代理 `.superpowers/sdd/2026-10-19-clipline-annotation-editor/native-qa.md`，截至 Task 3 修正 `7cdadbd` 的回歸紀錄。

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

## 尚待主代理原生驗收

- 其他工具、遮罩、泡泡、裁切比例／尺寸預設、各種樣式與相關實際匯出。
- 分享、JPEG 另存、設定操作、小視窗水平捲動。
- 真實中文輸入法組字／候選視窗；目前中文證據是原生貼上與選取。
- 最終 0.3.0 production App 的正常退出保護、掛圖長按入口、縮圖刷新，以及實際安裝後回歸。
- Intel 實機與 Intel ddddocr runtime。Universal binary／交叉編譯不能證明 Intel 原生操作已驗收。

本 Task 不執行安裝、啟動 App、push 或變更更新 automation。主代理將完成最後 native acceptance、獨立 review 與後續發行流程；待完成才更新上述項目。
