# Hosts Manager

Hosts Manager 是一款 macOS 应用，用于通过配置管理 `/etc/hosts`：支持结构化列表编辑、源码编辑、实时应用、自动备份，以及经过签名校验的后台写入助手。

项目当前已经开源，但尚未发布经过 Developer ID 签名的 DMG。你可以先用 Xcode 在本地构建运行，也可以等待第一个正式发布版本。

![Hosts Manager](website/assets/hosts-manager-main.png)

## 功能

- 基于配置管理 hosts，一键切换
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

`scripts/build-dmg.sh` 负责归档、签名、公证并生成 Universal DMG。它面向已拥有 Developer ID 身份的维护者，需要 `APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID` 和 `APPLE_API_KEY_PATH` 环境变量。

```bash
./scripts/build-dmg.sh --team-id YOUR_TEAM_ID --version 0.1.0
```

## 文档

- [English README](README.md)
- [贡献指南](CONTRIBUTING.md)
- [安全说明](SECURITY.md)
- [隐私说明](PRIVACY.md)

## 许可证

Hosts Manager 以 [MIT License](LICENSE) 发布。
