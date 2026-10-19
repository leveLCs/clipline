# Clipline 擷取設計

使用者已核准：⌘⇧2 框選 OCR，放開滑鼠時按住 ⌘ 則掛上截圖；名稱與圖示由實作者決定。名稱 Clipline，原創深藍底薄荷色框選與文字圖示。

保留原 AppKit / SwiftUI 掛圖功能與 macOS 14 支援。以 ScreenCaptureKit 取得各螢幕靜態畫面，再顯示 AppKit 框選面板；選取鎖定起始螢幕，超出邊界時裁切，第一版不跨螢幕拼接。依實際影像像素尺寸換算 Retina 座標，完成時判斷 mouseUp.modifierFlags。Esc、螢幕配置變更與擷取失敗都清除面板；同一時間只執行一次擷取。

OCR 使用 Vision accurate，優先正體中文與英文。本機處理、不存 OCR 圖片；成功且有文字才更新剪貼簿。取消、無文字、辨識失敗保留剪貼簿。以短暫提示回報成功／無文字，權限與錯誤提供可理解訊息。

圖片存獨立 Clipline/Screenshots 目錄，檔案僅擁有者可讀寫，直接接到 hangCapture 並傳入選取範圍；主動掛圖可在全螢幕 App 顯示。保留既有清除、拖曳與恢復生命週期。避免 watcher 重複接收同檔。

固定擷取熱鍵與既有可調整的掛圖列熱鍵分開註冊；衝突可重試且保留選單入口，不自行修改 TextSniper 設定。獨立 bundle ID io.github.leveLCs.Clipline，不讀寫原 App 偏好與資料。保留 MIT 原作授權，替換原品牌、圖示及未授權文件圖片。

內部審查已完成：納入全螢幕 openedOnPurpose、Inbox 檔案生命週期、多熱鍵分派與註冊失敗清理。

驗收：座標／分流／取消／剪貼簿／檔案測試；真實 Vision 中英文辨識；universal app 建置與簽章；實際 App 內框選 OCR、掛圖與 Esc。未能實測的環境條件如多螢幕須明確記錄。
