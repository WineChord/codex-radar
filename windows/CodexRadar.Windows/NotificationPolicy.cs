namespace CodexRadar.Windows;

internal enum NotificationSeverity { Passive, Active, Urgent }
internal sealed record NotificationEvent(string Identifier, string Title, string Body, NotificationSeverity Severity);

internal static class NotificationPolicy
{
    private const int WarningRemaining = 30;
    private const int CriticalRemaining = 15;
    private const int RestoredRemaining = 80;

    public static IReadOnlyList<NotificationEvent> Evaluate(
        DashboardSnapshot? previous, DashboardSnapshot current, AppSettings settings, DateTimeOffset? now = null)
    {
        var memory = settings.NotificationMemory;
        var wasInitialized = memory.Initialized;
        if (!memory.Initialized) Seed(current, memory);
        var events = new List<NotificationEvent>();
        AppendSpeed(current, wasInitialized, memory, settings.Chinese, events);
        if (!wasInitialized) return events;
        AppendReset(current, memory, settings.Chinese, events);
        AppendQuota(previous, current, memory, settings.Chinese, now ?? DateTimeOffset.Now, events);
        // Always advance the seen-event memory. Delivery preferences are applied by the tray
        // so re-enabling a category never replays an old prediction or IQ event.
        AppendPrediction(previous, current, memory, settings.Chinese, events);
        AppendIq(current, memory, settings.Chinese, events);
        return events;
    }

    private static void Seed(DashboardSnapshot current, NotificationMemory memory)
    {
        memory.Initialized = true;
        if (current.ResetCloseKey is { } reset) memory.LastResetCloseKey = reset;
        if (IqKey(current) is { } iq) memory.LastIqKey = iq;
        if (PredictionKey(current) is { } prediction) memory.LastPredictionKey = prediction;
    }

    private static void AppendSpeed(DashboardSnapshot state, bool initialized, NotificationMemory memory,
        bool zh, List<NotificationEvent> events)
    {
        if (state.SpeedAlertKey is not { } key || memory.LastSpeedOpenKey == key) return;
        memory.LastSpeedOpenKey = key;
        var weekly = state.WeeklyRemaining is int quota ? $"{quota}%" : "--";
        events.Add(new NotificationEvent($"speed-window-open-{key}", Zh(zh, "速蹬窗口开启", "Speed window open"),
            initialized ? Zh(zh, $"当前周额度剩余 {weekly}，建议尽快使用。", $"Weekly quota left: {weekly}. Use quota now.")
                : Zh(zh, $"启动时检测到窗口已开启，当前周额度剩余 {weekly}。", $"Window already open at launch; weekly quota left: {weekly}."),
            NotificationSeverity.Urgent));
    }

    private static void AppendReset(DashboardSnapshot state, NotificationMemory memory, bool zh, List<NotificationEvent> events)
    {
        if (state.ResetCloseKey is not { } key || memory.LastResetCloseKey == key) return;
        memory.LastResetCloseKey = key;
        events.Add(new NotificationEvent($"reset-close-{key}", Zh(zh, "CodexRadar 记录到 reset", "CodexRadar recorded a reset"),
            state.WindowTitle ?? "Codex limit reset", NotificationSeverity.Urgent));
    }

    private static void AppendQuota(DashboardSnapshot? previous, DashboardSnapshot state, NotificationMemory memory,
        bool zh, DateTimeOffset now, List<NotificationEvent> events)
    {
        if (state.WeeklyRemaining is not int remaining) return;
        var resetKey = state.WeeklyResetsAt?.ToUnixTimeSeconds().ToString() ?? "unknown";
        if (remaining <= CriticalRemaining)
        {
            var key = $"{resetKey}:critical";
            if (ShouldSend(key, memory.LastWeeklyCriticalKey, memory.LastWeeklyCriticalAt, TimeSpan.FromHours(4), now))
            {
                memory.LastWeeklyCriticalKey = key;
                memory.LastWeeklyCriticalAt = now;
                events.Add(new NotificationEvent($"weekly-critical-{key}", Zh(zh, "Codex 周额度很低", "Codex weekly quota is very low"),
                    Zh(zh, $"当前周额度剩余 {remaining}%。", $"Weekly quota left: {remaining}%."), NotificationSeverity.Urgent));
            }
        }
        else if (remaining <= WarningRemaining)
        {
            var key = $"{resetKey}:warning";
            if (ShouldSend(key, memory.LastWeeklyWarningKey, memory.LastWeeklyWarningAt, TimeSpan.FromHours(12), now))
            {
                memory.LastWeeklyWarningKey = key;
                memory.LastWeeklyWarningAt = now;
                events.Add(new NotificationEvent($"weekly-warning-{key}", Zh(zh, "Codex 周额度偏低", "Codex weekly quota is low"),
                    Zh(zh, $"当前周额度剩余 {remaining}%。", $"Weekly quota left: {remaining}%."), NotificationSeverity.Active));
            }
        }

        var restoreKey = state.WeeklyResetsAt is null ? null : $"{resetKey}:restored";
        if (memory.PendingWeeklyRestoreKey is { } pending)
        {
            if (pending == restoreKey && remaining >= RestoredRemaining)
            {
                memory.PendingWeeklyRestoreKey = null;
                if (memory.LastWeeklyRestoreKey != pending)
                {
                    memory.LastWeeklyRestoreKey = pending;
                    events.Add(new NotificationEvent($"weekly-restored-{pending}", Zh(zh, "Codex 周额度已恢复", "Codex weekly quota restored"),
                        Zh(zh, $"当前周额度剩余 {remaining}%。", $"Weekly quota left: {remaining}%."), NotificationSeverity.Active));
                }
                return;
            }
            if (pending != restoreKey || remaining < RestoredRemaining) memory.PendingWeeklyRestoreKey = null;
        }
        if (previous?.WeeklyRemaining <= WarningRemaining && remaining >= RestoredRemaining
            && previous.WeeklyResetsAt != state.WeeklyResetsAt && restoreKey is not null)
            memory.PendingWeeklyRestoreKey = restoreKey;
    }

    private static void AppendPrediction(DashboardSnapshot? previous, DashboardSnapshot state, NotificationMemory memory,
        bool zh, List<NotificationEvent> events)
    {
        if (state.RadarStatus?.Equals("retired", StringComparison.OrdinalIgnoreCase) == true || state.Prediction is not { } prediction) return;
        var level = prediction.Level?.ToLowerInvariant();
        var previousLevel = previous?.Prediction?.Level?.ToLowerInvariant();
        var shouldNotify = prediction.ShouldNotify == true || (level == "high" && previousLevel != "high");
        var key = PredictionKey(state);
        if (!shouldNotify || key is null || memory.LastPredictionKey == key) return;
        memory.LastPredictionKey = key;
        var probability = prediction.Probability24Hours is double value
            ? $"{Math.Round(NormalizeProbability(value), MidpointRounding.AwayFromZero):0}%"
            : "unknown";
        events.Add(new NotificationEvent($"prediction-{key}", Zh(zh, "Codex reset 预测升高", "Codex reset prediction increased"),
            Zh(zh, $"未来 24h 概率 {probability}，等级 {prediction.Level ?? "unknown"}。",
                $"24h probability {probability}; level {prediction.Level ?? "unknown"}."), NotificationSeverity.Active));
    }

    private static void AppendIq(DashboardSnapshot state, NotificationMemory memory, bool zh, List<NotificationEvent> events)
    {
        if (state.IqScore is not double score || (score >= 80 && !string.Equals(state.IqStatus, "red", StringComparison.OrdinalIgnoreCase))) return;
        var key = IqKey(state);
        if (key is null || memory.LastIqKey == key) return;
        memory.LastIqKey = key;
        events.Add(new NotificationEvent($"model-iq-{key}", Zh(zh, "Codex IQ 偏低", "Codex IQ is low"),
            $"IQ {score:0.0}, {state.Passed?.ToString() ?? "?"}/{state.ValidTasks?.ToString() ?? "?"} tasks.", NotificationSeverity.Passive));
    }

    private static bool ShouldSend(string key, string? previousKey, DateTimeOffset? sentAt, TimeSpan cooldown, DateTimeOffset now) =>
        previousKey != key && (sentAt is null || now - sentAt >= cooldown);
    private static string? PredictionKey(DashboardSnapshot state) => state.Prediction is not { } prediction ? null
        : $"{prediction.UpdatedAt?.ToUniversalTime().ToString("O") ?? "unknown"}:{prediction.Level ?? "unknown"}:{prediction.Probability24Hours ?? -1}";
    private static string? IqKey(DashboardSnapshot state) => state.IqScore is not double score ? null
        : $"{state.IqDate ?? "unknown"}:{score:0.0}:{state.IqStatus ?? "unknown"}";
    private static double NormalizeProbability(double value) => value <= 1 ? value * 100 : value;
    private static string Zh(bool chinese, string zh, string en) => chinese ? zh : en;
}
