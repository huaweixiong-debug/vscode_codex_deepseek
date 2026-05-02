using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

class CodexDeepSeekAppServer
{
    const string BaseUrl = "http://127.0.0.1:17777/v1";

    static int Main(string[] args)
    {
        try
        {
            StartProxy();
            return RunCodex(args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("CodexDeepSeekAppServer wrapper error: " + ex.Message);
            return 1;
        }
    }

    static void StartProxy()
    {
        var proxyStarter = ResolveProxyStarter();
        if (!File.Exists(proxyStarter))
            throw new FileNotFoundException("Proxy starter not found", proxyStarter);

        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoProfile -ExecutionPolicy Bypass -File " + Quote(proxyStarter) + " -ProxyOnly",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        using (var process = Process.Start(startInfo))
        {
            if (process == null)
                throw new InvalidOperationException("Failed to start DeepSeek proxy starter");

            process.WaitForExit(15000);
            if (!process.HasExited)
            {
                try { process.Kill(); } catch { }
                throw new TimeoutException("DeepSeek proxy starter timed out");
            }

            if (process.ExitCode != 0)
            {
                var err = process.StandardError.ReadToEnd();
                var output = process.StandardOutput.ReadToEnd();
                throw new InvalidOperationException((err + "\n" + output).Trim());
            }
        }
    }

    static int RunCodex(string[] args)
    {
        var realCodex = ResolveCodexExecutable();
        if (!File.Exists(realCodex))
            throw new FileNotFoundException("Bundled VSCode Codex executable not found", realCodex);

        var forwarded = new List<string>(args);
        if (forwarded.Count > 0 && forwarded[0] == "app-server")
        {
            forwarded.InsertRange(1, new[]
            {
                "-c", "model_provider=\"deepseek-codex\"",
                "-c", "model=\"deepseek-v4-pro\"",
                "-c", "model_providers.deepseek-codex.name=\"DeepSeek Codex\"",
                "-c", "model_providers.deepseek-codex.base_url=\"" + BaseUrl + "\"",
                "-c", "model_providers.deepseek-codex.wire_api=\"responses\""
            });
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = realCodex,
            Arguments = JoinArgs(forwarded),
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.EnvironmentVariables["CODEX_OSS_BASE_URL"] = BaseUrl;

        using (var process = Process.Start(startInfo))
        {
            if (process == null)
                throw new InvalidOperationException("Failed to start bundled Codex");

            var stdinThread = new Thread(() => Copy(Console.OpenStandardInput(), process.StandardInput.BaseStream, true));
            var stdoutThread = new Thread(() => Copy(process.StandardOutput.BaseStream, Console.OpenStandardOutput(), true));
            var stderrThread = new Thread(() => Copy(process.StandardError.BaseStream, Console.OpenStandardError(), true));

            stdinThread.IsBackground = true;
            stdoutThread.IsBackground = true;
            stderrThread.IsBackground = true;

            stdinThread.Start();
            stdoutThread.Start();
            stderrThread.Start();

            process.WaitForExit();
            stdoutThread.Join(2000);
            stderrThread.Join(2000);
            return process.ExitCode;
        }
    }

    static string ResolveProxyStarter()
    {
        var overridePath = Environment.GetEnvironmentVariable("CODEX_DEEPSEEK_PROXY_STARTER");
        if (!string.IsNullOrWhiteSpace(overridePath))
            return overridePath;

        var exeDir = AppDomain.CurrentDomain.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(exeDir, "Start-CodexDeepSeek.ps1"),
            Path.Combine(exeDir, "..", "Start-CodexDeepSeek.ps1"),
            Path.Combine(Directory.GetCurrentDirectory(), "Start-CodexDeepSeek.ps1")
        };

        foreach (var candidate in candidates)
        {
            var full = Path.GetFullPath(candidate);
            if (File.Exists(full))
                return full;
        }

        return candidates[0];
    }

    static string ResolveCodexExecutable()
    {
        var overridePath = Environment.GetEnvironmentVariable("CODEX_VSCODE_CODEX_EXE");
        if (!string.IsNullOrWhiteSpace(overridePath))
            return overridePath;

        var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var extensionsDir = Path.Combine(userProfile, ".vscode", "extensions");
        if (Directory.Exists(extensionsDir))
        {
            var dirs = Directory.GetDirectories(extensionsDir, "openai.chatgpt-*");
            Array.Sort(dirs, StringComparer.OrdinalIgnoreCase);
            Array.Reverse(dirs);
            foreach (var dir in dirs)
            {
                var candidate = Path.Combine(dir, "bin", "windows-x86_64", "codex.exe");
                if (File.Exists(candidate))
                    return candidate;
            }
        }

        return Path.Combine(extensionsDir, "openai.chatgpt-CHANGE-ME", "bin", "windows-x86_64", "codex.exe");
    }

    static void Copy(Stream input, Stream output, bool closeOutput)
    {
        try
        {
            var buffer = new byte[81920];
            int read;
            while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
            {
                output.Write(buffer, 0, read);
                output.Flush();
            }
        }
        catch { }
        finally
        {
            if (closeOutput)
            {
                try { output.Close(); } catch { }
            }
        }
    }

    static string JoinArgs(IEnumerable<string> args)
    {
        var quoted = new List<string>();
        foreach (var arg in args)
            quoted.Add(Quote(arg));
        return string.Join(" ", quoted.ToArray());
    }

    static string Quote(string value)
    {
        if (value == null)
            return "\"\"";
        if (value.Length == 0)
            return "\"\"";

        bool needsQuotes = value.IndexOfAny(new[] { ' ', '\t', '\n', '\v', '"' }) >= 0;
        if (!needsQuotes)
            return value;

        var result = "\"";
        int backslashes = 0;
        foreach (char ch in value)
        {
            if (ch == '\\')
            {
                backslashes++;
            }
            else if (ch == '"')
            {
                result += new string('\\', backslashes * 2 + 1);
                result += ch;
                backslashes = 0;
            }
            else
            {
                result += new string('\\', backslashes);
                result += ch;
                backslashes = 0;
            }
        }
        result += new string('\\', backslashes * 2);
        result += "\"";
        return result;
    }
}
