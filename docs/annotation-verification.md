# Clipline 0.3.0 標記驗證

本紀錄區分可重跑的 production assertions／建置結果與主代理使用 CUA 的真實原生操作。原生測試只使用自行產生的 2400×1600 中英文字、RGB、棋盤與安全 QR fixture；沒有使用私人截圖。2026-10-20 已備份 0.2.0，於使用者正常退出後安裝並啟動 0.3.0；正式掛圖長按入口、編輯器關閉保護與回存已驗收，未覆蓋項目列於文末。

## 程式與發行檢查

Task 4 將 `Markup.shared.requestClose()` 接入 `applicationShouldTerminate`：拒絕關閉回傳 `terminateCancel`，保留／捨棄成功才回傳 `terminateNow`。既有 thumbnail `onSaved`、錄影 Trim、capture cancellation、Inbox 與信號還原路徑不變。此映射與先前已使用同一 API 的 harness 一致；正式 App 的編輯器關閉已實測，但選單列「結束 Clipline」的整個程序退出仍未原生驗收。

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

### 正式安裝版入口與回存（2026-10-20）

- 使用者長按自行產生的測試圖後，CUA 實際讀到「標記 — Clipline-Annotation-QA-20261020.png」；已確認透過正式掛圖入口開啟新版深色編輯器。
- 在標題周圍拖曳紅色矩形，點「關閉」後出現保留／捨棄／取消提示；選取消後，原視窗與紅框保留，Undo 仍可用。
- 點「完成並回存」後編輯器關閉；實際原檔為 2400×1600 PNG，保留紅框、不含選取 handles 或編輯器 UI。SHA256 由 `99f03617cca6bd2beb256e45eb3c8df1e5e14bf6604360db78e1c81417321039` 變為 `d29bc0901d86eae847f6062037409428b44d040b82e5ea206ec04918e79e6c2a`。本地證據保留於忽略版控的 `build/annotation-verification/installed-production-saved.png`。
- 僅將該生成測試圖移回專案證據目錄；watcher 已自動移除測試掛圖，原有 3 張仍留在掛圖清單。正式 App 程序仍由 `/Applications/Clipline.app/Contents/MacOS/Clipline` 執行，binary SHA 與嚴格簽章再次確認未變。
- 實際按兩次 ⌘Q 均沒有作用：正式 App 的退出快捷鍵只綁在 status menu，沒有 harness 的 `NSApp.mainMenu`。這不是退出保護通過的證據；本次沒有擴張成新增全域退出快捷鍵。
- 先前已在系統設定確認 Clipline「登入時開啟」及 TextSniper 背景活動關閉；本次沒有修改這些設定。定期上游同步規則已納入新編輯器的保留與回歸要求。

## 尚未覆蓋的原生驗收

- 部分樣式／裁切比例預設目前只有 production assertions，未逐個原生操作。
- 真實中文輸入法組字／候選視窗；目前中文證據是原生貼上與選取。
- 從正式 App 選單列「結束 Clipline」觸發的程序退出保護，以及回存後掛圖縮圖的視覺刷新。CUA 無法讀取透明掛圖列／選單列 UI；已驗證原檔回存與編輯器關閉保護，不能將它們替代這兩項觀察。
- Intel 實機與 Intel ddddocr runtime。Universal binary／交叉編譯不能證明 Intel 原生操作已驗收。

上述未驗項目不以編譯、交叉建置或單元測試代替。本紀錄也不宣稱已與 TrarrenShot 每項互動或像素完全一致。

## 0.3.3 直接重選舊標記（2026-10-20）

使用者回報「先加箭頭、再畫線，就無法編輯舊箭頭」。修正前已用正式程式碼建置的隔離原生測試器重現：畫線工具仍啟用時，點舊箭頭會新增一條短線。原因是只有手形工具會選取既有物件。

- 繪圖工具現在以短點擊選取舊標記；超過 3 個視圖點的拖曳仍畫新元素，曾拖遠再回原位也算拖曳。已選物件可拖移，控制點優先調整。選取不提交文件、不增加復原步驟。
- 空心矩形、圓形與聚光區的內部保留給新元素繪圖，選取及移動使用外框；重疊時取最上層命中。畫筆／螢光筆繼續連續繪圖，移動筆畫使用既有手形工具。雙擊舊文字沿用文字編輯。
- 新回歸案例在修改前有 15 個 assertion 失敗，修正後全套 11 capture/OCR、40 annotation checks 與 editor assertions 通過；獨立差異審查沒有阻擋項目。
- 真實 CUA 滑鼠操作已驗證：畫箭頭→切直線並畫線→直接點回箭頭，沒有多餘短線，參數列正確顯示箭頭樣式；拖曳移動舊箭頭、拉端點改變長度與角度，原直線保持原位；兩次復原與兩次重做正確恢復各步狀態。
- 0.3.3 arm64／x86_64 建置與固定簽章更新相容驗證通過。已自行透過 `NSRunningApplication.terminate()` 正常退出，保留 0.3.2 備份後安裝並重啟；正式路徑程序、版本與二進位雜湊一致。完整本機紀錄位於 `build/annotation-editing-verification/`。

原生驗收使用同一份標記程式碼的隔離測試器與自製圖片，沒有編輯使用者截圖；正式掛圖入口沿用既有實作。圓角／虛線框採容許範圍內的近似外框命中。本次沒有改變回存格式，完成回存後仍會平面化成圖片。

## 0.4.0 回存後保留可編輯元素（2026-10-20）

- `scripts/test.sh` 全數通過：11 項擷取／真實 Vision 與 ddddocr、47 項標記檢查，以及編輯器 assertions。208 個語系字串檢查通過。
- 新增磁碟回存→重新建立文件→移動舊箭頭／調整端點／改文字→再回存測試；驗證 ID、原圖、順序、樣式、裁切與乾淨基準一致，沒有重複烙印。PNG／JPEG／TIFF／HEIC 重複回存使用保存的無損底圖，P3／透明度與備註附錄維持一致。
- 驗證 Finder 類型的檔案移動／複製可恢復且各自獨立、相同合成畫面但不同原圖不混淆、archive 0700／0600、缺失／損壞／未知版本／非法 ID、archive 寫入失敗，以及外部 bytes／inode／annotation ID 改變的拒絕覆寫。分享／複製／另存仍走平面輸出，沒有原圖 payload。
- 原生驗收發現 macOS 在開啟圖片後補上 `com.apple.macl`／provenance，使 ctime 改變；原先整個 FileVersion 相等判斷誤擋回存。新增回歸測試先確認失敗，再改成與既有 swap 後檢查一致的 bytes／device／inode／annotation ID 驗證。讀取期間 stat 一致性及 RENAME_SWAP／回滾防護仍保留。
- CUA 以隔離原生測試器建立箭頭、線及文字，完成第一次回存；重開後點選舊箭頭，移動並拉端點縮放，雙擊文字改為 `Reopened and edited`，第二次回存成功。兩份 archive 比對：原圖及三個 ID 不變，箭頭幾何／文字有變，線未變。正常退出並重啟測試器後再次選取箭頭，顯示控制點且沒有額外烙印；Undo 為新工作階段的空歷史。
- 獨立設計及程式審查通過。0.4.0 arm64／x86_64 建置、固定簽章及更新相容檢查通過；自行正常退出 0.3.3、備份、安裝到 `/Applications/Clipline.app` 並重啟，正式程序路徑／版本／binary SHA256 與建置一致。自動更新契約已加入可編輯資料相容與平面分享保護。
- 證據位於忽略版控的 `build/annotation-persistence-verification/`：測試／建置紀錄、兩次原生保存資料與圖片、安裝版本／雜湊及 0.3.3 備份。

限制：舊版已平面化標記無法還原；新資料只在本機保存，傳輸若丟失 xattr 或換到沒有 archive 的 Mac，只能開啟合成圖片。本機 archive 包含遮罩前／裁切前的原圖，刪除圖片不會自動清除 archive；初版不做垃圾回收或跨工作階段 Undo。原生驗收使用自製圖片及相同 production 編輯器程式，沒有修改使用者截圖；本次未重做未改動的正式掛圖入口或隱私授權驗收。

## 0.4.1 直接拖曳與各類控制點（2026-10-20）

本節取代 0.3.3 的「未選取拖曳仍新增」及「筆畫只能用手形工具移動」契約。使用者提供的橢圓八點、箭頭兩端點與 X 截圖為視覺參考。

- hover 與 mouseDown 共用命中判定，游標在可移動元素上為 openHand，按下移動中為 closedHand。各繪圖工具從既有元素開始拖曳會直接移動；空心框內仍可畫新圖，裁切／橡皮擦維持專用模式。文字／泡泡／備註雙擊進入既有編輯器。
- 線與箭頭保留兩端點；框形元素八點；步驟／圖章／筆畫四角等比縮放，筆畫連同線寬縮放；泡泡尾端及未連動放大鏡來源點保留。控制點固定畫面尺寸、藍色圓點白邊，不再畫通用虛線外框。原生 X 按鈕可存取、拖出取消且刪除可復原。
- 新直接拖曳測試先確認舊邏輯失敗；獨立審查另發現微小筆畫重疊命中區挑錯角，新增單點／水平／垂直筆畫測試重現後，改成挑最近控制點。最終 `scripts/test.sh` 為 11 capture/OCR、52 annotation checks 與 editor assertions 全通過；208 字串／12 語系通過；複審無阻擋問題。
- CUA 以相同 production 程式的隔離測試器，打開 0.4.0 保存的原圖／標記：在文字工具下首次拖曳未選箭頭可直接移動，沒有新增元素；拖箭頭端點改變方向與長度。橢圓顯示八圓點，拖側點單獨改寬；改用畫筆後從橢圓邊線直接拖移成功。雙擊舊文字可改成正體中文，完成回存並重開後文字與橢圓八點都保留。
- 原生驗收曾發現 X 拖出仍刪除，將原生按鈕明確設為 momentaryPushIn／leftMouseUp 後，重驗拖出不刪除、點擊刪除及 CmdZ 恢復通過。沒有加入自製滑鼠追蹤迴圈或新相依套件。
- 自動更新沿用排程中「以最新本文件驗收契約為準」的規則。觸及此互動時須保留共用 hover／按下命中、首次拖移、專屬控制點、文字雙擊、X 取消與復原，以及舊 archive 回存重開；不得回退為必須先點選的流程。
- 0.4.1 universal arm64／x86_64 與固定簽章更新相容驗證通過。正式 App 正常退出時出現未回存標記提示，選「保留變更」後確認程序已結束；備份 0.4.0 再安裝並重啟。正式路徑、0.4.1 版本、binary SHA256 `44c801dfff93487d4859475480e8720ac132952b64b540303a7ebf18fc60885f`、OCR helper 與建置一致，嚴格簽章通過。未重設權限或登入設定。

界線：游標物件與命中一致性由程式測試確認，CUA 截圖的指標覆蓋無法當成系統手掌圖示的視覺證據；未逐一原生驗收所有樣式，也未重做未變更的正式掛圖入口或隱私授權。既有 archive 格式未變，0.4.0 的平面舊圖／分享／本機 archive 限制仍適用。證據保存於忽略版控的 `build/annotation-interaction-verification/`。
