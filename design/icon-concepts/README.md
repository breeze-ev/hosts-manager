# Hosts Manager 图标方案

面向 Hosts Manager 的 6 套候选图标，统一为 1024×1024 矢量源文件（macOS 圆角方形画布），可任选一套继续打磨。

## 方案

1. `orbit.svg` — 深蓝轨道：延续现有抽象锚点方向，深海军蓝底 + 蓝光环 + 绿色节点，稳重、耐看、小尺寸辨识度高。
2. `aurora.svg` — 极光玻璃：蓝紫青渐变 + 白色毛玻璃面板，两个节点与箭头表达“主机名 → IP”的映射，现代 macOS 风格。
3. `flat.svg` — 扁平双色：奶油底色 + 墨蓝图形，圆点（域名）经箭头到达方块（IP），扁平极简，16px 依然清楚。
4. `neon.svg` — 霓虹终端：近黑底 + 等宽字体 hosts 行，绿色启用行与光标，开发工具气质强烈。
5. `liquid.svg` — 液态玻璃：经典 macOS 光泽蓝 + 白色网络节点，圆润立体，贴近系统应用质感。
6. `prism.svg` — 棱镜双色：靛蓝到青绿渐变 + 白色轨道，珊瑚与薄荷两颗节点，色彩更年轻有冲击力。

## 文件

- `*.svg` — 唯一矢量设计源。
- `previews/*.png` — 512px 预览图。
- `export/*-1024.png` — 1024px 导出图，可放入 `Assets.xcassets/AppIcon.appiconset` 或 `HostsManager.iconset`。
- `preview.html` — 浏览器/Quick Look 可打开的对比页。

## 生成

```bash
node render.js
```

脚本使用 `@resvg/resvg-js`（参考 `/tmp/hosts-icon-build/node_modules`），需要字体时已开启 `loadSystemFonts`。
