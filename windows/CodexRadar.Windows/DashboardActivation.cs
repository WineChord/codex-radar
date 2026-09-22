using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace CodexRadar.Windows;

// Requests only show the dashboard or query its visibility. They cannot change settings,
// execute commands, read account data, or trigger a reset-credit operation.
internal sealed class DashboardActivation : IDisposable
{
    private const byte ShowDashboard = 1;
    private const byte QueryVisibility = 2;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Task _listener;

    internal static string PipeName
    {
        get
        {
            using var identity = WindowsIdentity.GetCurrent();
            using var process = Process.GetCurrentProcess();
            return $"CodexRadarSentinel.Show.{identity.User!.Value}.{process.SessionId}";
        }
    }

    public DashboardActivation(Func<bool, Task<bool>> dashboardRequest, string? pipeName = null,
        TimeSpan? requestTimeout = null)
    {
        _listener = ListenAsync(pipeName ?? PipeName, dashboardRequest,
            requestTimeout ?? TimeSpan.FromSeconds(5), _lifetime.Token);
    }

    // null means unavailable/rejected, false means a healthy but hidden window.
    internal static async Task<bool?> RequestAsync(string? pipeName = null,
        TimeSpan? timeout = null, bool allowForeground = true, bool show = true)
    {
        using var deadline = new CancellationTokenSource(
            timeout ?? TimeSpan.FromSeconds(10));
        while (!deadline.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeClientStream(".", pipeName ?? PipeName,
                    PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                // Connect also waits for a first instance that is still starting.
                await pipe.ConnectAsync(deadline.Token).ConfigureAwait(false);
                if (show && allowForeground && GetNamedPipeServerProcessId(pipe.SafePipeHandle, out var processId))
                    AllowSetForegroundWindow(processId);
                await pipe.WriteAsync(new byte[] { show ? ShowDashboard : QueryVisibility }, deadline.Token).ConfigureAwait(false);
                var reply = new byte[1];
                if (await pipe.ReadAsync(reply, deadline.Token).ConfigureAwait(false) == 1)
                    return reply[0] switch { 1 => true, 2 => false, _ => null };
            }
            catch (IOException)
            {
                // A new launcher can race the preceding pipe's disconnect.
                // Show (never toggle) and visibility queries are safe to retry.
            }
            catch (Exception ex) when (ex is OperationCanceledException or UnauthorizedAccessException)
            {
                return null;
            }
            try { await Task.Delay(50, deadline.Token).ConfigureAwait(false); }
            catch (OperationCanceledException) { break; }
        }
        return null;
    }

    private static async Task ListenAsync(string pipeName, Func<bool, Task<bool>> dashboardRequest,
        TimeSpan requestTimeout, CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                using var pipe = new NamedPipeServerStream(pipeName, PipeDirection.InOut,
                    1, PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await pipe.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                deadline.CancelAfter(requestTimeout);
                var request = new byte[1];
                if (await pipe.ReadAsync(request, deadline.Token).ConfigureAwait(false) != 1)
                    continue;
                byte reply = 0;
                if (request[0] is ShowDashboard or QueryVisibility)
                {
                    var visible = await dashboardRequest(request[0] == ShowDashboard)
                        .WaitAsync(deadline.Token).ConfigureAwait(false);
                    reply = visible ? (byte)1 : (byte)2;
                }
                await pipe.WriteAsync(new byte[] { reply },
                    deadline.Token).ConfigureAwait(false);
                // Closing a Windows pipe immediately after WriteAsync can
                // discard the buffered reply before the launcher reads it.
                // The one-request client closes after reading; wait for that
                // close (or the deadline) before disposing the server handle.
                await pipe.ReadAsync(new byte[1], deadline.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                // An idle client must not block subsequent Search launches.
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // Disconnected clients and transient pipe failures are recoverable.
                await Task.Delay(100, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
        }
    }

    public void Dispose()
    {
        _lifetime.Cancel();
        try { _listener.GetAwaiter().GetResult(); }
        catch (OperationCanceledException) { }
        _lifetime.Dispose();
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetNamedPipeServerProcessId(SafePipeHandle pipe, out uint processId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AllowSetForegroundWindow(uint processId);
}

internal static class DashboardActivationSelfTest
{
    public static async Task RunAsync()
    {
        static void Assert(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }

        var name = "CodexRadarSentinel.ActivationTest." + Guid.NewGuid().ToString("N");
        var shown = 0;
        using (var server = new DashboardActivation(show =>
               {
                   if (show) Interlocked.Increment(ref shown);
                   return Task.FromResult(shown > 0);
               }, name, TimeSpan.FromMilliseconds(150)))
        {
            Assert(await DashboardActivation.RequestAsync(name, show: false) == false,
                "A read-only visibility probe must not open a hidden dashboard.");
            for (var index = 0; index < 3; index++)
                Assert(await DashboardActivation.RequestAsync(name, allowForeground: false) == true,
                    "Repeated launches must activate the existing instance.");
            Assert(shown == 3, "Each launch must show the dashboard exactly once.");

            using (var invalid = new NamedPipeClientStream(".", name, PipeDirection.InOut,
                       PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly))
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                await invalid.ConnectAsync(timeout.Token);
                await invalid.WriteAsync(new byte[] { 255 }, timeout.Token);
                var reply = new byte[1];
                Assert(await invalid.ReadAsync(reply, timeout.Token) == 1 && reply[0] == 0,
                    "Unsupported activation commands must be rejected.");
            }
            Assert(shown == 3, "Invalid commands must not invoke the dashboard.");

            using (var idle = new NamedPipeClientStream(".", name, PipeDirection.InOut,
                       PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly))
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                await idle.ConnectAsync(timeout.Token);
                Assert(await DashboardActivation.RequestAsync(name, allowForeground: false) == true,
                    "A stalled client must not prevent subsequent activation.");
            }
            Assert(shown == 4, "Stalled connections must never activate the dashboard.");
            Assert(await DashboardActivation.RequestAsync(name, show: false) == true && shown == 4,
                "A visibility probe must preserve the existing window state.");
        }
        Assert(await DashboardActivation.RequestAsync(name, TimeSpan.FromMilliseconds(100), false) is null,
            "An absent or stopped instance must time out without an unbounded wait.");

        var interrupted = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var attempts = 0;
        using (var retryServer = new DashboardActivation(_ =>
                   Interlocked.Increment(ref attempts) == 1 ? interrupted.Task : Task.FromResult(true),
                   name, TimeSpan.FromMilliseconds(100)))
        {
            try
            {
                Assert(await DashboardActivation.RequestAsync(name, allowForeground: false) == true
                       && attempts == 2,
                    "A dropped reply must retry the idempotent request within the original deadline.");
            }
            finally { interrupted.TrySetResult(false); }
        }
    }
}
