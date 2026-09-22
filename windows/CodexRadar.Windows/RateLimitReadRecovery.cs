namespace CodexRadar.Windows;

internal static class RateLimitReadRecovery
{
    // A quota read is read-only. Retry once after a transient disconnect; this
    // policy must never wrap credit consumption or authentication failures.
    internal static async Task<T> ReadAsync<T>(Func<CancellationToken, Task<T>> read,
        CancellationToken token, Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        try { return await read(token).ConfigureAwait(false); }
        catch (Exception ex) when (!token.IsCancellationRequested && ShouldRetry(ex))
        {
            await (delay ?? Task.Delay)(TimeSpan.FromSeconds(1), token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            return await read(token).ConfigureAwait(false);
        }
    }

    internal static bool ShouldRetry(Exception error)
    {
        if (error is OperationCanceledException or FileNotFoundException) return false;
        var message = error.Message;
        if (new[] { "authentication", "not logged in", "signed out" }
            .Any(value => message.Contains(value, StringComparison.OrdinalIgnoreCase))) return false;
        if (error is TimeoutException or EndOfStreamException) return true;
        if (error is not (AppServerRpcException or IOException or InvalidOperationException)) return false;
        return new[] { "failed to fetch codex rate limits", "error sending request for url",
                "connection reset", "connection closed", "network connection was lost",
                "temporarily unavailable", "timed out", "process exited", "broken pipe", "pipe is being closed" }
            .Any(value => message.Contains(value, StringComparison.OrdinalIgnoreCase));
    }
}
