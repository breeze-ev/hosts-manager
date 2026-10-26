# 更新日志

[English](CHANGELOG.en.md)

## 0.1.0-beta (6) - 2026-10-26

首个公开 beta 版本。

- 通过配置管理 `/etc/hosts`：一键切换、多配置组合启用、结构化列表编辑与源码编辑。
- 实时应用、写入前冲突与重复检测、自动带时间戳备份并支持还原。
- 可选的静默后台写入助手（经签名校验的特权 Helper）。
- 中文与英文界面，支持浅色 / 深色外观。
- 无遥测、无网络访问、无第三方统计。
- 开源准备：公开 bundle identifier、共享 scheme、MIT 许可证、双语文档、CI 与官网。
- Helper 签名校验改为从自身签名推导受信任团队，贡献者可以使用自己的团队证书构建。

### 打包

- 分别提供 arm64（Apple Silicon）与 x86_64（Intel）DMG，附 sha256 校验文件。
- beta 版本为 ad-hoc 签名，Gatekeeper 解决办法见 README 安装说明。
