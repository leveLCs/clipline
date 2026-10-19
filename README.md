# Clipline

Select text. Hang screenshots. A native macOS 14+ menu bar app, independently modified from [Tendedero](https://github.com/alejandrobujan/tendedero).

## 使用方式

| 操作 | 結果 |
|---|---|
| `⌘⇧2`，放開快捷鍵後拖曳框選 | Apple Vision OCR，文字直接複製到剪貼簿 |
| 框選時按住 `⌥`，直到放開滑鼠 | 改用 ddddocr OCR |
| 框選時按住 `⌘`，直到放開滑鼠 | 將截圖掛到螢幕上方 |
| `Esc` | 取消，保留原剪貼簿 |
| `⌃⌥T` | 顯示／隱藏掛圖列，可在選單修改 |

Apple Vision 優先辨識正體中文與英文；ddddocr 使用 1.6.1 預設模型。放開滑鼠時決定模式，`⌘` 優先於 `⌥`。框選上方會顯示目前模式。

兩種 OCR 都在本機處理，不上傳影像，也不儲存 OCR 用的截圖。無文字或錯誤時不清除原剪貼簿，ddddocr 失敗時不會自動切回 Vision。掛圖保留點擊複製、長按標記、雙擊預覽與拖曳分享。

第一次擷取需允許 macOS「螢幕與系統音訊錄製」權限；只擷取靜態影像，不錄音。若 TextSniper 已佔用 `⌘⇧2`，先在 TextSniper 釋放此快捷鍵，再使用 Clipline 選單的重試項目。也可從選單直接開始框選。

可從任一螢幕開始框選；每次擷取限定在起始螢幕內，不拼接跨螢幕影像。掛圖儲存於 `~/Library/Application Support/Clipline/Screenshots`，從掛圖列丟棄會移至垃圾桶。預設只收納 Clipline 擷取的圖片；系統截圖接管及剪貼簿圖片監看仍為選用功能。

## 圖片標記（0.3.0）

長按掛圖即可開啟 Clipline 原生標記編輯器；錄影仍開啟既有裁剪編輯器。工具列提供矩形、橢圓、線條、箭頭、文字／泡泡文字、畫筆、螢光筆、遮罩（馬賽克／模糊／實色）、放大鏡、步驟、表情符號、聚光燈與備註。選取工具後在圖片上拖曳建立；步驟與圖章可點擊建立。手形工具可選取、移動與調整物件；橡皮擦移除整個標記。

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

釘選完成按鈕會將標記平面化並安全回存原圖，再更新掛圖縮圖；原圖若已被外部變更會拒絕覆寫。支援單張 PNG、JPEG、TIFF、HEIC 回存，其他格式請另存 PNG／JPEG。**回存後無法重新編輯個別標記**；需要保留原圖時使用「另存圖片」。另存不會標記原圖已儲存，也不允許藉原圖路徑、符號連結或硬連結繞過安全回存。複製與分享只使用目前渲染圖片。關閉、切換圖片或正常結束 App 時，有未存變更會詢問保留／捨棄／取消；儲存失敗會保留編輯器。

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
scripts/build-app.sh
open build/Clipline.app
```

The app bundle contains Apple silicon and Intel binaries. The optional runtime was tested on Apple silicon with macOS 26.5.1; its Intel installation has not been verified. Local builds use ad-hoc signing unless a signing identity is supplied; they are not Apple-notarized. Rebuilding may require granting screen-recording permission again.

## Attribution and license

Based on Tendedero by Alejandro Buján. Original source copyright and MIT terms are retained in [LICENSE](LICENSE). Clipline is an independent fork and is not endorsed by the original author. Clipline uses its own name and original icon; upstream promotional artwork is not used.
