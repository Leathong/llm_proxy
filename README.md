# LLM Proxy

本地 LLM API 代理工具，支持规则配置、请求改写、多 Endpoint 负载均衡与日志分析。

## 核心功能

### 代理服务
- 在本地启动 HTTP/HTTPS 代理服务器，拦截发往 LLM API 的请求
- 支持 OpenAI（`/v1/chat/completions`）和 Anthropic（`/v1/messages`）API 格式
- 自动处理 CORS 预检请求，返回 `/v1/models` 模型列表
- SSE 流式响应透传，客户端断开时自动取消上游请求

### 规则配置
- **模型映射**：自定义模型 ID → 目标模型 ID，客户端无感知切换模型
- **多 Endpoint 负载均衡**：每条规则可绑定多个 Endpoint，Round-Robin 轮询分发
- **Thinking 参数注入**：支持注入 `thinking.type`、`reasoning_effort` 等扩展参数（适用于 Claude 等模型），URL 查询参数 `?thinking=high|max` 优先级高于规则配置
- **分组管理**：按分组（Tab）组织规则，支持启用/禁用、复制（另存为）

### 日志系统
- **实时日志**：内存环形缓冲区（500 条），实时显示请求状态、耗时、TTFB、错误信息
- **文件日志**：请求/响应按 `模型名_endpointId.log` 写入磁盘，支持离线分析
- **日志分析**：解析 `.log` 文件，支持关键词搜索、模型/目标筛选、正倒序切换
- **统计摘要**：请求总数、成功/失败数、P50/P70/P90/最慢/平均耗时、TTFB 统计、Token 用量（输入/输出/缓存命中率）

### 设置与证书
- 代理端口配置、系统代理开关
- **HTTPS 支持**：一键生成自签名 RSA 2048 证书（有效期 10 年），配置 SAN 域名
- 全局 Endpoint 池管理（URL + API Key），规则可从中复用
- Hosts 修改指引（弹窗说明如何信任证书和配置域名解析）

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3（macOS / Windows 桌面端） |
| 状态管理 | Riverpod 3（AsyncNotifier） |
| 路由 | GoRouter（声明式路由 + ShellRoute） |
| 数据库 | Drift（SQLite ORM） |
| 序列化 | Freezed + json_serializable |
| 持久化 | SharedPreferences |
| 桌面特性 | window_manager + tray_manager（系统托盘） |
| 架构 | Clean Architecture（presentation / domain / data） |

## 项目结构

```
lib/
├── main.dart                  # 入口：初始化数据库、窗口、托盘、ProviderScope
├── app/
│   └── router.dart            # GoRouter 路由配置（5 个页面 + NavigationRail）
├── core/
│   ├── database/              # Drift 数据库定义（rules / endpoints / rule_endpoints 三表）
│   ├── errors/                # 统一错误模型（Failure sealed class）
│   └── theme/                 # Material 3 主题
└── features/
    ├── proxy/                 # 代理服务核心
    │   ├── data/datasources/  # ProxyServerDataSource（HttpServer 生命周期管理）
    │   ├── domain/services/   # RuleMatcher / RequestTransformer / RequestForwarder / RequestRouter / ProxyLogger
    │   └── presentation/      # DashboardPage（启停控制 + 状态显示）
    ├── rules/                 # 规则配置
    │   ├── domain/entities/   # Rule / EndpointConfig 实体
    │   ├── data/repositories/ # DriftRuleRepository（CRUD + 数据迁移）
    │   └── presentation/      # ConfigPage + RuleEditDialog
    ├── logs/                  # 日志系统
    │   ├── domain/entities/   # LogEntry / FileLogEntry 实体
    │   ├── data/              # RingBuffer / LogFileWriter / LogFileParser
    │   └── presentation/      # LogPage（实时） + FileLogPage（文件分析）
    └── settings/              # 设置
        ├── domain/entities/   # AppSettings 实体
        ├── data/datasources/  # SettingsLocalDataSource（SharedPreferences）
        └── presentation/      # SettingsPage（端口/证书/Endpoint 管理）
```

## 快速开始

### 环境要求
- Flutter SDK >= 3.11
- macOS 或 Windows 桌面开发环境
- OpenSSL（用于证书生成，macOS 自带）

### 运行

```bash
# 安装依赖
flutter pub get

# 生成代码（Drift / Freezed / Riverpod / json_serializable）
dart run build_runner build --delete-conflicting-outputs

# 启动应用（macOS）
flutter run -d macos

# 启动应用（Windows）
flutter run -d windows
```

### 构建

```bash
# macOS 发布包
flutter build macos --release

# Windows 发布包
flutter build windows --release
```

## 使用说明

### 1. 配置 Endpoint
在「设置与证书」页面添加上游 API 的 Endpoint（URL + API Key），例如：
- `https://api.openai.com` + OpenAI API Key
- `https://api.anthropic.com` + Anthropic API Key

### 2. 创建规则
在「配置管理」页面创建规则：
- **自定义模型 ID**：客户端请求时使用的模型名（如 `my-gpt-4`）
- **目标模型 ID**：实际转发给上游的模型名（如 `gpt-4`）
- **绑定 Endpoint**：从全局池中选择一个或多个 Endpoint
- **Thinking 模式**：可选注入 thinking 参数

### 3. 启动代理
在「仪表盘」页面启动代理服务（默认端口 8080）。

### 4. 配置客户端
将 LLM 客户端的 API Base URL 指向 `http://localhost:8080`（或 HTTPS `https://localhost:8080`），使用规则中配置的自定义模型 ID 发起请求即可。

### 5. HTTPS 代理（可选）
如需代理 HTTPS 请求（如 `https://api.openai.com`），需在设置页面：
1. 配置证书 SAN 域名（如 `api.openai.com`）
2. 生成自签名证书
3. 修改系统 hosts 将域名指向 `127.0.0.1`
4. 信任生成的 CA 证书

## 许可证

MIT License