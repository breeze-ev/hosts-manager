<p align="center">
<img height="256" src="website/assets/hosts-manager-icon.png">
</p>

<h1 align="center">Hosts Manager</h1>

<p align="center">Hosts Manager 是一款 <b>现代化</b> 的 macOS hosts 文件管理工具。</p>

Hosts Manager 用于管理 `/etc/hosts` 中的域名与 IP 映射，主要有两个用途：为前后端开发配置本地域名映射，以及屏蔽指定应用或域名的网络连接。

- **按项目管理映射**：通过配置文件的方式组织映射规则，可按项目或场景一键切换、组合启用，多人协作时还能方便地分享配置。
- **两种编辑方式**：结构化列表编辑与 hosts 源码编辑并存，随个人习惯选择。
- **修改即备份**：每次写入自动备份，防止误改丢失；同时支持配置的导入与导出。

## 截图

<p align="center">
<img src="website/assets/hosts-manager-main.png" alt="Hosts Manager 主界面">
</p>

## 功能

- 配置式管理 hosts，一键切换
- 组合式管理，多个配置可同时启用并合并写入
- 支持配置的导入与导出
- Swift 原生编写（SwiftUI + Swift）
- 结构化列表编辑与 `/etc/hosts` 源码编辑
- 写入前冲突与重复检测
- 启用配置变更后实时应用
- 自动生成带时间戳的备份并支持还原
- 可选的静默后台写入助手
- 中文与英文界面
- 无遥测、无网络访问、无第三方统计

## 环境要求

- macOS 26 或更高版本
- 构建需要 Xcode 26.6 或更高版本

## 安装说明

从 [Releases](https://github.com/breeze-ev/hosts-manager/releases) 页面下载与你的 Mac 芯片匹配的 DMG：

| 文件 | 适用机型 |
| --- | --- |
| `Hosts-Manager-*-arm64.dmg` | Apple Silicon（M 系列芯片） |
| `Hosts-Manager-*-x86_64.dmg` | Intel 芯片 |

不确定芯片型号？点击左上角苹果菜单 → 关于本机，"芯片"一栏显示 Apple M 系列则下载 arm64，显示 Intel 则下载 x86_64。

安装步骤：

1. 双击打开下载的 DMG 文件。
2. 将 **Hosts Manager** 拖入 **Applications** 文件夹。
3. 从"应用程序"中启动 Hosts Manager。

## 从源码构建

```bash
git clone https://github.com/breeze-ev/hosts-manager.git
cd hosts-manager
open hosts-manager.xcodeproj
```

在 Signing & Capabilities 中为 `hosts-manager` 和 `HostsManagerHelper` 两个 Target 选择你自己的开发团队。应用与 Helper 必须使用同一团队签名，Helper 才能校验调用方。

也可以使用命令行构建：

```bash
xcodebuild build \
  -project hosts-manager.xcodeproj \
  -scheme hosts-manager \
  -destination 'platform=macOS' \
  -derivedDataPath build
```

## 使用说明

首次启动会创建只读的“系统”配置和可编辑的默认配置。在“设置”中启用后台写入助手后，应用可以静默写入 `/etc/hosts`；每次写入前都会自动备份当前文件，备份保存在 Application Support 目录。

## 发布打包

`scripts/build-dmg.sh` 负责归档、签名并分别生成 arm64 与 x86_64 两个 DMG。版本号、build 号与 Team ID 默认从 Xcode 项目中读取，无需手动传参：

```bash
./scripts/build-dmg.sh           # Developer ID 签名 + 公证（需要付费开发者证书）
./scripts/build-dmg.sh --dev     # Apple Development 签名、跳过公证，适合本地自用（推荐）
./scripts/build-dmg.sh --adhoc   # ad-hoc 签名、跳过公证，无需证书（注意：后台写入助手不可用，见下）
```

公证需要设置 `APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID` 和 `APPLE_API_KEY_PATH` 环境变量；只想跳过公证可传 `--skip-notarize`。产物输出到 `dist/` 目录，并附带 sha256 校验文件。

> **注意签名方式**：后台写入助手通过 SMAppService 注册，而系统的“登录项与扩展”批准与代码签名身份绑定。ad-hoc 签名没有稳定身份，开关能打开但守护进程永远不会真正注册，App 会持续提示“后台写入助手不可用”。本地自用请用 `--dev`（钥匙串里有免费的 Apple Development 证书即可），正式发布用 Developer ID。

## 文档

- [English README](README.en.md)
- [更新日志](CHANGELOG.md)
- [贡献指南](CONTRIBUTING.md)
- [安全说明](SECURITY.md)
- [隐私说明](PRIVACY.md)

## 许可证

Hosts Manager 以 [MIT License](LICENSE) 发布。
