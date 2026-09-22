using System.Diagnostics;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace CodexRadar.Windows;

internal sealed class AppServerClient : IAsyncDisposable
{
    private enum ProcessTransport
    {
        StandaloneStdio,
        ManagedWebSocket
    }

    internal static readonly System.Text.Encoding JsonLineEncoding = new System.Text.UTF8Encoding(false);
    private Process? _process;
    private StreamWriter? _input;
    private StreamReader? _output;
    private ManagedAppServerConnection? _managedConnection;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly bool _allowsAutomaticRestart;
    private readonly Func<string?> _managedControlSocketProvider;
    private int _nextId = 1;
    private bool _initialized;
    private bool _disposed;
    private bool _hasStartedProcess;
    private bool _hasCompletedRead;
    private bool _hasCompletedReadOnCurrentProcess;
    private ProcessTransport? _transport;
    private IReadOnlyList<string>? _cachedExecutables;
    private string? _preferredExecutable;
    private string? _runningExecutable;

    public AppServerClient(bool allowsAutomaticRestart = true)
        : this(allowsAutomaticRestart, CodexManagedAppServerLocator.FindControlSocket)
    {
    }

    internal AppServerClient(
        bool allowsAutomaticRestart,
        Func<string?> managedControlSocketProvider)
    {
        _allowsAutomaticRestart = allowsAutomaticRestart;
        _managedControlSocketProvider = managedControlSocketProvider;
    }

    public async Task<LocalQuotaResult> ReadRateLimitsAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var failures = new List<string>();
            var attempted = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            // Reuse a proven process first. If its quota RPC starts failing
            // (for example after a Codex update), fall through to the other
            // installed candidates instead of pinning the broken executable.
            if (_process is { HasExited: false } && _initialized && _runningExecutable is { } running)
            {
                try
                {
                    var quota = await ReadStartedRateLimitsAsync(cancellationToken).ConfigureAwait(false);
                    _preferredExecutable = running;
                    return quota;
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch (Exception ex) when (ShouldTryNextCandidate(ex))
                {
                    attempted.Add(running);
                    failures.Add($"{Path.GetFileName(running)}: {ex.Message}");
                    Stop();
                }
            }

            // Dispose an exited or only partially initialized process before a
            // replacement overwrites its redirected streams.
            Stop();

            var executables = _cachedExecutables ??= FindCodexBinaries();
            if (executables.Count == 0)
            {
                _cachedExecutables = null;
                throw new FileNotFoundException(
                    "未找到 Codex CLI。请安装 Codex，或通过 CODEX_RADAR_CODEX_PATH 指定 codex.exe。\n" +
                    "Codex CLI was not found. Set CODEX_RADAR_CODEX_PATH to codex.exe.");
            }

            foreach (var executable in executables
                         .OrderByDescending(path => string.Equals(path, _preferredExecutable,
                             StringComparison.OrdinalIgnoreCase)))
            {
                if (!attempted.Add(executable)) continue;
                try
                {
                    await StartAsync(executable, cancellationToken).ConfigureAwait(false);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) when (ShouldTryNextStartCandidate(ex))
                {
                    failures.Add($"{Path.GetFileName(executable)}: {ex.Message}");
                    Stop();
                    continue;
                }

                _runningExecutable = executable;
                try
                {
                    var quota = await ReadStartedRateLimitsAsync(cancellationToken).ConfigureAwait(false);
                    // A candidate is preferred only after the quota method and
                    // response shape both succeed, not merely after initialize.
                    _preferredExecutable = executable;
                    return quota;
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) when (ShouldTryNextCandidate(ex))
                {
                    failures.Add($"{Path.GetFileName(executable)}: {ex.Message}");
                    Stop();
                }
            }

            _cachedExecutables = null;
            _preferredExecutable = null;
            throw new InvalidOperationException("找到 Codex，但所有候选都无法读取额度 / Codex quota candidates failed: "
                                                + string.Join("; ", failures.Take(4)));
        }
        catch (InvalidOperationException ex) when (IsAuthenticationRequired(ex) && IsIsolatedUserContext())
        {
            Stop();
            throw new InvalidOperationException(
                "当前程序运行在隔离的 Windows 用户上下文，无法读取真实用户的 Codex 登录态。" +
                "请从开始菜单或资源管理器启动 Codex Radar；若由 Codex 启动，请允许它在主机环境运行。\n" +
                "Codex Radar is running in an isolated Windows user context. Launch it from Start or Explorer, " +
                "or allow Codex to start it in the host context.", ex);
        }
        catch
        {
            Stop();
            throw;
        }
        finally { _gate.Release(); }
    }

    private async Task<LocalQuotaResult> ReadStartedRateLimitsAsync(CancellationToken cancellationToken)
    {
        using var result = await ReadRequestWithManagedFallbackAsync(
                "account/rateLimits/read", null, cancellationToken)
            .ConfigureAwait(false);
        return ParseRateLimits(result.RootElement);
    }

    public async Task<CodexAccountIdentity> ReadAccountAsync(
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            using var result = await ReadRequestWithManagedFallbackAsync(
                "account/read", new { refreshToken = false }, cancellationToken)
                .ConfigureAwait(false);
            return CodexAccountIdentity.Parse(result.RootElement);
        }
        catch
        {
            Stop();
            throw;
        }
        finally { _gate.Release(); }
    }

    public async Task<ProtectionRateLimitResponse> ReadProtectionRateLimitsAsync(
        CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            using var result = await ReadRequestWithManagedFallbackAsync(
                "account/rateLimits/read", null, cancellationToken)
                .ConfigureAwait(false);
            return ProtectionRateLimitResponse.Parse(result.RootElement);
        }
        catch
        {
            Stop();
            throw;
        }
        finally { _gate.Release(); }
    }

    public async Task<ResetCreditConsumeOutcome> ConsumeResetCreditAsync(
        string creditId,
        string idempotencyKey,
        Action<Action> authorizedDispatch,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(creditId))
            throw new ArgumentException("Reset credit ID must not be empty.", nameof(creditId));
        if (!Guid.TryParse(idempotencyKey, out _))
            throw new ArgumentException("Reset credit idempotency key must be a UUID.", nameof(idempotencyKey));

        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_process is not { HasExited: false } || !_initialized)
                throw new ResetCreditPreDispatchException(
                    "The verified Codex app-server session ended before dispatch.");
            using var result = await RequestAsync(
                    "account/rateLimitResetCredit/consume",
                    new { idempotencyKey, creditId },
                    cancellationToken,
                    authorizedDispatch)
                .ConfigureAwait(false);
            var outcome = result.RootElement.String("outcome");
            return Enum.TryParse<ResetCreditConsumeOutcome>(outcome, true, out var parsed)
                ? parsed
                : throw new InvalidDataException("Codex returned an unknown reset-credit outcome.");
        }
        finally { _gate.Release(); }
    }

    internal static LocalQuotaResult ParseRateLimits(JsonElement root)
    {
        JsonElement selected;
        if (root.TryGetProperty("rateLimitsByLimitId", out var byId)
            && byId.ValueKind == JsonValueKind.Object
            && byId.TryGetProperty("codex", out var codex)
            && codex.ValueKind == JsonValueKind.Object)
        {
            selected = codex;
        }
        else if (root.TryGetProperty("rateLimits", out var rateLimits)
                 && rateLimits.ValueKind == JsonValueKind.Object)
        {
            selected = rateLimits;
        }
        else
        {
            throw new InvalidDataException("Codex app-server returned no usable rateLimits object.");
        }

        var windows = new List<(string Name, double? Duration, double Used, long? ResetsAt)>();
        foreach (var name in new[] { "primary", "secondary" })
        {
            if (!selected.TryGetProperty(name, out var window) || window.ValueKind != JsonValueKind.Object) continue;
            var duration = window.Number("windowDurationMins", "window_duration_mins");
            var used = window.Number("usedPercent", "used_percent");
            var reset = window.Int64("resetsAt", "resets_at");
            // The duration is optional in the app-server protocol. macOS keeps
            // such a bucket and falls back to primary/secondary ordering; doing
            // the same here prevents an otherwise valid quota from becoming --.
            if (used is double u) windows.Add((name, duration, u, reset));
        }

        var weekly = ChooseWindow(windows, 10_080, "secondary");
        var shortWindow = ChooseWindow(windows, 300, "primary");
        var reportsUsagePermission = root.TryGetProperty("ordinaryUsageAllowed", out _)
                                     || root.TryGetProperty("ordinary_usage_allowed", out _);
        var usageAllowed = root.Bool("ordinaryUsageAllowed", "ordinary_usage_allowed");
        var blocked = usageAllowed == false
                      || selected.Bool("spendControlReached", "spend_control_reached") == true
                      || selected.String("rateLimitReachedType", "rate_limit_reached_type") is not null
                      || windows.Any(x => x.Used >= 100);
        string? creditsBalance = null;
        if (selected.Object("credits") is JsonElement credits)
        {
            var unlimited = credits.Bool("unlimited") == true;
            creditsBalance = unlimited ? "unlimited" : credits.String("balance");
        }

        return new LocalQuotaResult(
            weekly is null ? null : RadarJson.RemainingPercent(weekly.Value.Used),
            shortWindow is null ? null : RadarJson.RemainingPercent(shortWindow.Value.Used),
            weekly?.Used, shortWindow?.Used, weekly?.Duration, shortWindow?.Duration,
            ToDate(weekly?.ResetsAt), ToDate(shortWindow?.ResetsAt), blocked,
            selected.String("planType", "plan_type"), creditsBalance,
            !blocked && (!reportsUsagePermission || usageAllowed == true));
    }

    private static (string Name, double? Duration, double Used, long? ResetsAt)? ChooseWindow(
        IReadOnlyList<(string Name, double? Duration, double Used, long? ResetsAt)> windows,
        double target,
        string preferredName)
    {
        if (windows.Count == 0) return null;
        var close = windows.FirstOrDefault(window => window.Duration is double duration
            && Math.Abs(duration - target) <= target * .05);
        if (close.Name is not null) return close;

        if (windows.Any(window => window.Duration is not null))
            return target >= 1000
                ? windows.OrderByDescending(window => window.Duration ?? 0).First()
                : windows.OrderBy(window => window.Duration ?? 0).First();

        // Current Codex responses conventionally use primary for the short
        // window and secondary for the weekly window. This is also the most
        // useful fallback when both optional duration fields are absent.
        var preferred = windows.FirstOrDefault(window => window.Name == preferredName);
        return preferred.Name is not null ? preferred : windows.FirstOrDefault();
    }

    internal static (double Duration, double Used)? ChooseWindow(IEnumerable<(double Duration, double Used)> windows, double target)
    {
        var values = windows.ToArray();
        var close = values.FirstOrDefault(x => Math.Abs(x.Duration - target) <= target * .05);
        if (close.Duration > 0) return close;
        return target >= 1000
            ? values.OrderByDescending(x => x.Duration).Cast<(double, double)?>().FirstOrDefault()
            : values.OrderBy(x => x.Duration).Cast<(double, double)?>().FirstOrDefault();
    }

    private async Task StartAsync(string executable, CancellationToken cancellationToken)
    {
        var socket = _managedControlSocketProvider();
        if (!string.IsNullOrWhiteSpace(socket))
        {
            try
            {
                await StartTransportAsync(
                        executable,
                        ProcessTransport.ManagedWebSocket,
                        socket,
                        cancellationToken)
                    .ConfigureAwait(false);
                return;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception ex) when (ShouldFallbackFromManagedTransport(ex))
            {
                Stop();
            }
        }

        await StartTransportAsync(
                executable,
                ProcessTransport.StandaloneStdio,
                null,
                cancellationToken)
            .ConfigureAwait(false);
    }

    private async Task StartTransportAsync(
        string executable,
        ProcessTransport transport,
        string? socket,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Stop();
        var start = CreateStartInfo(executable, transport, socket);
        _process = Process.Start(start)
                   ?? throw new InvalidOperationException("Codex app-server 启动失败");
        _hasStartedProcess = true;
        _transport = transport;
        _runningExecutable = executable;
        var errorReader = _process.StandardError;
        _ = Task.Run(async () =>
        {
            try { while (await errorReader.ReadLineAsync() is not null) { } } catch { }
        }, CancellationToken.None);
        if (cancellationToken.IsCancellationRequested)
        {
            Stop();
            cancellationToken.ThrowIfCancellationRequested();
        }

        var startedProcess = _process;
        if (transport == ProcessTransport.ManagedWebSocket)
        {
            using var handshakeTimeout =
                CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            handshakeTimeout.CancelAfter(TimeSpan.FromSeconds(15));
            try
            {
                _managedConnection = await ManagedAppServerConnection.ConnectAsync(
                        startedProcess.StandardInput.BaseStream,
                        startedProcess.StandardOutput.BaseStream,
                        handshakeTimeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException ex)
                when (!cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException(
                    "The managed Codex app-server handshake timed out after 15 seconds.",
                    ex);
            }
        }
        else
        {
            _input = startedProcess.StandardInput;
            _input.AutoFlush = true;
            _output = startedProcess.StandardOutput;
        }

        var parameters = new
        {
            clientInfo = new
            {
                name = "codex-radar-sentinel-windows",
                title = "Codex Radar Sentinel",
                version = AppUpdateService.CurrentVersion
            },
            capabilities = new
            {
                experimentalApi = false,
                requestAttestation = false,
                optOutNotificationMethods = Array.Empty<string>()
            }
        };
        using var initializeResult = await RequestAsync(
                "initialize", parameters, cancellationToken)
            .ConfigureAwait(false);
        if (transport == ProcessTransport.ManagedWebSocket)
        {
            var initialized = JsonSerializer.SerializeToUtf8Bytes(
                new { method = "initialized" });
            using var notificationTimeout =
                CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            notificationTimeout.CancelAfter(TimeSpan.FromSeconds(15));
            try
            {
                await (_managedConnection
                       ?? throw new InvalidOperationException(
                           "The managed Codex app-server connection is unavailable."))
                    .SendNotificationAsync(initialized, notificationTimeout.Token)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException ex)
                when (!cancellationToken.IsCancellationRequested)
            {
                throw new TimeoutException(
                    "The managed Codex app-server initialization notification timed out after 15 seconds.",
                    ex);
            }
        }
        _initialized = true;
    }

    private static ProcessStartInfo CreateStartInfo(
        string executable,
        ProcessTransport transport,
        string? socket)
    {
        if (transport == ProcessTransport.ManagedWebSocket
            && string.IsNullOrWhiteSpace(socket))
            throw new ArgumentException(
                "A control socket is required for a managed Codex session.",
                nameof(socket));
        var arguments = transport == ProcessTransport.ManagedWebSocket
            ? new[] { "app-server", "proxy", "--sock", socket! }
            : new[] { "app-server", "--listen", "stdio://" };
        var isCommandScript = executable.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase)
                              || executable.EndsWith(".bat", StringComparison.OrdinalIgnoreCase);
        var start = new ProcessStartInfo
        {
            FileName = isCommandScript
                ? Environment.GetEnvironmentVariable("COMSPEC") ?? "cmd.exe"
                : executable,
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8,
            // JSON Lines must start with '{'. Encoding.UTF8 emits a BOM on the
            // first redirected write on Windows, which makes app-server reject
            // initialize before it can return a JSON-RPC response.
            StandardInputEncoding = JsonLineEncoding
        };
        if (isCommandScript)
        {
            if (arguments.Any(argument => argument.Contains('"'))
                || executable.Contains('"'))
                throw new InvalidDataException(
                    "The Codex executable or socket path contains an unsafe quote.");
            start.Arguments = $"/d /s /c \"\"{executable}\" "
                              + string.Join(" ", arguments.Select(argument =>
                                  argument.Contains(' ') ? $"\"{argument}\"" : argument))
                              + "\"";
        }
        else
        {
            foreach (var argument in arguments) start.ArgumentList.Add(argument);
        }
        return start;
    }

    private async Task EnsureStartedAsync(CancellationToken cancellationToken)
    {
        if (_process is { HasExited: false } && _initialized) return;
        if (!_allowsAutomaticRestart && _hasStartedProcess)
            throw new ResetCreditPreDispatchException(
                "The verified Codex app-server session ended before dispatch.");
        Stop();
        var executables = _cachedExecutables ??= FindCodexBinaries();
        if (executables.Count == 0)
        {
            _cachedExecutables = null;
            throw new FileNotFoundException(
                "未找到 Codex CLI。请安装 Codex，或通过 CODEX_RADAR_CODEX_PATH 指定 codex.exe。\n" +
                "Codex CLI was not found. Set CODEX_RADAR_CODEX_PATH to codex.exe.");
        }

        var failures = new List<string>();
        foreach (var executable in executables.OrderByDescending(path =>
                     string.Equals(path, _preferredExecutable, StringComparison.OrdinalIgnoreCase)))
        {
            try
            {
                await StartAsync(executable, cancellationToken).ConfigureAwait(false);
                _runningExecutable = executable;
                _preferredExecutable = executable;
                return;
            }
            catch (OperationCanceledException) { throw; }
            catch (Exception ex) when (ShouldTryNextStartCandidate(ex))
            {
                failures.Add($"{Path.GetFileName(executable)}: {ex.Message}");
                Stop();
            }
        }
        _cachedExecutables = null;
        _preferredExecutable = null;
        throw new InvalidOperationException(
            "Codex app-server candidates failed: " + string.Join("; ", failures.Take(4)));
    }

    private async Task<JsonDocument> ReadRequestWithManagedFallbackAsync(
        string method,
        object? parameters,
        CancellationToken cancellationToken)
    {
        await EnsureStartedAsync(cancellationToken).ConfigureAwait(false);
        var usedManagedTransport = _transport == ProcessTransport.ManagedWebSocket;
        try
        {
            var result = await RequestAsync(method, parameters, cancellationToken)
                .ConfigureAwait(false);
            _hasCompletedRead = true;
            _hasCompletedReadOnCurrentProcess =
                _process is { HasExited: false } && _initialized;
            return result;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception ex)
            when (usedManagedTransport
                  && ShouldFallbackFromManagedTransport(ex)
                  && CanFallbackFromManagedTransport(
                      _allowsAutomaticRestart,
                      _hasCompletedRead,
                      _hasCompletedReadOnCurrentProcess))
        {
            var executable = _runningExecutable
                             ?? throw new InvalidOperationException(
                                 "The Codex executable is unavailable for fallback.",
                                 ex);
            Stop();
            await StartTransportAsync(
                    executable,
                    ProcessTransport.StandaloneStdio,
                    null,
                    cancellationToken)
                .ConfigureAwait(false);
            var result = await RequestAsync(method, parameters, cancellationToken)
                .ConfigureAwait(false);
            _hasCompletedRead = true;
            _hasCompletedReadOnCurrentProcess =
                _process is { HasExited: false } && _initialized;
            return result;
        }
    }

    private async Task<JsonDocument> RequestAsync(
        string method,
        object? parameters,
        CancellationToken cancellationToken,
        Action<Action>? authorizedDispatch = null)
    {
        var process = _process;
        var input = _input;
        var output = _output;
        var managed = _managedConnection;
        if (process is not { HasExited: false }
            || (_transport == ProcessTransport.ManagedWebSocket
                ? managed is null
                : input is null || output is null))
            throw new InvalidOperationException("Codex app-server 不可用");
        var id = _nextId++;
        var request = parameters is null ? new { id, method } : (object)new { id, method, @params = parameters };
        var serialized = JsonSerializer.Serialize(request);
        cancellationToken.ThrowIfCancellationRequested();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        JsonDocument document;
        try
        {
            if (_transport == ProcessTransport.ManagedWebSocket)
            {
                document = await managed!.RequestAsync(
                        id,
                        JsonLineEncoding.GetBytes(serialized),
                        timeout.Token,
                        authorizedDispatch)
                    .ConfigureAwait(false);
            }
            else
            {
                if (authorizedDispatch is null)
                {
                    await input!.WriteLineAsync(serialized);
                }
                else
                {
                    authorizedDispatch(() =>
                    {
                        cancellationToken.ThrowIfCancellationRequested();
                        input!.WriteLine(serialized);
                    });
                }

                while (true)
                {
                    var line = await output!.ReadLineAsync(timeout.Token);
                    if (line is null) throw new EndOfStreamException("Codex app-server 已退出");
                    document = JsonDocument.Parse(line);
                    if (document.RootElement.Int32("id") == id) break;
                    document.Dispose();
                }
            }
        }
        catch (ResetCreditAuthorizationException)
        {
            throw;
        }
        catch (OperationCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException(
                $"Codex app-server RPC '{method}' timed out after 15 seconds.", ex);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex) when (authorizedDispatch is not null)
        {
            throw new ResetCreditPreDispatchException(
                "Reset-credit dispatch authorization could not be verified.", ex);
        }

        var root = document.RootElement;
        if (root.TryGetProperty("error", out var error))
        {
            var message = error.String("message") ?? "Codex app-server RPC error";
            var code = error.Int32("code");
            document.Dispose();
            throw new AppServerRpcException(code, message);
        }
        if (!root.TryGetProperty("result", out var resultElement))
        {
            document.Dispose();
            throw new InvalidDataException("Codex app-server 响应缺少 result");
        }
        var copy = JsonDocument.Parse(resultElement.GetRawText());
        document.Dispose();
        return copy;
    }

    private static DateTimeOffset? ToDate(long? epochSeconds) => epochSeconds is long seconds
        ? DateTimeOffset.FromUnixTimeSeconds(seconds).ToLocalTime() : null;

    private static bool IsAuthenticationRequired(Exception exception) =>
        exception.Message.Contains("authentication required", StringComparison.OrdinalIgnoreCase)
        || exception.Message.Contains("not logged in", StringComparison.OrdinalIgnoreCase);

    internal static bool ShouldFallbackFromManagedTransport(Exception exception) =>
        exception is ManagedAppServerTransportException
            or EndOfStreamException
            or IOException
            or TimeoutException
        || exception is AppServerRpcException rpc
           && (rpc.Message.Contains("authentication", StringComparison.OrdinalIgnoreCase)
               || rpc.Message.Contains("not logged in", StringComparison.OrdinalIgnoreCase));

    internal static bool CanFallbackFromManagedTransport(
        bool allowsAutomaticRestart,
        bool hasCompletedRead,
        bool hasCompletedReadOnCurrentProcess) =>
        allowsAutomaticRestart
            ? !hasCompletedReadOnCurrentProcess
            : !hasCompletedRead;

    internal static bool ShouldTryNextCandidate(Exception exception) => exception switch
    {
        AppServerRpcException rpc => rpc.Code is -32601 or -32602
                                     || rpc.Message.Contains("method not found", StringComparison.OrdinalIgnoreCase)
                                     || rpc.Message.Contains("unsupported", StringComparison.OrdinalIgnoreCase),
        InvalidDataException or JsonException or EndOfStreamException or IOException => true,
        _ => false
    };

    internal static bool ShouldTryNextStartCandidate(Exception exception) => exception switch
    {
        AppServerRpcException rpc => ShouldTryNextCandidate(rpc),
        TimeoutException => false,
        Win32Exception or FileNotFoundException or UnauthorizedAccessException
            or IOException or InvalidDataException or JsonException => true,
        InvalidOperationException => true,
        _ => false
    };

    internal static bool IsIsolatedUserContext()
    {
        var processProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var environmentProfile = Environment.GetEnvironmentVariable("USERPROFILE");
        if (string.IsNullOrWhiteSpace(processProfile) || string.IsNullOrWhiteSpace(environmentProfile)) return false;
        try
        {
            return !Path.GetFullPath(processProfile).TrimEnd(Path.DirectorySeparatorChar)
                .Equals(Path.GetFullPath(environmentProfile).TrimEnd(Path.DirectorySeparatorChar),
                    StringComparison.OrdinalIgnoreCase);
        }
        catch { return false; }
    }

    internal static string? FindCodexBinary() => FindCodexBinaries().FirstOrDefault();

    internal static IReadOnlyList<string> FindCodexBinaries()
    {
        var explicitCandidate = Environment.GetEnvironmentVariable("CODEX_RADAR_CODEX_PATH");
        var candidates = new List<string?> { explicitCandidate };
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var roaming = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        candidates.AddRange(new[]
        {
            Path.Combine(home, ".codex", "packages", "standalone", "current", "bin", "codex.exe"),
            Path.Combine(home, ".codex", "packages", "standalone", "current", "codex.exe"),
            Path.Combine(home, ".local", "bin", "codex.exe"),
            Path.Combine(roaming, "npm", "codex.cmd"),
            Path.Combine(local, "Microsoft", "WindowsApps", "codex.exe"),
            Path.Combine(local, "Programs", "Codex", "codex.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Codex", "codex.exe")
        });
        foreach (var folder in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator))
        {
            if (string.IsNullOrWhiteSpace(folder)) continue;
            var normalizedFolder = folder.Trim('"');
            // File.Exists on a disconnected UNC/mapped PATH entry can block a
            // refresh (and shutdown) for many seconds. Explicitly configured
            // CODEX_RADAR_CODEX_PATH remains supported above.
            if (IsNetworkPath(normalizedFolder)) continue;
            candidates.Add(Path.Combine(normalizedFolder, "codex.exe"));
            candidates.Add(Path.Combine(normalizedFolder, "codex.cmd"));
        }
        if (!IsNetworkPath(home)) candidates.AddRange(VisualStudioCodeExtensionCandidates(home));
        candidates.Add(Path.Combine(home, ".codex", ".sandbox-bin", "codex.exe"));
        return candidates.Where(path => !string.IsNullOrWhiteSpace(path)
                                        && (string.Equals(path, explicitCandidate, StringComparison.OrdinalIgnoreCase)
                                            || !IsNetworkPath(path!))
                                        && File.Exists(path))
            .Select(path => Path.GetFullPath(path!)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
    }

    internal static bool IsNetworkPath(string path)
    {
        try
        {
            var fullPath = Path.GetFullPath(path);
            if (fullPath.StartsWith(@"\\", StringComparison.Ordinal)) return true;
            var root = Path.GetPathRoot(fullPath);
            return !string.IsNullOrWhiteSpace(root) && new DriveInfo(root).DriveType == DriveType.Network;
        }
        catch { return true; }
    }

    private static IEnumerable<string> VisualStudioCodeExtensionCandidates(string home)
    {
        var architectures = RuntimeInformation.OSArchitecture == Architecture.Arm64
            ? new[] { "windows-aarch64", "windows-x86_64" }
            : new[] { "windows-x86_64" };
        foreach (var rootName in new[] { ".vscode", ".vscode-insiders" })
        {
            var root = Path.Combine(home, rootName, "extensions");
            if (!Directory.Exists(root)) continue;
            IEnumerable<string> extensions;
            try
            {
                extensions = Directory.EnumerateDirectories(root, "openai.chatgpt-*")
                    .OrderByDescending(Directory.GetLastWriteTimeUtc).ToArray();
            }
            catch { continue; }
            foreach (var extension in extensions)
                foreach (var architecture in architectures)
                    yield return Path.Combine(extension, "bin", architecture, "codex.exe");
        }
    }

    private void Stop()
    {
        _initialized = false;
        _hasCompletedReadOnCurrentProcess = false;
        _transport = null;
        _runningExecutable = null;
        var managed = Interlocked.Exchange(ref _managedConnection, null);
        var input = Interlocked.Exchange(ref _input, null);
        var output = Interlocked.Exchange(ref _output, null);
        var process = Interlocked.Exchange(ref _process, null);
        try { managed?.Dispose(); } catch { }
        try { input?.Dispose(); } catch { }
        try { output?.Dispose(); } catch { }
        if (process is not null)
        {
            try
            {
                var exited = false;
                try { exited = process.HasExited; } catch { }
                if (!exited)
                {
                    try { process.Kill(true); }
                    catch { try { process.Kill(); } catch { } }
                }
            }
            catch { }
            finally { try { process.Dispose(); } catch { } }
        }
    }

    internal void Abort()
    {
        _disposed = true;
        Stop();
    }

    public async ValueTask DisposeAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_disposed) return;
            _disposed = true;
            Stop();
        }
        finally { _gate.Release(); }
    }
}

internal sealed class AppServerRpcException(int? code, string message) : InvalidOperationException(message)
{
    public int? Code { get; } = code;
}

internal sealed record LocalQuotaResult(
    int? Weekly, int? Short, double? WeeklyUsed, double? ShortUsed,
    double? WeeklyDurationMinutes, double? ShortDurationMinutes,
    DateTimeOffset? WeeklyReset, DateTimeOffset? ShortReset, bool Blocked,
    string? PlanType, string? CreditsBalance, bool CanConfirmWeeklyRecovery = true);
