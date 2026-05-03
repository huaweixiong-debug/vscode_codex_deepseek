# VSCode Codex DeepSeek

把 Codex CLI、VSCode OpenAI Codex 插件、NAS Docker 里的 Codex CLI 路由到 DeepSeek V4 Pro。

核心思路：

```text
Codex / VSCode Codex
  -> http://127.0.0.1:17777/v1
  -> deepseek-codex-proxy.js
  -> https://api.deepseek.com/v1
  -> deepseek-v4-pro
```

`deepseek-codex-proxy.js` 做两件事：

- 把 Codex Responses API 请求转换成 DeepSeek Chat Completions 请求。
- 正确处理 Codex tool calls，避免 `tool_calls must be followed by tool messages` 这类错误。

## 目录

```text
.
|-- deepseek-codex-proxy.js
|-- Start-CodexDeepSeek.ps1
|-- CodexDeepSeek.cmd
|-- CodexDeepSeekApp.cmd
|-- Test-CodexDeepSeek.ps1
|-- windows/
|   |-- CodexDeepSeekAppServer.cs
|   `-- Build-AppServerWrapper.ps1
`-- nas-docker/
    |-- start-deepseek-proxy.sh
    |-- codex-deepseek.sh
    |-- nas-update-codex-config.js
    |-- deploy-codex-deepseek-to-nas.sh
    |-- sync-deepseek-env-to-codex-compose.sh
    |-- persist-codex-deepseek-wrapper.sh
    |-- enable-codex-proxy-autostart.sh
    |-- verify-codex-deepseek-on-nas.sh
    |-- run-codex-deepseek-smoke-on-nas.sh
    `-- run-plain-codex-smoke-on-nas.sh
```

## 前置条件

- Windows: Node.js、Codex CLI、VSCode OpenAI Codex 插件。
- NAS Docker: 一个名为 `codex` 的容器，容器里有 Node.js 和 Codex CLI。
- DeepSeek API Key。

不要把真实 API key 提交到 GitHub。

## Windows: Codex CLI 走 DeepSeek

1. 配置 key：

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.codex" | Out-Null
Set-Content "$env:USERPROFILE\.codex\deepseek.env" "DEEPSEEK_API_KEY=sk-your-key-here"
```

2. 启动 DeepSeek 版 Codex CLI：

```powershell
.\CodexDeepSeek.cmd
```

等价手动命令：

```powershell
.\Start-CodexDeepSeek.ps1 -Workspace "D:\your\workspace"
```

3. 只启动 proxy：

```powershell
.\Start-CodexDeepSeek.ps1 -ProxyOnly
```

4. 验证日志：

```powershell
Get-Content "$env:USERPROFILE\.codex\log\deepseek-codex-proxy.log" -Tail 20
```

看到类似内容即表示真实请求走 DeepSeek：

```text
responses->chat model=deepseek-v4-pro requested_model=deepseek-v4-pro
```

## VSCode Codex 插件走 DeepSeek

VSCode 插件启动的是 `codex app-server`，不能直接复用普通 CLI 参数。这里用一个小的 `.exe` wrapper 接管插件的 `chatgpt.cliExecutable`。

### 一键部署

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-VSCodeCodexDeepSeek.ps1
```

脚本会自动完成：

- 复制 `deepseek-codex-proxy.js` 和启动脚本到 `%LOCALAPPDATA%\CodexDeepSeek`
- 编译 `CodexDeepSeekAppServer.exe`
- 写入 `%USERPROFILE%\.codex\deepseek.env`
- 修改 VSCode `settings.json`
- 启动本地 DeepSeek proxy

如果想非交互传入 key：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-VSCodeCodexDeepSeek.ps1 -DeepSeekApiKey "sk-your-key-here"
```

部署后执行 `Developer: Reload Window`，或重启 VSCode。

### 手动部署

1. 编译 wrapper：

```powershell
.\windows\Build-AppServerWrapper.ps1
```

生成：

```text
.\CodexDeepSeekAppServer.exe
```

2. 在 VSCode `settings.json` 里加入：

```json
{
  "chatgpt.runCodexInWindowsSubsystemForLinux": false,
  "chatgpt.cliExecutable": "D:\\path\\to\\vscode_codex_deepseek\\CodexDeepSeekAppServer.exe"
}
```

3. 执行 `Developer: Reload Window`，或重启 VSCode。

4. 打开 Codex 面板发一条测试消息，然后看日志：

```powershell
Get-Content "$env:USERPROFILE\.codex\log\deepseek-codex-proxy.log" -Tail 20
```

如果看到 `model=deepseek-v4-pro`，说明 VSCode 插件实际走 DeepSeek。

注意：模型自报“我是 GPT-5.5”不一定可信，真实路由以 proxy 日志为准。proxy 已加入身份提示和模型名强制映射，前端传 `gpt-5.5`、`gpt-5.4-mini` 时也会映射到 `deepseek-v4-pro`。

## NAS Docker: Codex CLI 走 DeepSeek

假设：

- NAS 上有 `/volume1/docker/codex/docker-compose.yml`
- compose 服务名和容器名都是 `codex`
- DeepSeek key 已在某个来源可用，例如 `.env` 或另一个容器环境变量

推荐步骤：

1. 把这些文件复制到 NAS 用户家目录：

```text
deepseek-codex-proxy.js
nas-docker/start-deepseek-proxy.sh
nas-docker/codex-deepseek.sh
nas-docker/nas-update-codex-config.js
nas-docker/deploy-codex-deepseek-to-nas.sh
nas-docker/sync-deepseek-env-to-codex-compose.sh
nas-docker/persist-codex-deepseek-wrapper.sh
nas-docker/enable-codex-proxy-autostart.sh
```

2. 复制 proxy 和脚本进容器，并更新 `/root/.codex/config.toml`：

```sh
chmod 700 ~/deploy-codex-deepseek-to-nas.sh
~/deploy-codex-deepseek-to-nas.sh
```

3. 让 `codex` compose 持久化 `DEEPSEEK_API_KEY`：

```sh
chmod 700 ~/sync-deepseek-env-to-codex-compose.sh
~/sync-deepseek-env-to-codex-compose.sh
```

如果你的 key 不在 `hermes` 容器里，请手动把下面这行写入 `/volume1/docker/codex/.env`：

```env
DEEPSEEK_API_KEY=sk-your-key-here
```

4. 持久化 `codex-deepseek` 入口：

```sh
chmod 700 ~/persist-codex-deepseek-wrapper.sh
~/persist-codex-deepseek-wrapper.sh
```

5. 设置容器启动时自动拉起 proxy：

```sh
chmod 700 ~/enable-codex-proxy-autostart.sh
~/enable-codex-proxy-autostart.sh
cd /volume1/docker/codex
docker compose up -d codex
```

6. 验证：

```sh
chmod 700 ~/run-plain-codex-smoke-on-nas.sh
~/run-plain-codex-smoke-on-nas.sh
```

成功时会看到：

```text
model: deepseek-v4-pro
provider: deepseek-codex
responses->chat model=deepseek-v4-pro requested_model=deepseek-v4-pro
```

## 使用方式

Windows CLI：

```powershell
.\CodexDeepSeek.cmd
```

VSCode：

```text
打开 VSCode Codex 面板，正常聊天即可。
```

NAS Docker：

```sh
docker exec -it codex sh
codex
```

或显式入口：

```sh
docker exec -it codex codex-deepseek
```

单次执行：

```sh
docker exec codex codex exec --skip-git-repo-check "你的问题"
```

## 恢复默认 OpenAI Codex

Windows：

- 删除 VSCode 设置里的 `chatgpt.cliExecutable`
- 停止本地 `deepseek-codex-proxy.js` node 进程
- 把 `%USERPROFILE%\.codex\config.toml` 改回原来的 OpenAI 配置

NAS Docker：

- 从 `/volume1/docker/codex/docker-compose.yml.before-*` 恢复 compose
- 从 `/root/.codex/config.toml.before-*` 恢复 Codex 配置
- `docker compose up -d codex`

## 常见问题

`codex debug models` 仍显示 `gpt-5.5`：

这通常是 Codex 内置模型目录，不代表实际请求。以 `deepseek-codex-proxy.log` 为准。

模型回答“我是 GPT-5.5”：

这是模型自报和前端身份上下文，不代表真实计费模型。用 proxy 日志确认。

`chatgpt.com/backend-api/wham/apps` 报错：

这是 Codex 尝试访问应用/插件元数据的非致命错误，不影响 DeepSeek 推理请求。

`DEEPSEEK_API_KEY is not set`：

把 key 放到 Windows 的 `%USERPROFILE%\.codex\deepseek.env`，或 NAS 的 `/volume1/docker/codex/.env`，然后重启 proxy/容器。
