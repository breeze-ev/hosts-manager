const strings = {
  en: {
    navFeatures: "Features",
    navSecurity: "Security",
    navBuild: "Build",
    github: "GitHub",
    eyebrow: "Open source macOS hosts manager",
    heroLead: "Manage `/etc/hosts` with profiles, live apply, source editing, and automatic backups.",
    viewSource: "View Source",
    releases: "Releases",
    statusNote: "Source is public. A signed DMG will be published when Apple release credentials are ready.",
    featuresEyebrow: "Built for daily hosts work",
    featuresTitle: "Profiles instead of manual edits",
    featuresLead: "Keep separate hosts configurations, switch quickly, and see exactly what will be written before it happens.",
    featureProfiles: "Profile switching",
    featureProfilesBody: "Enable one profile or combine several enabled profiles into a single written result.",
    featureCombine: "Combinable profiles",
    featureCombineBody: "Enable several profiles at once and write their merged result in one step.",
    featureImportExport: "Import and export",
    featureImportExportBody: "Move profiles between machines with structured import and export.",
    featureLive: "Real-time apply",
    featureLiveBody: "List edits apply immediately when a profile is enabled, with conflict detection first.",
    featureSource: "Source editing",
    featureSourceBody: "Edit hosts text directly with comment and uncomment actions when you need full control.",
    featureBackups: "Automatic backups",
    featureBackupsBody: "Every write is backed up first and can be previewed or restored later.",
    featureNative: "Native Swift",
    featureNativeBody: "Built with Swift and SwiftUI for macOS.",
    securityEyebrow: "Privileged writes, contained",
    securityTitle: "No broad root access",
    securityLead: "The helper only accepts a signed Hosts Manager caller from the same signing team and performs one validated write operation.",
    securityHelper: "Same-team helper",
    securityHelperBody: "The background writer validates the caller's signature and bundle identifier before serving requests.",
    securityAtomic: "Atomic writes",
    securityAtomicBody: "Hosts content is validated and written atomically while preserving file permissions.",
    securityPrivacy: "No telemetry",
    securityPrivacyBody: "No network calls, no analytics, and no third-party SDKs. Everything stays on your Mac.",
    securityLocal: "Local storage",
    securityLocalBody: "Profiles and backups live in Application Support and are never uploaded.",
    buildEyebrow: "Requirements",
    buildTitle: "macOS 26+",
    buildBody: "Build with Xcode 26.6 or newer. The app and helper use the same signing team for development and distribution.",
    license: "MIT License",
    footerLinks: "Privacy · Security · Contributing"
  },
  zh: {
    navFeatures: "功能",
    navSecurity: "安全",
    navBuild: "构建",
    github: "GitHub",
    eyebrow: "开源的 macOS hosts 管理器",
    heroLead: "通过配置管理 `/etc/hosts`：支持实时应用、源码编辑与自动备份。",
    viewSource: "查看源码",
    releases: "Releases",
    statusNote: "源码已公开；Apple 发布证书就绪后，将提供签名 DMG。",
    featuresEyebrow: "为日常 hosts 工作设计",
    featuresTitle: "用配置替代手动编辑",
    featuresLead: "维护多套 hosts 配置，快速切换，并在写入前看清即将产生的变化。",
    featureProfiles: "配置切换",
    featureProfilesBody: "启用单个配置，或组合多个已启用配置后一次性写入。",
    featureCombine: "组合式管理",
    featureCombineBody: "可同时启用多个配置，并将合并结果一次写入。",
    featureImportExport: "导入与导出",
    featureImportExportBody: "通过结构化导入导出，在不同电脑之间迁移配置。",
    featureLive: "实时应用",
    featureLiveBody: "启用配置后列表编辑立即生效，并先完成冲突检测。",
    featureSource: "源码编辑",
    featureSourceBody: "需要完全控制时，可直接编辑 hosts 文本并快速注释或取消注释。",
    featureBackups: "自动备份",
    featureBackupsBody: "每次写入前自动备份，稍后可预览或还原。",
    featureNative: "Swift 原生",
    featureNativeBody: "使用 Swift 与 SwiftUI 为 macOS 原生构建。",
    securityEyebrow: "有边界的特权写入",
    securityTitle: "不开放宽泛的 root 权限",
    securityLead: "后台助手只接受同一签名团队的 Hosts Manager 调用，并仅执行一次经过校验的写入。",
    securityHelper: "同团队助手",
    securityHelperBody: "后台写入助手在处理请求前会校验调用方的签名与 Bundle ID。",
    securityAtomic: "原子写入",
    securityAtomicBody: "hosts 内容先校验，再原子写入，并保留文件权限。",
    securityPrivacy: "无遥测",
    securityPrivacyBody: "没有网络请求、分析统计或第三方 SDK，所有数据只留在你的 Mac。",
    securityLocal: "本地存储",
    securityLocalBody: "配置与备份保存在 Application Support，永远不会被上传。",
    buildEyebrow: "环境要求",
    buildTitle: "macOS 26+",
    buildBody: "使用 Xcode 26.6 或更高版本构建；开发与发布时，应用与 Helper 使用同一签名团队。",
    license: "MIT License",
    footerLinks: "隐私 · 安全 · 贡献"
  }
};

function applyLanguage(lang) {
  document.documentElement.lang = lang;
  const langStrings = strings[lang] || strings.en;
  for (const [key, value] of Object.entries(langStrings)) {
    const nodes = document.querySelectorAll(`[data-i18n="${key}"]`);
    for (const node of nodes) node.textContent = value;
  }
}

const savedLanguage = localStorage.getItem("hosts-manager-language");
const initialLanguage = savedLanguage || (navigator.language && navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");
applyLanguage(initialLanguage);

const toggle = document.querySelector(".lang-toggle");
if (toggle) {
  toggle.textContent = initialLanguage === "zh" ? "EN" : "中文";
  toggle.addEventListener("click", () => {
    const next = document.documentElement.lang === "zh" ? "en" : "zh";
    localStorage.setItem("hosts-manager-language", next);
    applyLanguage(next);
    toggle.textContent = next === "zh" ? "EN" : "中文";
  });
}
