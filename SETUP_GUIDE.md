# VSCode Codex 插件切换 DeepSeek V4 Pro 傻瓜教程

**换一台电脑，照着下面 1、2、3、4 走，每一步都复制粘贴，不要改。**

---

## 前置条件

- Windows 10 或 11
- 已安装 Node.js（[nodejs.org](https://nodejs.org) 下载 LTS 版，安装时勾选"Add to PATH"）
- VSCode 已安装 OpenAI Codex 插件（扩展商店搜 `openai.chatgpt`）
- 有一个 DeepSeek API Key（格式 `sk-xxx`，从 [platform.deepseek.com](https://platform.deepseek.com) 获取）

---

## 第一步：克隆仓库

打开 PowerShell（右键 → 以管理员身份运行），逐条执行：

```powershell
cd D:\
mkdir D:\Codex\tools -Force
cd D:\Codex\tools
git clone https://github.com/你的仓库地址/vscode_codex_deepseek.git
cd vscode_codex_deepseek
```

如果仓库已存在，跳过 git clone，直接 `cd D:\Codex\tools\vscode_codex_deepseek`。

---

## 第二步：处理 .codex 目录的沙箱 ACL 锁

Codex 桌面端会给 `C:\Users\你的用户名\.codex` 目录加上拒绝写入的 DENY 规则。必须先清掉，否则后面密钥文件写不进去。

```powershell
# 夺取所有权
takeown /F "$env:USERPROFILE\.codex" /R /D Y

# 递归清除所有 DENY 规则
icacls "$env:USERPROFILE\.codex" /reset /T /C /Q

# 确认没有 DENY 字样了
icacls "$env:USERPROFILE\.codex"
```

最后一条命令的输出里不应该出现 `DENY`。如果还有，再跑一次 `icacls ... /reset /T /C /Q`。

---

## 第三步：写入密钥文件（双重保险）

把下面命令里的 `sk-你的key` 换成你真实的 DeepSeek API Key，然后整段复制粘贴执行：

```powershell
$key = "sk-你的真实key"

# 位置 1：用户目录（主位置）
New-Item -ItemType Directory -Force "$env:USERPROFILE\.codex" | Out-Null
Set-Content "$env:USERPROFILE\.codex\deepseek.env" "DEEPSEEK_API_KEY=$key"

# 位置 2：仓库目录（备用，权限问题时的逃生通道）
Set-Content "D:\Codex\tools\vscode_codex_deepseek\deepseek.env" "DEEPSEEK_API_KEY=$key"

# 位置 3：仓库目录 local 版（第二备用，最不可能被锁）
Set-Content "D:\Codex\tools\vscode_codex_deepseek\deepseek.local.env" "DEEPSEEK_API_KEY=$key"

# 位置 4：系统环境变量（终极备用，全局生效）
[System.Environment]::SetEnvironmentVariable("DEEPSEEK_API_KEY", $key, "User")

Write-Host "密钥已写入 4 个位置，任一个可用即可"
```

**验证密钥写入成功：**

```powershell
Get-Content "$env:USERPROFILE\.codex\deepseek.env"
Get-Content "D:\Codex\tools\vscode_codex_deepseek\deepseek.env"
```

两条命令都应该输出 `DEEPSEEK_API_KEY=sk-xxx`。

---

## 第四步：运行一键部署

```powershell
cd D:\Codex\tools\vscode_codex_deepseek
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-VSCodeCodexDeepSeek.ps1
```

正常情况下你会看到：

```
[Codex DeepSeek] Installing files to C:\Users\...\CodexDeepSeek
[Codex DeepSeek] Writing DeepSeek key to ...
[Codex DeepSeek] Building VSCode app-server wrapper
Built ...
[Codex DeepSeek] Updating VSCode settings.json
[Codex DeepSeek] Starting DeepSeek proxy
DeepSeek Codex proxy is running at http://127.0.0.1:17777/v1
[Codex DeepSeek] Done
```

---

## 第五步：重载 VSCode

1. 打开 VSCode
2. 按 `Ctrl + Shift + P`
3. 输入 `Developer: Reload Window`，回车
4. 打开 Codex 面板（左侧边栏的 Codex 图标），发一条消息，比如 `hello`

---

## 第六步：验证是否真的走 DeepSeek

回到 PowerShell 执行：

```powershell
Get-Content "$env:USERPROFILE\.codex\log\deepseek-codex-proxy.log" -Tail 10
```

看到这一行就说明成功：

```
responses->chat model=deepseek-v4-pro requested_model=deepseek-v4-pro
```

---

## 常见问题

### Q: 脚本提示"对路径的访问被拒绝"

回到第二步，重跑 `icacls ... /reset /T /C /Q`。如果还报错，手动删除目录后重试：

```powershell
takeown /F "$env:USERPROFILE\.codex" /R /D Y
icacls "$env:USERPROFILE\.codex" /reset /T /C /Q
Remove-Item "$env:USERPROFILE\.codex" -Recurse -Force
```

然后从第三步重新开始。

### Q: VSCode Codex 插件一直显示"初始化"转圈

```powershell
# 检查 proxy 是否在监听
netstat -ano | findstr ":17777"

# 如果没有输出，手动启动 proxy
$env:DEEPSEEK_API_KEY = "sk-你的key"
$env:PORT = "17777"
$env:CODEX_DEEPSEEK_LOG_DIR = "$env:USERPROFILE\.codex\log"
node "D:\Codex\tools\vscode_codex_deepseek\deepseek-codex-proxy.js"
```

看到 `DeepSeek Codex proxy listening on 127.0.0.1:17777` 后，再重载 VSCode。

### Q: 模型回答"我是 GPT-5.5"

不用管。这是模型自身的身份幻觉，不代表实际用了 OpenAI。以 proxy 日志为准——只要日志显示 `model=deepseek-v4-pro`，计费就走 DeepSeek。

### Q: 怎么恢复到原来的 OpenAI Codex

```powershell
# 1. 删掉 VSCode 设置里的 cliExecutable
$settings = Get-Content "$env:APPDATA\Code\User\settings.json" -Raw | ConvertFrom-Json
$settings.PSObject.Properties.Remove('chatgpt.cliExecutable')
$settings | ConvertTo-Json -Depth 100 | Set-Content "$env:APPDATA\Code\User\settings.json" -Encoding UTF8

# 2. 停掉 proxy
taskkill /F /IM node.exe

# 3. 重载 VSCode
```
