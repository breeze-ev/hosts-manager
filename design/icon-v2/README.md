# Hosts Manager 图标（抽象版）

面向 Hosts Manager 的抽象“网络路由锚点”图标：深海军蓝圆角方底上，一条蓝色开口圆环代表地址空间/网络，开口处嵌着一枚绿色节点，表示主机名“锚定”到 IP 映射。仅两个图形元素，无文字，小尺寸可辨识。

## 文件

- `icon-abstract.svg` — 1024×1024 矢量源文件，唯一设计源。
- `HostsManager.iconset/` — 10 张标准 PNG（16 到 1024，含 @2x）。
- `HostsManager.icns` — macOS 应用图标，由 Xcode `actool` 从 AppIcon.appiconset 编译生成。
- `preview.png` — 512px 预览图。

## 生成链路

1. 编辑 `icon-abstract.svg`。
2. 用 `@resvg/resvg-js` 按 1024 渲染，再缩放出各尺寸 PNG（脚本参考 `/tmp/hosts-icon-build/render.js`）。
3. 将 PNG 放入 `HostsManager.iconset/`，用 `iconutil` 或 `actool` 组装 `.icns`。

## 说明

- 本机 macOS 26 的 `iconutil` 对 iconset→icns 方向校验异常，因此 `.icns` 改由 Xcode 的 `actool` 编译产出（与系统 App 图标同构：16/32/128/1024 四种规格）。
- `Assets.xcassets/AppIcon.appiconset` 未改动；如需让 App 直接使用新图标，把 `HostsManager.iconset/` 里的 PNG 覆盖进去即可。
- 如需在 Icon Composer.app 中编辑：用 Icon Composer 打开 `icon-abstract.svg`（或把 PNG/SVG 拖入新文档），再“另存为”Icon Composer 文档（`.icon`）。`.icon` 的内部包结构当前无公开样例可离线还原，故不在本目录预生成。
