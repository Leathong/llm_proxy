# LLM Proxy

本地 LLM API 代理工具，运行在 macOS / Windows 桌面端。作为中间代理层，拦截客户端（IDE、CLI 工具等）发往 LLM API 的请求，根据用户配置的规则进行**模型映射、参数注入、System Prompt 替换**等操作，然后转发到上游 API 提供商。

## 功能特性

- **请求代理与转发** — 启动本地 HTTP/HTTPS 代理服务器，拦截并转发 LLM API 请求
- **模型映射** — 将客户端请求的模型名映射为上游提供商的实际模型
- **参数注入** — 自动注入 `thinking`、`reasoning_effort` 等推理参数
- **System Prompt 替换** — 按规则替换请求中的 System Prompt
- **多格式支持** — 同时兼容 OpenAI（`/v1/chat/completions`）和 Anthropic（`/v1/messages`）API 格式
- **SSE 流式透传** — 支持流式响应的实时转发与解析
- **请求日志** — 完整的请求/响应日志记录，支持搜索、统计分析和导出
- **HTTPS 支持** — 可生成自签名证书，支持 HTTPS 代理
- **系统托盘** — 关闭窗口时隐藏到系统托盘，后台持续运行

## 系统要求

- **macOS** 10.15 或更高版本
- **Windows** 10 或更高版本
- [Flutter SDK](https://flutter.dev) 3.44.0（通过 [FVM](https://fvm.app) 管理）

## 快速开始

### 环境准备

```bash
# 安装 FVM（如果尚未安装）
dart pub global activate fvm

# 安装项目指定的 Flutter 版本
fvm install
```

### 构建与安装

```bash
# 获取依赖
make get

# 生成代码（Drift、Freezed、Riverpod）
make gen

# 编译 macOS release 版本
fvm flutter build macos --release

# 一键编译并安装到 /Applications
make install
```

### 开发运行

```bash
# 获取依赖并生成代码
make get
make gen

# 以 debug 模式运行
fvm flutter run -d macos
```

## 项目结构

```
lib/
├── main.dart                     # 应用入口
├── app/
│   ├── app.dart                  # MaterialApp 根组件
│   └── router.dart               # GoRouter 路由配置
├── core/
│   ├── database/
│   │   └── app_database.dart     # Drift 数据库定义（7 张表）
│   ├── errors/
│   │   └── failures.dart         # 错误类型定义
│   ├── theme/
│   │   └── app_theme.dart        # Material3 主题
│   └── widgets/
│       └── scaled_switch.dart    # 通用缩放开关组件
└── features/
    ├── proxy/                    # 代理服务模块（核心引擎）
    │   ├── data/datasources/
    │   │   └── proxy_server_datasource.dart  # HTTP/HTTPS 代理服务器
    │   ├── domain/services/
    │   │   ├── request_router.dart           # 请求路由核心
    │   │   ├── rule_matcher.dart             # 规则匹配器
    │   │   ├── request_transformer.dart      # 请求体改写器
    │   │   ├── request_forwarder.dart        # 请求转发器
    │   │   └── provider_format.dart          # API 格式枚举
    │   └── presentation/
    │       └── pages/dashboard_page.dart     # 仪表盘页面
    ├── rules/                    # 规则配置模块
    │   ├── data/repositories/
    │   │   └── drift_rule_repository.dart    # Drift 规则仓库实现
    │   ├── domain/
    │   │   ├── entities/                     # Rule、ModelProvider、SystemPrompt 等实体
    │   │   └── services/
    │   │       └── model_list_service.dart   # 远程模型列表获取
    │   └── presentation/
    │       └── pages/config_page.dart        # 配置管理页面
    ├── logs/                     # 日志模块
    │   ├── data/datasources/
    │   │   ├── log_file_exporter.dart        # 日志文件导出
    │   │   └── log_file_parser.dart          # .log 文件解析
    │   ├── domain/services/
    │   │   └── sse_parser.dart               # SSE 流式响应解析器
    │   └── presentation/
    │       └── pages/log_page.dart           # 日志查看页面
    └── settings/                 # 设置模块
        ├── data/datasources/
        │   └── settings_local_datasource.dart
        └── presentation/
            └── pages/settings_page.dart      # 设置与证书页面
```

## 架构

项目采用 **Clean Architecture** 分层架构，每个功能模块分为三层：

- **data** — 数据源实现、仓库实现（Drift 数据库操作）
- **domain** — 实体定义、仓库接口、业务服务
- **presentation** — 页面、状态管理（Riverpod Provider）

### 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.44.0 / Dart 3.11 |
| 状态管理 | Riverpod 3.x |
| 路由 | GoRouter 17.x |
| 数据库 | Drift（SQLite ORM） |
| 序列化 | Freezed + json_serializable |
| 桌面集成 | window_manager + tray_manager |

### 请求处理流程

```
客户端请求 → ProxyServerDataSource (HTTP Server)
  → RequestRouter.handle()
    → 解析请求体 JSON
    → RuleMatcher.match() 匹配规则
    → 校验 Provider 格式
    → RequestTransformer.transform() 改写请求体
    → RequestForwarder.forward() 转发到上游 API
    → SSE 流式回写客户端
    → 记录日志到 Drift 数据库
```

## 配置说明

### 代理规则

每条规则定义了一个模型映射关系：

- **自定义模型 ID** — 客户端请求时使用的模型名
- **目标模型** — 实际转发到的上游模型
- **Provider** — 上游 API 提供商（baseUrl、apiKey、格式）
- **Thinking 模式** — 是否启用推理模式
- **Reasoning Effort** — 推理强度（low / medium / high）
- **System Prompt** — 关联的 System Prompt 模板
- **流式输出** — 是否启用 SSE 流式响应

### 证书配置

如需代理 HTTPS 请求，可在设置页面生成自签名证书，并将证书添加到系统信任链。

## 许可证

MIT License
