const I18N = {
  zh: {
    title: "Hosts Manager",
    list: "列表", source: "源码", apply: "应用",
    searchProfile: "搜索配置", searchEntry: "搜索主机名或 IP",
    profiles: "配置", newProfile: "新建配置", backups: "备份", settings: "设置",
    current: "当前", notApplied: "未应用",
    metaEnabled: "{0} 条启用 · {1} 条停用 · {2}",
    enabledCount: "{0} 条启用",
    sort: "排序", import: "导入", addEntry: "新增条目",
    colState: "状态", colIP: "IP 地址", colHost: "主机名", colDesc: "描述",
    emptyProfile: "此配置暂无条目", emptyProfileHint: "点击“新增条目”开始添加",
    emptySearch: "没有匹配的条目", emptySearchHint: "换个关键词试试",
    sourcePreview: "/etc/hosts 预览", comment: "注释", uncomment: "取消注释",
    sourceMeta: "{0} 条启用 · {1} 条注释",
    backupHint: "写入前会自动备份当前 hosts 文件",
    backupsTitle: "备份", backupsSub: "每次写入前自动生成时间戳备份，可预览并还原。",
    preview: "预览", restore: "还原",
    settingsTitle: "设置", settingsSub: "管理默认行为、外观与备份策略。",
    defaultProfile: "默认配置", defaultProfileDesc: "启动时选中的配置",
    startup: "启动行为", startupDesc: "打开 App 时的默认视图",
    lastView: "上次视图", profilesView: "配置列表",
    retention: "备份保留数量", retentionDesc: "超过数量后自动清理旧备份",
    lang: "界面语言", langDesc: "中文 / English", followSystem: "跟随系统",
    appearance: "外观", appearanceDesc: "亮色、暗色或跟随系统",
    auto: "自动", light: "浅色", dark: "深色",
    edit: "编辑", duplicate: "复制", delete: "删除", toggle: "切换",
    conflict: "冲突", duplicateName: "重复",
    applyTitle: "应用“{0}”", restoreTitle: "还原备份",
    cancel: "取消", confirmApply: "确认应用", confirmRestore: "确认还原",
    done: "完成", save: "保存",
    backupNote: "写入前将自动备份当前 /etc/hosts 到备份目录，可随时还原。",
    restoreNote: "将用备份文件覆盖当前 hosts，覆盖前也会先备份当前内容。",
    writing: "正在写入 /etc/hosts…", restoring: "正在还原…",
    appliedOk: "已应用“{0}”到 /etc/hosts",
    backupPath: "已备份原文件到 {0}",
    applyErrorConflict: "检测到冲突或重复条目，未写入 /etc/hosts。请先解决后重试。",
    restoredOk: "已还原备份 {0}",
    addEntryTitle: "新增条目", editEntryTitle: "编辑条目",
    ipLabel: "IP 地址", hostLabel: "主机名", descLabel: "描述",
    hostPlaceholder: "输入主机名后回车添加", addHost: "添加",
    enableLabel: "启用此条目", ipRequired: "请输入有效的 IP 地址",
    hostRequired: "请至少添加一个主机名",
    deleted: "已删除条目", added: "已添加条目", updated: "已更新条目",
    created: "已创建新配置", importDemo: "导入（演示）", commented: "已注释全部条目", uncommented: "已取消注释",
    before: "写入前", after: "写入后"
  },
  en: {
    title: "Hosts Manager",
    list: "List", source: "Source", apply: "Apply",
    searchProfile: "Search profiles", searchEntry: "Search hostname or IP",
    profiles: "Profiles", newProfile: "New Profile", backups: "Backups", settings: "Settings",
    current: "Active", notApplied: "Not applied",
    metaEnabled: "{0} enabled · {1} disabled · {2}",
    enabledCount: "{0} enabled",
    sort: "Sort", import: "Import", addEntry: "New Entry",
    colState: "State", colIP: "IP Address", colHost: "Hostname", colDesc: "Description",
    emptyProfile: "No entries in this profile", emptyProfileHint: "Click “New Entry” to get started",
    emptySearch: "No matching entries", emptySearchHint: "Try a different keyword",
    sourcePreview: "/etc/hosts Preview", comment: "Comment", uncomment: "Uncomment",
    sourceMeta: "{0} enabled · {1} commented",
    backupHint: "The current hosts file is backed up before writing",
    backupsTitle: "Backups", backupsSub: "Timestamped backups are created before each write. Preview or restore anytime.",
    preview: "Preview", restore: "Restore",
    settingsTitle: "Settings", settingsSub: "Manage defaults, appearance, and backup policy.",
    defaultProfile: "Default Profile", defaultProfileDesc: "Profile selected at launch",
    startup: "Startup Behavior", startupDesc: "Default view when the app opens",
    lastView: "Last view", profilesView: "Profiles",
    retention: "Backup Retention", retentionDesc: "Older backups are cleaned up beyond this count",
    lang: "Language", langDesc: "中文 / English", followSystem: "Follow system",
    appearance: "Appearance", appearanceDesc: "Light, dark, or follow system",
    auto: "Auto", light: "Light", dark: "Dark",
    edit: "Edit", duplicate: "Duplicate", delete: "Delete", toggle: "Toggle",
    conflict: "Conflict", duplicateName: "Duplicate",
    applyTitle: "Apply “{0}”", restoreTitle: "Restore Backup",
    cancel: "Cancel", confirmApply: "Confirm Apply", confirmRestore: "Confirm Restore",
    done: "Done", save: "Save",
    backupNote: "The current /etc/hosts will be backed up to the backup folder before writing.",
    restoreNote: "The backup will overwrite the current hosts file. The current file is also backed up first.",
    writing: "Writing to /etc/hosts…", restoring: "Restoring…",
    appliedOk: "Applied “{0}” to /etc/hosts",
    backupPath: "Backed up the original file to {0}",
    applyErrorConflict: "Conflicts or duplicates detected, so /etc/hosts was not written. Resolve them and retry.",
    restoredOk: "Restored backup {0}",
    addEntryTitle: "New Entry", editEntryTitle: "Edit Entry",
    ipLabel: "IP Address", hostLabel: "Hostname", descLabel: "Description",
    hostPlaceholder: "Type a hostname and press Enter", addHost: "Add",
    enableLabel: "Enable this entry", ipRequired: "Enter a valid IP address",
    hostRequired: "Add at least one hostname",
    deleted: "Entry deleted", added: "Entry added", updated: "Entry updated",
    created: "New profile created", importDemo: "Import (demo)", commented: "Commented all entries", uncommented: "Uncommented",
    before: "Before", after: "After"
  }
};

const DATA = {
  profiles: [
    {
      id: "dev", name: "开发环境", nameEn: "Development", active: true, updated: "刚刚",
      entries: [
        { id: "d1", ip: "127.0.0.1", hosts: ["localhost"], desc: "本机回环地址", on: true, system: true },
        { id: "d2", ip: "::1", hosts: ["localhost"], desc: "IPv6 回环地址", on: true, system: true },
        { id: "d3", ip: "127.0.0.1", hosts: ["api.dev.local"], desc: "本地 API 服务", on: true },
        { id: "d4", ip: "192.168.1.50", hosts: ["mysql.db.local"], desc: "开发数据库", on: true },
        { id: "d5", ip: "10.0.0.12", hosts: ["cache.redis.local"], desc: "本地缓存节点", on: false },
        { id: "d6", ip: "127.0.0.1", hosts: ["staging.website.com","www.staging.website.com"], desc: "预发布站点", on: true },
        { id: "d7", ip: "0.0.0.0", hosts: ["ads.example.com"], desc: "屏蔽广告域名", on: false }
      ]
    },
    {
      id: "prod", name: "生产环境", nameEn: "Production", active: false, updated: "昨天",
      entries: [
        { id: "p1", ip: "127.0.0.1", hosts: ["localhost"], desc: "本机回环地址", on: true, system: true },
        { id: "p2", ip: "::1", hosts: ["localhost"], desc: "IPv6 回环地址", on: true, system: true },
        { id: "p3", ip: "203.0.113.24", hosts: ["api.example.com"], desc: "生产 API", on: true },
        { id: "p4", ip: "198.51.100.7", hosts: ["staging.website.com"], desc: "预发布站点", on: true },
        { id: "p5", ip: "198.51.100.8", hosts: ["api.example.com"], desc: "备用 API 节点", on: true },
        { id: "p6", ip: "198.51.100.9", hosts: ["db.example.com"], desc: "生产数据库", on: false }
      ]
    },
    {
      id: "local", name: "本地测试", nameEn: "Local Testing", active: false, updated: "3 天前",
      entries: [
        { id: "l1", ip: "127.0.0.1", hosts: ["localhost"], desc: "本机回环地址", on: true, system: true },
        { id: "l2", ip: "::1", hosts: ["localhost"], desc: "IPv6 回环地址", on: true, system: true },
        { id: "l3", ip: "127.0.0.1", hosts: ["test.local"], desc: "本地测试域名", on: true },
        { id: "l4", ip: "127.0.0.1", hosts: ["mock.api.local"], desc: "Mock API", on: true },
        { id: "l5", ip: "127.0.0.1", hosts: ["mock.api.local"], desc: "重复条目", on: true }
      ]
    },
    {
      id: "default", name: "默认", nameEn: "Default", active: false, updated: "5 天前",
      entries: [
        { id: "df1", ip: "127.0.0.1", hosts: ["localhost"], desc: "本机回环地址", on: true, system: true },
        { id: "df2", ip: "::1", hosts: ["localhost"], desc: "IPv6 回环地址", on: true, system: true },
        { id: "df3", ip: "255.255.255.255", hosts: ["broadcasthost"], desc: "广播地址", on: true, system: true }
      ]
    }
  ],
  backups: [
    { name: "hosts-2026-08-19-103012.hosts", time: "今天 10:30", size: "1.2 KB", note: "应用“开发环境”前自动备份" },
    { name: "hosts-2026-08-18-210544.hosts", time: "昨天 21:05", size: "1.1 KB", note: "应用“生产环境”前自动备份" },
    { name: "hosts-2026-08-16-091233.hosts", time: "3 天前 09:12", size: "1.3 KB", note: "应用“本地测试”前自动备份" }
  ]
};

const AVATAR_COLORS = [
  ["#0a7af5","#4aa0ff"],["#34c759","#63e27b"],["#ff9f0a","#ffc24d"],["#af52de","#cf87f5"],["#ff375f","#ff6b86"],["#5ac8fa","#8edcff"]
];

const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => Array.from(document.querySelectorAll(sel));

let state = {
  theme: "dark",
  lang: "zh",
  langMode: "system",
  view: "profiles",
  currentProfile: "dev",
  editMode: "list",
  entryQuery: "",
  profileQuery: "",
  loading: true,
  sort: "default",
  modal: { mode: null },
  formEntry: null,
  formHosts: [],
  formIP: "",
  formDesc: "",
  formOn: true
};

function t(key, ...args){
  const dict = I18N[state.lang] || I18N.zh;
  let s = dict[key] != null ? dict[key] : (I18N.zh[key] != null ? I18N.zh[key] : key);
  args.forEach((a, i) => { s = String(s).split("{" + i + "}").join(String(a)); });
  return s;
}
function esc(s){ return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); }
function avatarColors(i){ return AVATAR_COLORS[i % AVATAR_COLORS.length]; }
function profileName(p){ return state.lang === "en" ? (p.nameEn || p.name) : p.name; }
function currentProfile(){ return DATA.profiles.find(p => p.id === state.currentProfile); }
function profileById(id){ return DATA.profiles.find(p => p.id === id); }
function profileEnabledCount(p){ return p.entries.filter(e => e.on).length; }
function enabledLines(p){ return p.entries.filter(e => e.on).map(e => {
  const hosts = e.hosts.join(" ");
  return e.ip.padEnd(18) + " " + hosts + (e.desc ? " # " + e.desc : "");
}); }

function icon(name){
  const I = {
    check: '<svg viewBox="0 0 24 24" width="16" height="16"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    alert: '<svg viewBox="0 0 24 24" width="16" height="16"><path d="M12 3l10 18H2zM12 10v4m0 3v.01" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    backup: '<svg viewBox="0 0 24 24" width="16" height="16"><path d="M12 5v8m0 0l-3.5-3.5M12 13l3.5-3.5M5 15v3a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-3" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    edit: '<svg viewBox="0 0 24 24" width="15" height="15"><path d="M4 20l1-4L16.5 4.5a2.1 2.1 0 0 1 3 3L8 19l-4 1z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/></svg>',
    trash: '<svg viewBox="0 0 24 24" width="15" height="15"><path d="M5 7h14M10 7V5h4v2M8 7l1 12h6l1-12" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    copy: '<svg viewBox="0 0 24 24" width="15" height="15"><rect x="8" y="8" width="12" height="12" rx="2.5" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M5 16V6a2 2 0 0 1 2-2h9" fill="none" stroke="currentColor" stroke-width="1.6"/></svg>',
    apply: '<svg viewBox="0 0 24 24" width="14" height="14"><path d="M12 3v11m0 0l-4-4m4 4l4-4" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>'
  };
  return I[name] || "";
}

/* Conflict / duplicate detection */
function hostIssues(entries){
  const byHost = {};
  entries.forEach(e => e.hosts.forEach(h => { (byHost[h] = byHost[h] || []).push(e); }));
  const out = [];
  Object.entries(byHost).forEach(([host, list]) => {
    if(list.length < 2) return;
    const ips = new Set(list.map(e => e.ip));
    out.push({ host, kind: ips.size > 1 ? "conf" : "dup", count: list.length });
  });
  return out;
}
function entryFlagMap(p){
  const map = {};
  hostIssues(p.entries).forEach(issue => {
    p.entries.forEach(e => { if(e.hosts.includes(issue.host)) map[e.id] = issue.kind; });
  });
  return map;
}
function issuesText(p){
  const issues = hostIssues(p.entries.filter(e => e.on));
  const labels = { conf: t("conflict"), dup: t("duplicateName") };
  return issues.map(i => i.host + " · " + labels[i.kind]).join("；") || "—";
}

/* ---------- i18n ---------- */
function applyI18n(){
  $$("[data-i18n]").forEach(el => {
    const v = I18N[state.lang] && I18N[state.lang][el.dataset.i18n];
    if(v != null) el.textContent = v;
  });
  $$("[data-i18n-ph]").forEach(el => {
    const v = I18N[state.lang] && I18N[state.lang][el.dataset.i18nPh];
    if(v != null) el.setAttribute("placeholder", v);
  });
}
function syncLangSeg(){
  $$("#langSeg .seg-btn").forEach(b => b.classList.toggle("active", b.dataset.lang === state.langMode));
}
function setLang(mode){
  state.langMode = mode;
  state.lang = mode === "en" ? "en" : "zh";
  document.documentElement.lang = state.lang === "en" ? "en" : "zh-CN";
  syncLangSeg();
  applyI18n();
  renderAll();
  renderSettings();
}

/* ---------- Sidebar ---------- */
function renderSidebar(){
  const list = $("#profileList");
  if(state.loading){
    list.innerHTML = Array.from({length:4}).map(() => `
      <div class="sk-profile"><div class="skeleton sk-avatar"></div><div><div class="skeleton sk-line"></div><div class="skeleton sk-line sk-sub"></div></div></div>`).join("");
    return;
  }
  const q = state.profileQuery.trim().toLowerCase();
  const filtered = DATA.profiles.filter(p => (profileName(p)).toLowerCase().includes(q));
  list.innerHTML = filtered.map((p, i) => {
    const colors = avatarColors(DATA.profiles.indexOf(p));
    const on = profileEnabledCount(p);
    return `
      <div class="profile-item ${p.id===state.currentProfile?"active":""}" data-id="${p.id}">
        <div class="avatar" style="background:linear-gradient(140deg,${colors[1]},${colors[0]})">${esc(profileName(p).slice(0,1))}</div>
        <div class="p-info">
          <div class="p-name">${esc(profileName(p))}</div>
          <div class="p-meta">${esc(t("enabledCount", on))}</div>
        </div>
        <button class="p-apply" data-apply="${p.id}" title="${esc(t("apply"))}">${icon("apply")}</button>
      </div>`;
  }).join("");
}

/* ---------- Entries ---------- */
function renderProfileHead(){
  const p = currentProfile();
  $("#profileName").textContent = profileName(p);
  $("#activeBadge").textContent = p.active ? t("current") : t("notApplied");
  $("#activeBadge").classList.toggle("badge-active", p.active);
  const enabled = profileEnabledCount(p);
  const off = p.entries.length - enabled;
  $("#profileMeta").textContent = t("metaEnabled", enabled, off, p.updated);
}

function skeletonRows(){
  return Array.from({length:5}).map(() => `
    <div class="sk-row">
      <span class="skeleton sk-line" style="width:34px;height:22px;border-radius:999px"></span>
      <span class="skeleton sk-line"></span>
      <span class="skeleton sk-chip"></span>
      <span class="skeleton sk-line"></span>
      <span></span>
    </div>`).join("");
}

function rowHtml(e, flags){
  const flag = flags[e.id];
  const hosts = e.hosts.map(h => `<span class="chip ${e.on?"":"off"}">${esc(h)}</span>`).join("");
  const flagBadge = flag ? (flag === "conf"
    ? `<span class="flag-badge warn" title="${esc(t("conflict"))}">${icon("alert")}</span>`
    : `<span class="flag-badge danger" title="${esc(t("duplicateName"))}">${icon("copy")}</span>`)
    : "";
  return `
    <div class="entry-row ${e.system?"system":""} ${flag==="conf"?"conflict":""} ${flag==="dup"?"duplicate":""}" data-id="${e.id}">
      <div class="col-state">
        <button class="switch ${e.on?"on":""}" data-toggle="${e.id}" ${e.system?"disabled":""} aria-label="${esc(t("toggle"))}"></button>
      </div>
      <div class="col-ip" title="${esc(e.ip)}">${esc(e.ip)}</div>
      <div class="col-host">${hosts}</div>
      <div class="col-desc">${esc(e.desc)}</div>
      <div class="col-actions">
        ${flagBadge}
        <button class="icon-btn" data-edit="${e.id}" title="${esc(t("edit"))}">${icon("edit")}</button>
        <button class="icon-btn danger" data-del="${e.id}" ${e.system?"disabled":""} title="${esc(t("delete"))}">${icon("trash")}</button>
      </div>
    </div>`;
}

function renderEntries(){
  const p = currentProfile();
  const q = state.entryQuery.trim().toLowerCase();
  let filtered = p.entries.filter(e => {
    if(!q) return true;
    return (e.ip + " " + e.hosts.join(" ") + " " + e.desc).toLowerCase().includes(q);
  });
  if(state.sort === "name") filtered = [...filtered].sort((a, b) => a.ip.localeCompare(b.ip, undefined, {numeric:true}));
  const flags = entryFlagMap(p);
  const tbody = $("#entryRows");
  if(state.loading){
    tbody.innerHTML = skeletonRows();
  } else {
    tbody.innerHTML = filtered.map(e => rowHtml(e, flags)).join("");
  }
  $("#emptyProfile").hidden = !(p.entries.length === 0 && !state.loading);
  $("#emptySearch").hidden = !(p.entries.length > 0 && filtered.length === 0 && !state.loading);
}

/* ---------- Source view ---------- */
function renderSource(){
  const p = currentProfile();
  const lines = p.entries.map(e => {
    const hosts = e.hosts.join(" ");
    const desc = e.desc ? " # " + e.desc : "";
    return (e.on ? "" : "# ") + e.ip.padEnd(18) + " " + hosts + desc;
  }).join("\n");
  $("#sourceArea").value = lines;
  $("#sourceMeta").textContent = t("sourceMeta", profileEnabledCount(p), p.entries.length - profileEnabledCount(p));
}

/* ---------- Backups / settings ---------- */
function renderBackups(){
  const list = $("#backupList");
  list.innerHTML = DATA.backups.map(b => `
    <div class="backup-item glass">
      <div class="backup-ic">${icon("backup")}</div>
      <div class="backup-info">
        <div class="backup-name">${esc(b.name)}</div>
        <div class="backup-meta">${esc(b.time)} · ${esc(b.size)} · ${esc(b.note)}</div>
      </div>
      <div class="backup-actions">
        <button class="btn btn-ghost" data-preview="${esc(b.name)}">${esc(t("preview"))}</button>
        <button class="btn btn-primary" data-restore="${esc(b.name)}">${esc(t("restore"))}</button>
      </div>
    </div>`).join("");
}

function renderSettings(){
  const sel = $("#setDefaultProfile");
  sel.innerHTML = DATA.profiles.map(p => `<option value="${p.id}" ${p.id===state.currentProfile?"selected":""}>${esc(profileName(p))}</option>`).join("");
  const startup = $("#setStartupView");
  startup.innerHTML = `<option value="last">${esc(t("lastView"))}</option><option value="profiles">${esc(t("profilesView"))}</option><option value="backups">${esc(t("backups"))}</option>`;
  syncLangSeg();
}

/* ---------- Apply flow ---------- */
function buildDiffHtml(p){
  const lines = enabledLines(p);
  const diff = lines.map(l => `<span class="add">+ ${esc(l)}</span>`).join("\n");
  const disabled = p.entries.filter(e => !e.on);
  const retained = disabled.map(e => `<span class="meta"># ${esc(e.ip + " " + e.hosts.join(" "))}</span>`).join("\n");
  return diff + (retained ? "\n" + retained : "");
}

function diffResultHtml(p){
  const after = enabledLines(p).map(l => `<span class="add">+ ${esc(l)}</span>`).join("\n");
  const before = "127.0.0.1\tlocalhost\n::1\tlocalhost\n255.255.255.255\tbroadcasthost"
    .split("\n").map(l => `<span class="del">- ${esc(l)}</span>`).join("\n");
  return `<div class="diff"><span class="seg-label">${esc(t("before"))}</span>${before}
<span class="seg-label">${esc(t("after"))}</span>${after || '<span class="meta">—</span>'}</div>`;
}

function fakeBackupName(){
  const d = new Date();
  const p = n => String(n).padStart(2, "0");
  return "hosts-" + d.getFullYear() + p(d.getMonth()+1) + p(d.getDate()) + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()) + ".hosts";
}

/* ---------- Modal ---------- */
function showModal(){ $("#modalBackdrop").hidden = false; }
function hideModal(){ $("#modalBackdrop").hidden = true; state.modal = { mode: null }; }

function entryFormHtml(){
  return `
    <div class="entry-form">
      <div class="field">
        <label>${esc(t("ipLabel"))}</label>
        <input id="f-ip" value="${esc(state.formIP)}" placeholder="127.0.0.1 / ::1" spellcheck="false">
      </div>
      <div class="field">
        <label>${esc(t("hostLabel"))}</label>
        <div class="chip-input">
          <div class="chip-list" id="f-hosts"></div>
          <div class="chip-input-row">
            <input id="f-host" placeholder="${esc(t("hostPlaceholder"))}" spellcheck="false">
            <button class="btn btn-ghost" data-add-host>${esc(t("addHost"))}</button>
          </div>
        </div>
        <div class="form-error" id="f-host-err" hidden>${esc(t("hostRequired"))}</div>
      </div>
      <div class="field">
        <label>${esc(t("descLabel"))}</label>
        <input id="f-desc" value="${esc(state.formDesc)}">
      </div>
      <div class="field-inline">
        <label>${esc(t("enableLabel"))}</label>
        <button class="switch ${state.formOn?"on":""}" id="f-on"></button>
      </div>
    </div>`;
}

function renderFormChips(){
  const list = $("#f-hosts");
  if(!list) return;
  list.innerHTML = state.formHosts.map((h, i) =>
    `<span class="chip">${esc(h)}<button class="chip-x" data-rm-host="${i}" aria-label="remove">×</button></span>`).join("");
}

function renderModal(){
  const m = state.modal;
  const title = $("#modalTitle");
  const body = $("#modalBody");
  const foot = $("#modalFoot");
  const p = currentProfile();
  if(m.mode === "entry-form"){
    title.textContent = state.formEntry ? t("editEntryTitle") : t("addEntryTitle");
    body.innerHTML = entryFormHtml();
    foot.innerHTML = `<button class="btn btn-ghost" data-modal-cancel>${esc(t("cancel"))}</button><button class="btn btn-primary" data-modal-confirm data-action="save-entry">${esc(t("save"))}</button>`;
    renderFormChips();
    return;
  }
  if(m.mode === "apply-confirm"){
    title.textContent = t("applyTitle", profileName(p));
    body.innerHTML = `<div class="backup-note">${icon("backup")}<span>${esc(t("backupNote"))}</span></div><div class="diff">${buildDiffHtml(p)}</div>`;
    foot.innerHTML = `<button class="btn btn-ghost" data-modal-cancel>${esc(t("cancel"))}</button><button class="btn btn-primary" data-modal-confirm data-action="apply-write">${esc(t("confirmApply"))}</button>`;
    return;
  }
  if(m.mode === "apply-writing"){
    title.textContent = t("applyTitle", profileName(p));
    body.innerHTML = `<div class="writing-state"><div class="spinner"></div><p>${esc(t("writing"))}</p></div>`;
    foot.innerHTML = "";
    return;
  }
  if(m.mode === "apply-result"){
    title.textContent = t("applyTitle", profileName(p));
    if(m.ok){
      body.innerHTML = `<div class="status-ok">${icon("check")}<span>${esc(t("appliedOk", profileName(p)))}</span></div>
        <div class="status-sub">${esc(t("backupPath", m.backupName))}</div>${diffResultHtml(p)}`;
    } else {
      body.innerHTML = `<div class="status-err">${icon("alert")}<span>${esc(t("applyErrorConflict"))}</span></div>
        <div class="status-sub">${esc(issuesText(p))}</div>`;
    }
    foot.innerHTML = `<button class="btn btn-primary" data-modal-cancel>${esc(t("done"))}</button>`;
    return;
  }
  if(m.mode === "restore-confirm"){
    title.textContent = t("restoreTitle");
    body.innerHTML = `<div class="backup-note">${icon("backup")}<span>${esc(t("restoreNote"))}</span></div><div class="diff mono">${esc(m.backup.name)}</div>`;
    foot.innerHTML = `<button class="btn btn-ghost" data-modal-cancel>${esc(t("cancel"))}</button><button class="btn btn-primary" data-modal-confirm data-action="restore-write">${esc(t("confirmRestore"))}</button>`;
    return;
  }
  if(m.mode === "restore-writing"){
    title.textContent = t("restoreTitle");
    body.innerHTML = `<div class="writing-state"><div class="spinner"></div><p>${esc(t("restoring"))}</p></div>`;
    foot.innerHTML = "";
    return;
  }
  if(m.mode === "restore-result"){
    title.textContent = t("restoreTitle");
    body.innerHTML = `<div class="status-ok">${icon("check")}<span>${esc(t("restoredOk", m.backup.name))}</span></div>`;
    foot.innerHTML = `<button class="btn btn-primary" data-modal-cancel>${esc(t("done"))}</button>`;
    return;
  }
}

function openEntryForm(id){
  const p = currentProfile();
  const e = id ? p.entries.find(x => x.id === id) : null;
  state.formEntry = e ? e.id : null;
  state.formHosts = e ? [...e.hosts] : [];
  state.formIP = e ? e.ip : "";
  state.formDesc = e ? e.desc : "";
  state.formOn = e ? e.on : true;
  state.modal = { mode: "entry-form" };
  renderModal();
  showModal();
}

function addFormHost(){
  const inp = $("#f-host");
  const val = inp && inp.value.trim();
  if(!val) return;
  if(!state.formHosts.includes(val)) state.formHosts.push(val);
  if(inp) inp.value = "";
  $("#f-host-err").hidden = true;
  renderFormChips();
}

function saveEntry(){
  const ip = $("#f-ip").value.trim();
  const desc = $("#f-desc").value.trim();
  if(!ip){ showToast(t("ipRequired"), "err"); return; }
  if(!state.formHosts.length){ $("#f-host-err").hidden = false; return; }
  const p = currentProfile();
  if(state.formEntry){
    const e = p.entries.find(x => x.id === state.formEntry);
    e.ip = ip; e.hosts = [...state.formHosts]; e.desc = desc; e.on = state.formOn; e.updated = "刚刚";
    showToast(t("updated"), "ok");
  } else {
    p.entries.push({ id: "new" + Date.now(), ip, hosts: [...state.formHosts], desc, on: state.formOn, system: false, updated: "刚刚" });
    showToast(t("added"), "ok");
  }
  hideModal();
  renderAll();
}

function beginApply(profileId){
  state.currentProfile = profileId;
  renderAll();
  state.modal = { mode: "apply-confirm" };
  renderModal();
  showModal();
}

function startApplyWrite(){
  state.modal = { mode: "apply-writing" };
  renderModal();
  setTimeout(() => {
    const p = currentProfile();
    const issues = hostIssues(p.entries.filter(e => e.on));
    state.modal = issues.length
      ? { mode: "apply-result", ok: false }
      : { mode: "apply-result", ok: true, backupName: fakeBackupName() };
    renderModal();
  }, 1300);
}

function openRestoreModal(name){
  const backup = DATA.backups.find(b => b.name === name) || { name };
  state.modal = { mode: "restore-confirm", backup };
  renderModal();
  showModal();
}

function startRestoreWrite(){
  state.modal = { mode: "restore-writing", backup: state.modal.backup };
  renderModal();
  setTimeout(() => {
    state.modal = { mode: "restore-result", backup: state.modal.backup };
    renderModal();
  }, 1200);
}

function showToast(msg, type){
  const tm = $("#toast");
  tm.hidden = false;
  tm.innerHTML = `<span class="t-ic" style="color:${type==="ok"?"var(--green)":"var(--red)"}">${type==="ok"?icon("check"):icon("alert")}</span><span>${esc(msg)}</span>`;
  clearTimeout(tm._timer);
  tm._timer = setTimeout(() => { tm.hidden = true; }, 2600);
}

/* ---------- View switching ---------- */
function setView(view){
  state.view = view;
  $$(".view").forEach(v => v.hidden = true);
  $("#view-" + view).hidden = false;
  $$(".nav-item").forEach(n => n.classList.toggle("active", n.dataset.view === view));
  $("#toolbar").style.display = view === "profiles" ? "" : "none";
  if(view === "backups") renderBackups();
  if(view === "settings") renderSettings();
}

function renderAll(){
  renderSidebar();
  renderProfileHead();
  renderEntries();
  renderSource();
}

/* ---------- Events ---------- */
document.addEventListener("click", e => {
  const t = e.target;

  const profileItem = t.closest(".profile-item");
  if(profileItem && !t.closest(".p-apply")){
    state.currentProfile = profileItem.dataset.id;
    renderAll();
    return;
  }
  const applyBtn = t.closest(".p-apply");
  if(applyBtn){
    e.stopPropagation();
    beginApply(applyBtn.dataset.apply);
    return;
  }

  const toggle = t.closest(".switch");
  if(toggle && !toggle.disabled && toggle.id !== "f-on"){
    const p = currentProfile();
    const entry = p.entries.find(x => x.id === toggle.dataset.toggle);
    if(entry){ entry.on = !entry.on; entry.updated = "刚刚"; renderAll(); }
    return;
  }

  if(t.closest("#f-on")){
    state.formOn = !state.formOn;
    t.closest("#f-on").classList.toggle("on", state.formOn);
    return;
  }
  const addHost = t.closest("[data-add-host]");
  if(addHost){ addFormHost(); return; }
  const rmHost = t.closest("[data-rm-host]");
  if(rmHost){
    state.formHosts.splice(parseInt(rmHost.dataset.rmHost, 10), 1);
    renderFormChips();
    return;
  }

  const edit = t.closest("[data-edit]");
  if(edit){ openEntryForm(edit.dataset.edit); return; }
  const del = t.closest("[data-del]");
  if(del && !del.disabled){
    const p = currentProfile();
    const idx = p.entries.findIndex(x => x.id === del.dataset.del);
    if(idx > -1){ p.entries.splice(idx, 1); renderAll(); showToast(t("deleted"), "ok"); }
    return;
  }

  if(t.closest("#applyBtn")){ beginApply(state.currentProfile); return; }
  if(t.closest("#addEntryBtn")){ openEntryForm(null); return; }
  if(t.closest("#newProfileBtn")){
    const n = DATA.profiles.length + 1;
    DATA.profiles.push({
      id: "p" + n, name: "新配置 " + n, nameEn: "Profile " + n, active: false, updated: "刚刚",
      entries: [
        { id: "s1", ip: "127.0.0.1", hosts: ["localhost"], desc: "本机回环地址", on: true, system: true },
        { id: "s2", ip: "::1", hosts: ["localhost"], desc: "IPv6 回环地址", on: true, system: true }
      ]
    });
    state.currentProfile = DATA.profiles[DATA.profiles.length - 1].id;
    renderAll(); renderSettings();
    showToast(t("created"), "ok");
    return;
  }
  if(t.closest("#importBtn")){ showToast(t("importDemo"), "ok"); return; }
  if(t.closest("#sortBtn")){
    state.sort = state.sort === "name" ? "default" : "name";
    renderEntries();
    return;
  }

  if(t.closest("#editProfileBtn") || t.closest("#duplicateProfileBtn")){
    showToast(t("editDemo") || t("edit"), "ok");
    return;
  }

  const preview = t.closest("[data-preview]");
  if(preview){ openRestoreModal(preview.dataset.preview); return; }
  const restore = t.closest("[data-restore]");
  if(restore){ openRestoreModal(restore.dataset.restore); return; }

  const closeBtn = t.closest("#modalClose");
  if(closeBtn){ hideModal(); return; }
  if(t.id === "modalBackdrop"){ hideModal(); return; }
  const cancelBtn = t.closest("[data-modal-cancel]");
  if(cancelBtn){ hideModal(); return; }
  const confirmBtn = t.closest("[data-modal-confirm]");
  if(confirmBtn){
    const action = confirmBtn.dataset.action;
    if(action === "save-entry") saveEntry();
    else if(action === "apply-write") startApplyWrite();
    else if(action === "restore-write") startRestoreWrite();
    return;
  }

  const segBtn = t.closest(".seg-btn");
  if(segBtn && t.closest("#editModeSeg")){
    state.editMode = segBtn.dataset.mode;
    $$("#editModeSeg .seg-btn").forEach(b => b.classList.toggle("active", b === segBtn));
    $("#entryTable").hidden = state.editMode !== "list";
    $("#sourceView").hidden = state.editMode !== "source";
    return;
  }
  if(segBtn && t.closest("#themeSeg")){
    $$("#themeSeg .seg-btn").forEach(b => b.classList.toggle("active", b === segBtn));
    state.theme = segBtn.dataset.theme === "auto" ? "dark" : segBtn.dataset.theme;
    document.body.dataset.theme = state.theme;
    return;
  }
  if(segBtn && t.closest("#langSeg")){
    setLang(segBtn.dataset.lang);
    return;
  }

  const nav = t.closest(".nav-item");
  if(nav){ setView(nav.dataset.view); return; }

  if(t.closest("#toggleThemeBtn")){
    state.theme = state.theme === "dark" ? "light" : "dark";
    document.body.dataset.theme = state.theme;
    return;
  }

  if(t.closest("#commentBtn")){
    const p = currentProfile();
    p.entries.forEach(e => e.on = false);
    renderAll(); showToast(t("commented"), "ok");
    return;
  }
  if(t.closest("#uncommentBtn")){
    const p = currentProfile();
    p.entries.forEach(e => { if(!e.system) e.on = true; });
    renderAll(); showToast(t("uncommented"), "ok");
    return;
  }

  const step = t.closest(".stepper-btn");
  if(step){
    let v = parseInt($("#retentionVal").textContent, 10);
    v = Math.max(1, Math.min(100, v + parseInt(step.dataset.step, 10)));
    $("#retentionVal").textContent = v;
    return;
  }
});

document.addEventListener("input", e => {
  if(e.target.id === "entrySearch"){ state.entryQuery = e.target.value; renderEntries(); }
  if(e.target.id === "profileSearch"){ state.profileQuery = e.target.value; renderSidebar(); }
});

document.addEventListener("keydown", e => {
  if(e.target.id === "f-host" && e.key === "Enter"){
    e.preventDefault();
    addFormHost();
  }
});

document.addEventListener("change", e => {
  if(e.target.id === "setDefaultProfile"){
    state.currentProfile = e.target.value;
    renderAll();
  }
});

/* Init */
document.body.dataset.theme = state.theme;
renderAll();
setView("profiles");
applyI18n();
setTimeout(() => { state.loading = false; renderAll(); }, 900);
