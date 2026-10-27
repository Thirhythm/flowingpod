# FlowingPod

基于哔哩哔哩和网易云音乐的在线音乐播放器（Flutter / Android）。

> [!NOTE]
> 应用功能均基于哔哩哔哩官方 API 与本地实现的网易云音乐 weapi 请求开发，不需要部署额外的网易云 API 服务，也不会将用户的数据披露给第三方。

## 功能

- [x] 双音源音频播放（哔哩哔哩 / 网易云音乐）
- [x] 账号登录
  - [x] 哔哩哔哩手机号验证登录 / 二维码登录
  - [x] 网易云音乐手机号验证登录 / 二维码登录
- [x] 双音源搜索
- [x] 歌单管理
  - [x] 本地歌单（内置「我喜欢的音乐」）
  - [x] 哔哩哔哩收藏夹
  - [x] 网易云音乐歌单
  - [x] 批量删除、添加到歌单、拖动排序
- [x] 收藏歌曲并选择加入的歌单
- [x] 历史记录
- [x] Android 媒体控制
- [x] 音效/均衡器
- [x] 深色模式

> [!IMPORTANT]
> 网易云音乐功能通过原生 `weapi` 加密直连官方接口，无需部署额外服务。若网络环境无法访问 `music.163.com`，相关功能将不可用。

> [!WARNING]
> 若同设备扫码登录失败请确保本应用保持运行，可在登录时激活本应用小窗以保证顺利登录。

## 技术栈

- **状态管理**：[flutter_riverpod](https://pub.dev/packages/flutter_riverpod) 3.x（`Notifier` / `AsyncNotifier`，无代码生成）
- **网络**：`dio` + 自实现 Cookie Jar（`SharedPreferences` 持久化）+ WBI 签名 + 极验人机验证（`webview_flutter`）
- **网易云**：本地 `weapi` 加密（AES-CBC + RSA，`pointycastle`）直连 `music.163.com`，无需额外服务
- **播放**：`just_audio`（仅加载音频流）+ Android 音效管线（`AndroidEqualizer` 均衡器 / `AndroidLoudnessEnhancer` 响度增强）
- **后台与通知**：`audio_service`（Android 前台服务 + MediaStyle 通知）
- **音频焦点**：`audio_session`
- **其他**：`cached_network_image`、`qr_flutter`、`intl`、`crypto`

## 目录结构

```
lib/
├── main.dart                 启动：构建 API 客户端、音频服务，注入 ProviderScope
├── app.dart                  MaterialApp（主题、中文本地化）
├── core/
│   ├── api/                  端点表、Dio 客户端、Cookie Jar、WBI 签名、异常
│   ├── models/               领域模型（媒体条目、用户、音轨、播放状态…）
│   └── utils/                时长/数量格式化、图片 URL、文本清理
├── data/
│   ├── repositories/         认证、搜索、视频、收藏夹、历史、最近播放
│   └── services/             音频播放服务（audio_service handler）
├── state/                    Riverpod providers / controllers
├── features/                 页面（shell、home、search、player、login、library、profile、settings）
├── widgets/                  复用组件（迷你播放栏、播放列表、收藏面板…）
└── theme/                    Material 3 主题
```

> [!NOTE]
> release 打包时请自行配置签名，详见 https://docs.flutter.cn/deployment/android/ 。
