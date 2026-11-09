<div align="center">
  <img width="160" height="160" src="assets/branding/xmplus.png" alt="XMPlus">
  <h1>XMPlus</h1>
  <p>使用 Flutter 开发的喜马拉雅第三方下载与收听客户端</p>

  [![Android CI](https://github.com/teikengstudio/XMPlus/actions/workflows/android.yml/badge.svg)](https://github.com/teikengstudio/XMPlus/actions/workflows/android.yml)
  [![GitHub release](https://img.shields.io/github/v/release/teikengstudio/XMPlus)](https://github.com/teikengstudio/XMPlus/releases/latest)
  [![GitHub downloads](https://img.shields.io/github/downloads/teikengstudio/XMPlus/total)](https://github.com/teikengstudio/XMPlus/releases)
  [![License](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue)](LICENSE)
</div>

<br/>

## 适配平台

- 多账号登录、专辑搜索、播放队列、在线收听和听时记录。
- 下载任务、本地媒体管理、可选转码与音频标签；自动下载需单独启用。
- Android 安装包内含源码构建的 FFmpeg / FFprobe 和 LAME，支持原始流保存、MP3、M4A、M4B、FLAC、标签及封面处理。
- 备份设置、书架、历史和可选账号信息；含登录凭据的备份未加密，请妥善保管。
- 播放与下载设置、持久音频地址缓存、主题和 GitHub 稳定版更新检查。


## 下载

从 [Releases](https://github.com/teikengstudio/XMPlus/releases) 下载。

## 登录与获取 Cookie

在 XMPlus 的「账号」页面选择「短信登录」，按提示完成安全验证并输入短信验证码；也可以选择「Cookie 登录」，导入自己账号的登录信息。

### 获取自己的请求 Cookie

1. 在官方客户端登录自己的账号。使用本机抓包工具（例如 Reqable 或 Charles）查看该客户端发往 `*.ximalaya.com` 的请求；HTTPS 请求需要按工具说明配置代理和信任证书。打开个人页面或查询听时，让客户端产生登录后的请求。
2. 查看请求头中的 `Cookie`，确认同一条请求中包含 `1&_token` 和 `1&_device`。复制整个 Cookie 值即可，不要复制响应头中的 `Set-Cookie`，也不要混用不同账号或设备的字段。
3. 抓取结束后关闭代理并移除仅为本次抓包安装的证书。若设备或客户端无法查看 HTTPS 请求，使用 XMPlus 的短信登录。

也可以在电脑浏览器登录 [喜马拉雅官网](https://www.ximalaya.com/)，按 `F12` 打开开发者工具的「网络 / Network」，刷新页面，选择发往喜马拉雅的请求，在「请求标头 / Request Headers」中查找 `Cookie`。**只有其中同时含有上述两个字段时才能尝试导入**；网页 Cookie 不一定包含客户端所需的登录信息，缺少字段时请使用短信登录或自己的官方客户端请求，不要编造设备 ID。

### 导入与检查

在「账号 → Cookie 登录」粘贴 Cookie 或包含它的请求头，提交后等待账号核验。下面只是格式示例，不能用于登录：

```text
1&_token=123456789&EXAMPLE_TOKEN; 1&_device=android&EXAMPLE_DEVICE_ID&3.4.10;
```

`1&_token` 的值包含数字 UID 和令牌；`1&_device` 中第二段是原设备 ID。请保留自己的原始值，不要替换成示例中的版本或设备信息。导入成功后，账号页会显示账号和已核验的可用听时。

- 提示缺少令牌或原设备 ID：检查两个字段是否完整，尤其是令牌中的 `&` 和设备字段的分段。
- 提示登录信息无效或已过期：在官方客户端确认登录状态，重新获取同一账号的 Cookie，或改用短信登录。
- 提示网络或听时核验失败：先检查网络；网页登录成功不代表该账号能通过客户端的听时接口核验。

Cookie 相当于登录凭据，只在自己信任的设备上处理。不要把真实 Cookie、包含账号信息的备份或请求诊断日志上传到 issue、聊天或公共网盘；反馈时只提供脱敏后的错误提示。


## 编译

工具链：Flutter 3.47.9 / Dart 3.13.7、Java 25、Gradle 9.9.0、AGP 9.5.1、Kotlin 2.4.21；Android `compileSdk` / `targetSdk` 为 36，NDK 为 28.2.13676358。依赖版本和校验值锁定在 `pubspec.lock`。

先在 Linux x86_64 安装 Android NDK 28.2.13676358、`jq`、`make`、`tar`、`sha256sum`（构建 x86_64 时还需 `nasm`），再运行：

```sh
flutter pub get --enforce-lockfile
bash tool/build_android_media.sh
flutter build apk --release --split-per-abi --no-pub
```

正式 Android 构建必须配置 JKS 签名环境变量：`ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_PASSWORD`、`ANDROID_KEY_ALIAS`。签名材料不得提交到仓库。

Windows 构建命令见 `licenses/native/SOURCE-MATERIALS-INCOMPLETE.txt`。


## 许可与安全

项目按 [AGPL-3.0-or-later](LICENSE) 提供。第三方组件保留各自许可与版权声明，详见 [NOTICE](NOTICE) 和 `licenses/`；发布时须履行对应源码提供义务。

本项目与喜马拉雅无隶属、合作或背书关系。请遵守平台规则、版权及当地法律。反馈问题时请附应用版本、系统版本和复现步骤；不要上传 Cookie、令牌、账号备份或签名私钥。

## 致谢与交流

- [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)：界面与 Windows runner 参考。
- [LinuxDo](https://linux.do/)
- [Flutter](https://flutter.dev/) · [media-kit](https://github.com/media-kit/media-kit) · [Dio](https://pub.dev/packages/dio) · [FFmpeg](https://ffmpeg.org/)
- [GitHub Issues](https://github.com/teikengstudio/XMPlus/issues) · [Telegram](https://t.me/+csbfHjIyqkoyNDA1)
