# AGENTS.md

本文件定义项目的 Swift 开发规范。所有 AI Agent、开发人员在新增、修改代码时必须遵守。

如果现有代码与本规范冲突，优先按照本规范逐步整理，但不得擅自破坏现有功能。

---

# 1. 基本开发原则

- 使用原生 Swift 和 SwiftUI 开发。
- 优先使用 Apple 官方框架和系统 API。
- 不引入不必要的第三方依赖。
- 不使用 WebView、Electron 或其他 Web 技术实现原生 UI 能力。
- 优先采用现代 Swift 语法和 API。
- 保持代码简洁、可读、可维护。
- 避免过度设计，不为简单功能引入复杂架构。
- 不要将多个不相关的功能集中在一个文件中。
- 修改代码时优先保持现有架构和设计风格。

# 2. 文件与目录组织

## 2.1 一个文件一个主要类型

原则上，一个 Swift 文件只声明一个主要类型。

例如：

```text
Models/
├── User.swift
├── Article.swift
└── Order.swift

Services/
├── UserService.swift
└── NetworkService.swift
```

不允许将多个无关的 Class、Struct、Enum 集中在一个文件中。

允许以下情况：

- 一个类型及其紧密关联的辅助类型。
- 一个类型的 extension。
- 仅供当前文件使用的私有辅助类型。
- 紧密关联的协议及其实现。

## 2.2 文件命名

- 使用 PascalCase。
- 文件名与主要类型名称保持一致。
- 不使用拼音命名。
- 不使用无意义的缩写。

例如：

```text
UserService.swift
UserViewModel.swift
NetworkManager.swift
AppSettings.swift
```

## 2.3 目录组织

按照职责和业务功能组织代码。

推荐结构：

```text
Project/
├── App/
│   ├── MainApp.swift
│   └── AppDelegate.swift
│
├── Core/
│   ├── Constants/
│   ├── Extensions/
│   ├── Utilities/
│   └── Errors/
│
├── Models/
│
├── Services/
│
├── ViewModels/
│
├── Views/
│   ├── Components/
│   ├── Home/
│   └── Settings/
│
├── Resources/
│
└── SupportingFiles/
```

不要为了形式而创建过多目录。

目录仅用于组织文件，不代表 Swift 命名空间或模块。

# 3. 类型与命名规范

统一使用以下命名规则：

| 类型 | 命名规范 | 示例 |
|---|---|---|
| Class | PascalCase | UserService |
| Struct | PascalCase | UserModel |
| Enum | PascalCase | NetworkError |
| Protocol | PascalCase | DataProviding |
| Function | camelCase | fetchUser() |
| Variable | camelCase | userName |
| Constant | camelCase | maxRetryCount |
| Enum Case | camelCase | case success |
| Property | camelCase | isLoading |

其他要求：

- 类型名称使用明确的业务含义。
- 方法名称应体现行为。
- Boolean 属性优先使用 is、has、should、can 等前缀。
- 避免使用单字母变量，循环索引等局部场景除外。
- 不使用匈牙利命名法。
- 不使用下划线连接变量名称。

# 4. 访问控制

合理使用 Swift 访问控制。

默认规则：

- `private`：类型内部实现细节。
- `fileprivate`：仅在确实需要文件级访问时使用。
- `internal`：模块内部使用，Swift 默认级别。
- `public`：需要暴露给其他模块的 API。
- `open`：仅在确实需要允许外部模块继承或重写时使用。

要求：

- 优先使用最小访问权限。
- 不要无理由声明 public。
- 不要为了方便调用而随意扩大访问范围。
- 不要将内部实现暴露给外部模块。

# 5. Swift 代码规范

## 5.1 类型设计

- 优先使用 Struct 表达值类型。
- 只有需要引用语义、继承或共享可变状态时才使用 Class。
- 合理使用 Enum 表达有限状态。
- 优先使用不可变属性 `let`。
- 避免不必要的全局变量和单例。
- 避免使用隐式解包可选类型 `!`。
- 优先使用 `guard let` 处理提前退出。
- 避免强制类型转换，优先使用安全类型判断。

## 5.2 Extension

使用 extension 拆分类型的不同职责。

例如：

```swift
struct User {
    let id: Int
    let name: String
}

extension User {
    var displayName: String {
        name
    }
}
```

不要为了拆分代码而创建没有实际意义的 extension。

## 5.3 错误处理

- 使用 Swift Error 协议定义业务错误。
- 使用 `throws` 传递可恢复错误。
- 不允许无理由使用 `try!`。
- 不允许使用 `try?` 静默吞掉重要错误。
- 错误信息应具备明确含义。
- 避免使用字符串代替结构化错误类型。

## 5.4 异步编程

- 优先使用 Swift Concurrency。
- 优先使用 async/await。
- 避免在新代码中引入不必要的 GCD 回调。
- 正确处理 Task 生命周期。
- UI 状态更新必须在 MainActor 上执行。
- 避免创建没有必要的非结构化 Task。
- 注意避免数据竞争。

# 6. SwiftUI 开发规范

## 6.1 View 组织

- 一个 View 文件原则上只声明一个主要 View。
- 复杂页面拆分为独立子 View。
- 可复用组件放在 Views/Components。
- 不要将整个应用界面集中在一个 Swift 文件中。
- 避免过度拆分简单 View。

## 6.2 状态管理

根据实际场景选择：

- `@State`
- `@Binding`
- `@Observable`
- `@StateObject`（适用于仍采用 ObservableObject 的代码）
- `@ObservedObject`（适用于仍采用 ObservableObject 的代码）
- `@Environment`
- `@EnvironmentObject`（适用于现有 ObservableObject 架构）

新代码优先使用现代 Observation 框架。

不要为了传递少量数据而创建复杂的全局状态管理机制。

## 6.3 View 职责

View 主要负责：

- UI 布局。
- 用户交互。
- 展示状态。
- 响应状态变化。

业务逻辑应放在合适的 Model、Service 或 ViewModel 中。

避免在 View 的 body 中编写复杂业务逻辑。

## 6.4 组件复用

- 相同 UI 结构出现多次时，应考虑提取公共组件。
- 公共组件应具有明确的职责。
- 避免创建只有一行代码且没有复用价值的组件。
- 不要为了复用而牺牲组件的可读性。

## 6.5 Xcode Preview 与 List 兼容性

macOS 26/27 的 SwiftUI Preview 存在已知崩溃：`List` 的 `ForEach` 直接返回自定义复合行时，Preview 宿主可能在 `TableViewListCore_Mac2.swift` 的 `ViewListTree.visitItem` / `OutlineListCoordinator.diffRows` 中触发 `fatalError`。该问题不一定在实际运行 App 时复现。

遇到此问题时必须遵守：

- 保留 `List`，不要用 `ScrollView`、`LazyVStack` 等组件替换它来规避问题。
- 不要删除行视图的业务实现或简化交互来绕过崩溃。
- 仅在 Debug Preview 环境中加入兼容层，生产运行路径不得改变。
- 使用 `AnyView(EmptyView())` 作为 `ForEach` 中自定义行之前的占位视图。
- 同时识别 `XCODE_RUNNING_FOR_PREVIEWS` 和 `XCODE_RUNNING_FOR_PLAYGROUNDS`；Xcode 27 的 Preview 进程可能只设置后者。
- Debug 配置的 `ENABLE_HARDENED_RUNTIME` 必须为 `NO`，否则 Preview 注入的 `__preview.dylib` 可能因签名校验而无法加载；Release 配置仍应为 `YES`。

兼容写法：

```swift
List {
    ForEach(items) { item in
        #if DEBUG
        if isRunningInXcodePreview {
            AnyView(EmptyView())
        }
        #endif
        CustomRow(item: item)
    }
}
```

修改 `List` 或行视图后，必须至少验证一次对应的 `#Preview` 能完成渲染，而不能只确认项目编译通过。

# 7. macOS 原生 UI 规范

本项目以 macOS 原生应用为目标。

必须遵守：

- 优先使用 SwiftUI 原生组件。
- 尊重 macOS 系统交互习惯。
- 优先使用系统提供的 Toolbar、Sidebar、NavigationSplitView、Sheet 等组件。
- 正确使用系统安全区域和窗口布局机制。
- 不要通过硬编码模拟系统原生组件。
- 不要随意覆盖系统默认交互行为。
- 优先使用系统材质、视觉效果和动画。

## 7.1 Liquid Glass

在支持 Liquid Glass 的系统版本中：

- 优先使用 Apple 官方 Liquid Glass API。
- 根据控件的实际语义选择适当的 Glass 样式。
- 不要将普通模糊背景误认为 Liquid Glass。
- 不要重复实现系统已经提供的玻璃效果。
- 避免滥用 Glass，保证内容可读性。
- 注意处理不同 macOS 版本之间的视觉差异。

## 7.2 系统兼容性

- 项目部署版本必须以 Xcode 项目配置为准。
- 使用新系统 API 时必须检查 availability。
- 不允许在不兼容的系统版本上直接调用新 API。
- 对于新旧系统之间的视觉差异，应提供合理的兼容处理。
- 不要仅为了兼容旧系统而牺牲新系统的原生体验。

## 7.3 禁止事项

- 不使用大量自定义绘制模拟原生系统控件。
- 不随意修改系统默认圆角、阴影和材质。
- 不使用定时器模拟本应由系统提供的状态更新机制。
- 不使用固定尺寸强行适配所有窗口大小。
- 不随意使用 NSViewRepresentable，只有 SwiftUI 无法满足需求时才考虑 AppKit。

# 8. 注释规范

- 注释应解释为什么这样实现，而不是重复代码本身。
- 复杂算法、特殊处理和系统兼容逻辑必须添加注释。
- 公共 API 应根据需要添加文档注释。
- 不添加无意义的注释。
- 不保留已经失效的注释。
- 不要随意删除仍然有效的业务说明。

# 9. 代码质量

每次开发必须遵守：

1. 优先复用已有实现。
2. 不要重复实现项目已经具备的功能。
3. 不要随意修改无关文件。
4. 不要引入不必要的依赖。
5. 不要留下无用变量、无用方法和废弃代码。
6. 不要使用空实现掩盖未完成的功能。
7. 不要通过关闭编译检查解决问题。
8. 不要为了通过编译而破坏原有业务逻辑。

# 10. 构建与验证

完成代码修改后：

- 检查代码是否存在编译错误。
- 检查是否存在明显的并发安全问题。
- 检查是否符合当前项目的最低系统版本。
- 尽可能执行 Xcode Build。
- 如果修改了 UI，检查不同窗口尺寸下的显示效果。
- 如果无法完成构建或测试，必须明确说明原因。
- 不允许声称已经通过测试，而实际上没有执行测试。

# 11. Agent 执行要求

开始开发前：

1. 阅读本文件。
2. 阅读相关目录和现有代码。
3. 理解当前项目的架构和命名习惯。
4. 确认是否已有可复用的组件或服务。

开发过程中：

1. 严格遵守本文件规范。
2. 不要擅自改变项目整体架构。
3. 不要为了完成任务而引入不必要的技术方案。
4. 优先选择简单、原生、可维护的实现。

开发完成后：

1. 检查新增文件是否符合目录规范。
2. 检查是否存在多个无关类型集中在一个文件的问题。
3. 检查访问权限是否合理。
4. 执行必要的构建和测试。
5. 汇报修改内容、验证结果以及尚未解决的问题。
