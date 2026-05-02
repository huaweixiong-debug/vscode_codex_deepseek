# VSCode Codex DeepSeek

将 VSCode 中 OpenAI Codex 插件的模型从 GPT 切换到 DeepSeek，通过本地代理转发 API 请求。

## 架构

```
Codex CLI / VSCode 插件  →  http://127.0.0.1:17777/v1  →  Node.js 代理  →  https://api.deepseek.com/v1
```

代理负责将 Codex 的 "responses" API 格式转换为 DeepSeek 的 "chat/completions" 格式。

## 前置条件

- Node.js
- DeepSeek API Key

## 快速开始

### 1. 配置 API Key

在 `%USERPROFILE%\.codex\deepseek.env` 文件中设置：

```
DEEPSEEK_API_KEY=sk-your-key-here
```

或者设置环境变量 `DEEPSEEK_API_KEY`。

### 2. 修改 Codex 配置

编辑 `%USERPROFILE%\.codex\config.toml`，改为：

```toml
model_provider = "lmstudio"
model = "deepseek-v4-pro"
disable_response_storage = true

# 保持原有的其他配置 ...
```

### 3. 设置环境变量

设置用户级环境变量 `CODEX_OSS_BASE_URL`：

```powershell
[Environment]::SetEnvironmentVariable("CODEX_OSS_BASE_URL", "http://127.0.0.1:17777/v1", "User")
```

### 4. 启动代理

```powershell
# 仅启动代理（后台运行）
.\Start-CodexDeepSeek.ps1 -ProxyOnly

# 启动代理 + 打开 Codex CLI
.\CodexDeepSeek.cmd

# 启动代理 + 打开 Codex 桌面应用
.\CodexDeepSeekApp.cmd
```

### 5. 注册开机自启（可选）

```powershell
.\Register-ProxyTask.ps1
```

## 文件说明

| 文件 | 用途 |
|------|------|
| `deepseek-codex-proxy.js` | Node.js 代理，将 Codex API 请求转发到 DeepSeek |
| `Start-CodexDeepSeek.ps1` | 启动代理 + Codex 的主脚本 |
| `Test-CodexDeepSeek.ps1` | 快速测试脚本 |
| `CodexDeepSeek.cmd` | 一键启动 Codex CLI（含代理） |
| `CodexDeepSeekApp.cmd` | 一键启动 Codex 桌面应用（含代理） |
| `Start-Proxy.cmd` | 仅启动代理 |
| `Register-ProxyTask.ps1` | 注册 Windows 计划任务，开机自动启动代理 |

## 恢复默认

将 `config.toml` 改回原来的设置：

```toml
model_provider = "openai"
model = "gpt-5.5"
```

## 日志

代理日志位于 `%USERPROFILE%\.codex\log\deepseek-codex-proxy.log`。
