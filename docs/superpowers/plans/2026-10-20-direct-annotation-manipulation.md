# 直接調整標記實作計畫

目標：使用者提供的橢圓／箭頭控制點與直接手掌拖移行為。

- [x] 先以 production Canvas 測試未選元素直接拖移（跨工具、筆畫）、點擊不提交、保留框內繪圖，確認舊邏輯失敗。
- [x] 共用命中結果於游標與按下；NSTrackingArea 更新 hover，移動中 closedHand，控制點 resize／crosshair；清除舊 clickTarget 手勢分歧。
- [x] Geometry 提供各元素控制點與實際範圍；藍色白邊圓點，移除通用虛線，原生可存取 X；步驟與退化筆畫縮放測試。
- [x] 檢查全部既有呼叫與測試期待，保留重開可編輯、取消／Undo／Redo；原生滑鼠驗收直接拖移、縮放、文字、X、回存重開。
- [x] 獨立審查、完整測試、語系／固定簽章建置；正常退出舊版、備份安裝、確認啟動與雜湊，更新驗收契約。
- [x] 提交推送；版本與 commit 對應紀錄保存於忽略版控的 build/annotation-interaction-verification/state.json。
