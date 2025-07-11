# Momentum Flutter

一個跨平台的 **主動式生產力助理**，結合 Google Calendar、智慧通知與 AI 拖延教練，協助你如期完成每日任務。

---

## ✨ 特色總覽

1. **Google 帳號一站式登入**
   - OAuth 權限涵蓋 Calendar 讀寫，免繁瑣設定即可同步行事曆。
2. **雙向日曆同步**
   - 每次啟動 / 恢復 App 時自動與 Google Calendar 同步當日事件。
   - Firestore 雲端儲存，離線亦可瀏覽快取。
3. **雙重智慧通知**
   - 任務開始前 `10` 分鐘發送第一則提醒。
   - 任務開始後 `5` 分鐘再次追蹤，並於你開始任務後自動取消後續通知。
4. **AI 拖延教練 (Procrastination Coach)**
   - 透過雲端函式呼叫 OpenAI，與使用者對話找出拖延原因並給予行動方案。
   - 自動產生聊天摘要、統計對話 token 及延遲，回寫 Firestore 供研究分析。
5. **多平台支援**：iOS / Android / Web / macOS / Windows / Linux。
6. **實驗數據儀表**
   - 事件開始延遲、聊天迴合數、平均 API 延遲…等指標一應俱全。

---

## 🖼️ App 截圖

>（可於 `docs/` 目錄放置截圖並在此引用）

---

## 🔧 技術架構

| Layer            | Technology                                   |
|------------------|----------------------------------------------|
| Frontend         | Flutter 3.*, Provider 狀態管理              |
| Auth             | Firebase Authentication (Google Sign-In)     |
| Data Store       | Cloud Firestore                              |
| Notifications    | flutter_local_notifications + Firebase Cloud Messaging |
| Calendar Sync    | Google Calendar API                          |
| AI Coach         | Firebase Cloud Functions (Python) + OpenAI   |
| Analytics        | 自訂實驗欄位寫入 Firestore                   |

---

## 📂 專案結構

```text
lib/
  ├── models/          資料模型 (Event, ChatMessage, Enums…)
  ├── providers/       狀態管理 (EventsProvider, ChatProvider…)
  ├── services/        平台服務 (Auth, Calendar, Notification…)
  ├── screens/         UI 版面 (SignIn, Home, Chat…)
  └── widgets/         可重用元件
functions/             Python Cloud Functions 來源碼
android/ ios/ macos/ … Flutter 原生殼層設定
```

---

## 🚀 快速開始

### 1. 前置需求

- Flutter 3.x (stable channel)
- Firebase CLI `>= 12`
- Python 3.10 (部署 Cloud Functions)

### 2. 下載並安裝套件

```bash
# Clone
$ git clone https://github.com/your-org/momentum_flutter.git
$ cd momentum_flutter

# Flutter 依賴
$ flutter pub get
```

### 3. Firebase 設定

1. 建立 Firebase 專案並啟用 *Authentication → Google*、*Firestore*、*Cloud Functions*。
2. 下載 `google-services.json`（Android）及 `GoogleService-Info.plist`（iOS/macOS），放入相對應目錄。
3. 執行 `flutterfire configure` 產生 `lib/firebase_options.dart`（已附檔可跳過）。
4. 更新 Firestore 規則 `firestore.rules` 以符合研究需求。

### 4. Cloud Functions（可選，啟用 AI 教練）

```bash
$ cd functions
$ python3 -m venv venv && source venv/bin/activate
$ pip install -r requirements.txt
# 設定 OPENAI_API_KEY 環境變數後部署
$ firebase deploy --only functions
```

### 5. 執行 App

```bash
$ flutter run -d <device_id>
```

> Web: `flutter run -d chrome`  /  Desktop: `flutter run -d macos` 等。

---

## 🧪 測試

```bash
# 執行 Widget 測試
$ flutter test
```

---

## 🤝 貢獻指南

1. Fork → 新分支 → Commit → Pull Request。
2. Commit message 使用 [Conventional Commits](https://www.conventionalcommits.org/)。
3. 新功能請附上對應測試與文件。

---

## 📄 授權

本專案採用 MIT License 釋出，詳見 [`LICENSE`](LICENSE)。

---

## 🙏 致謝

- [Flutter](https://flutter.dev/)
- [Firebase](https://firebase.google.com/)
- [OpenAI](https://openai.com/)

> 若此專案對你有幫助，歡迎 Star ⭐️ 支持！
