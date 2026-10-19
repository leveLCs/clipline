# Clipline

Select text. Hang screenshots. A native macOS 14+ menu bar app, independently modified from [Tendedero](https://github.com/alejandrobujan/tendedero).

## 使用方式

| 操作 | 結果 |
|---|---|
| `⌘⇧2`，放開快捷鍵後拖曳框選 | Apple Vision OCR，文字直接複製到剪貼簿 |
| 框選時按住 `⌥`，直到放開滑鼠 | 改用 ddddocr OCR |
| 框選時按住 `⌃ Ctrl`，直到放開滑鼠 | 將截圖掛到螢幕上方 |
| `Esc` | 取消，保留原剪貼簿 |
| `⌃⌥T` | 顯示／隱藏掛圖列，可在選單修改 |

Apple Vision 優先辨識正體中文與英文；ddddocr 使用 1.6.1 預設模型。放開滑鼠時決定模式，`⌃ Ctrl` 優先於 `⌥`；`⌘` 不切換掛圖模式。框選上方會顯示目前模式。

兩種 OCR 都在本機處理，不上傳影像，也不儲存 OCR 用的截圖。無文字或錯誤時不清除原剪貼簿，ddddocr 失敗時不會自動切回 Vision。掛圖保留點擊複製、長按標記、雙擊預覽與拖曳分享。

第一次擷取需允許 macOS「螢幕與系統音訊錄製」權限；只擷取靜態影像，不錄音。若 TextSniper 已佔用 `⌘⇧2`，先在 TextSniper 釋放此快捷鍵，再使用 Clipline 選單的重試項目。也可從選單直接開始框選。

可從任一螢幕開始框選；每次擷取限定在起始螢幕內，不拼接跨螢幕影像。掛圖儲存於 `~/Library/Application Support/Clipline/Screenshots`，從掛圖列丟棄會移至垃圾桶。預設只收納 Clipline 擷取的圖片；系統截圖接管及剪貼簿圖片監看仍為選用功能。

## 圖片標記（0.4.1）

長按掛圖即可開啟 Clipline 原生標記編輯器；錄影仍開啟既有裁剪編輯器。工具列提供矩形、橢圓、線條、箭頭、文字／泡泡文字、畫筆、螢光筆、遮罩（馬賽克／模糊／實色）、放大鏡、步驟、表情符號、聚光燈與備註。選取工具後在圖片空白處拖曳建立；步驟與圖章可點擊建立。游標移到既有標記的線條或實心區域會變手掌，可直接拖曳移動，不必先點選或切換手形工具；畫筆／螢光筆也適用。空心框內部可繼續繪圖，手形工具可從框內選取。橡皮擦移除整個標記，裁切模式使用專用控制點。

選取元素後會顯示藍色白邊圓形控制點與 X 刪除按鈕，刪除可復原：

| 元素 | 調整方式 |
|---|---|
| 線條、箭頭、箭頭備註 | 拖兩端改長度與方向 |
| 矩形、橢圓、遮罩、聚光燈、文字框、框形備註 | 八點調整寬高；文字字級由參數列調整 |
| 步驟、圖章、畫筆、螢光筆 | 四角等比縮放；筆畫同步調整線寬 |
| 泡泡、放大鏡 | 調整外框，另可拖泡泡尾端或未連動的取樣點 |

下方參數列調整目前工具或選取物的樣式。文字／泡泡共用 A 與下拉選單；雙擊文字可編輯。備註總覽可編輯備註，輸出時在圖片下方附加一次備註清單。尺寸按鈕提供裁切、像素座標、比例與尺寸預設；預設尺寸超過原圖時等比縮小，不放大原圖。設定可保存各工具樣式、工具順序與顯示、工具列大小及點擊建立偏好；窄視窗可水平捲動工具列。

| 編輯器操作 | 結果 |
|---|---|
| `⌘Z`／`⌘⇧Z` | 復原／重做（本次編輯最多 100 筆歷史） |
| `⌘D` | 複製選取標記 |
| `Delete`／`Backspace` | 刪除選取標記 |
| `⌘C` | 複製渲染後 PNG；編輯文字且有選取文字時優先複製文字 |
| `⌘+`／`⌘-`／`⌘0` | 放大／縮小／符合視窗 |
| `Shift`＋拖曳 | 限制形狀比例，或線條／箭頭角度；裁切時保持正方形 |
| `Return`／空白鍵（畫布焦點） | 完成並回存原圖；文字編輯中仍使用原生文字輸入 |
| `Esc` | 依序結束文字、取消手勢、取消選取、離開裁切，最後才關閉編輯器 |

釘選完成按鈕會安全回存圖片並更新掛圖縮圖，同時在本機保留原圖、裁切與標記元素；下次長按同一張圖可繼續移動、縮放、改文字或樣式。復原／重做歷史從每次開啟時重新開始。支援單張 PNG、JPEG、TIFF、HEIC 回存，其他格式請另存 PNG／JPEG。原圖若在編輯期間被外部變更會拒絕覆寫。另存不會標記原圖已儲存，也不允許藉原圖路徑、符號連結或硬連結繞過安全回存。複製、分享及另存只輸出合成圖片，不帶可還原遮罩的原圖或標記資料。關閉、切換圖片或正常結束 App 時，有未存變更會詢問保留／捨棄／取消；儲存失敗會保留編輯器。

可編輯資料放在 `~/Library/Application Support/Clipline/Annotations`（目錄 0700、檔案 0600）；圖片只帶隨機識別碼。Finder 保留擴充屬性的改名、移動與複製可延續編輯，複本各自修改互不影響。移到另一台 Mac、移除擴充屬性或刪除本機資料後只剩合成圖片；外部修改造成內容不符時也不會套用舊標記，編輯器會顯示提示。損壞或不支援的標記資料會停止開啟，保留原檔。**舊版已回存的標記無法還原成獨立元素。**

本機標記資料包含遮罩前及裁切前的原圖。為保留複本與垃圾桶還原的可編輯性，目前不自動清除歷次資料；刪除圖片不會清除這些資料，長期使用會增加磁碟用量。分享出去的圖片不包含這些本機資料。

OCR 與 QR 使用目前標記後的裁切範圍（不含備註清單）。OCR 按鈕預設使用 Vision，按住 `⌥` 點擊改用已安裝的 ddddocr；結果可選取並手動複製。QR 顯示內容及可切換的提示框，不會自動開啟網址。取消辨識或關閉編輯器後，過期結果不會更新視窗或剪貼簿。

驗證結果與仍待原生操作確認的項目見 [標記驗證紀錄](docs/annotation-verification.md)。

## Build and test

Requires Apple's Command Line Tools or Xcode. Apple Vision needs no third-party runtime.

Option OCR needs a one-time installation with [uv](https://docs.astral.sh/uv/) available:

```sh
scripts/install-ddddocr.sh
```

This downloads a private Python 3.13 and pinned ddddocr dependencies into `~/Library/Application Support/Clipline/OCR`. It does not change system Python or depend on the checkout, pyenv, or uv after installation. Install separately on each Mac for its architecture; copying only the app does not copy the optional runtime. ddddocr starts on demand, takes about a second per capture on the tested Mac, and stops after 15 seconds if unresponsive. Its default model targets CAPTCHA-style images; long, multiline Traditional Chinese is better handled by Vision.

The complete test suite includes the 11 capture/OCR checks, annotation model/renderer/canvas checks, and native editor assertions. It requires that optional runtime to be installed, and a logged-in macOS session for Vision and the private test pasteboard.

```sh
scripts/test.sh
swift scripts/check-strings.swift
/usr/bin/python3 Tests/SigningTests.py
scripts/build-app.sh
```

The app bundle contains Apple silicon and Intel binaries. The optional runtime was tested on Apple silicon with macOS 26.5.1; its Intel installation has not been verified.

### Fixed signing identity for local updates

Release and debug app builds require a configured Apple code-signing identity in the macOS Keychain. There is no ad-hoc fallback. For this Mac's local use, create an Apple Development certificate in Xcode Settings → Apple Accounts → your authorized team → Manage Certificates. Keep its private key in Keychain; never commit or export it into this repository.

Initialize once with the certificate's 40-character fingerprint from `security find-identity -v -p codesigning` and an existing Clipline bundle:

```sh
/usr/bin/python3 scripts/signing.py configure CERTIFICATE_FINGERPRINT /Applications/Clipline.app
```

This signs and validates a temporary copy, leaving the supplied app untouched. Only the public fingerprint and designated requirement (DR) are saved in `~/Library/Application Support/Clipline/Signing/identity.json`, shared across checkouts/worktrees. `SIGN_IDENTITY` cannot override this pin. `CLIPLINE_SIGNING_CONFIG` is available for isolated tests; normal builds and updates must use the default configuration.

`scripts/build-app.sh` checks the identity before compiling or replacing an existing build. A missing, expired, or inaccessible certificate stops the build. Signing uses Apple's default DR, then checks the exact pinned DR, certificate, bundle identifier, resources, and every architecture. Updates must run this before replacing the installed app:

```sh
/usr/bin/python3 scripts/signing.py verify-update build/Clipline.app /Applications/Clipline.app
```

Both apps must pass the fixed identity checks and satisfy each other's DR. Altered files, another signer, weaker/different DRs, and ad-hoc builds are rejected. Keep the installation path `/Applications/Clipline.app` and the bundle ID unchanged. Back up the installed app, quit normally, install the tested bundle, restart, and verify the installed bundle again. Request a normal quit through `NSRunningApplication.terminate()` and confirm the process has exited; preserve any unsaved-edit prompt instead of force-quitting or routinely asking the user to quit manually. Do not run a development copy from another path as the permission-retention acceptance test.

The first migration from an ad-hoc build intentionally cannot pass `verify-update`. Perform it explicitly after a `signing.py verify` check and backup; macOS may require one new screen-recording grant. Recurring updates must never bypass `verify-update`, reset TCC, or silently replace the identity. Certificate renewal is a separate explicit operation: verify the new certificate's DR against the stored DR and installed app before changing the fingerprint and migrating. Do not delete the configuration to work around a failed check. Switching from Apple Development to Developer ID may change the DR and require new permission.

Apple Development signing here is for local use, not notarized distribution. A matching signature is a prerequisite for retaining TCC access, not proof that macOS will never show a privacy reminder. Verify one real update and screen capture after the initial authorization. `Tests/SigningTests.py` uses real `codesign`; positive cases are marked skipped if no identity is configured, which is not sufficient for an update approval.

本機建置、更新及權限保留的實測紀錄見 [固定簽章驗證](docs/signing-verification.md)。

## Attribution and license

Based on Tendedero by Alejandro Buján. Original source copyright and MIT terms are retained in [LICENSE](LICENSE). Clipline is an independent fork and is not endorsed by the original author. Clipline uses its own name and original icon; upstream promotional artwork is not used.
