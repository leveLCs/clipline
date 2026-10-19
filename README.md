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

## Build and test

Requires Apple's Command Line Tools or Xcode. Apple Vision needs no third-party runtime.

Option OCR needs a one-time installation with [uv](https://docs.astral.sh/uv/) available:

```sh
scripts/install-ddddocr.sh
```

This downloads a private Python 3.13 and pinned ddddocr dependencies into `~/Library/Application Support/Clipline/OCR`. It does not change system Python or depend on the checkout, pyenv, or uv after installation. Install separately on each Mac for its architecture; copying only the app does not copy the optional runtime. ddddocr starts on demand, takes about a second per capture on the tested Mac, and stops after 15 seconds if unresponsive. Its default model targets CAPTCHA-style images; long, multiline Traditional Chinese is better handled by Vision.

The complete test suite below requires that optional runtime to be installed, and a logged-in macOS session for Vision and the private test pasteboard.

```sh
scripts/test.sh
swift scripts/check-strings.swift
scripts/build-app.sh
open build/Clipline.app
```

The app bundle contains Apple silicon and Intel binaries. The optional runtime was tested on Apple silicon with macOS 26.5.1; its Intel installation has not been verified. Local builds use ad-hoc signing unless a signing identity is supplied; they are not Apple-notarized. Rebuilding may require granting screen-recording permission again.

## Attribution and license

Based on Tendedero by Alejandro Buján. Original source copyright and MIT terms are retained in [LICENSE](LICENSE). Clipline is an independent fork and is not endorsed by the original author. Clipline uses its own name and original icon; upstream promotional artwork is not used.
