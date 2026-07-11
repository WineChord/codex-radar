namespace CodexRadar.Windows;

internal sealed record DashboardSnapshot
{
    public DateTimeOffset RefreshedAt { get; init; } = DateTimeOffset.Now;
    public int? WeeklyRemaining { get; init; }
    public int? ShortRemaining { get; init; }
    public double? WeeklyUsedPercent { get; init; }
    public double? ShortUsedPercent { get; init; }
    public double? WeeklyWindowMinutes { get; init; }
    public double? ShortWindowMinutes { get; init; }
    public DateTimeOffset? WeeklyResetsAt { get; init; }
    public DateTimeOffset? ShortResetsAt { get; init; }
    public string? PlanType { get; init; }
    public string? CreditsBalance { get; init; }
    public bool LimitReached { get; init; }
    public double? IqScore { get; init; }
    public string? IqDate { get; init; }
    public string? IqStatus { get; init; }
    public string? ModelLabel { get; init; }
    public int? Passed { get; init; }
    public int? ValidTasks { get; init; }
    public string? WallTime { get; init; }
    public double? CostUsd { get; init; }
    public string? CacheHitRate { get; init; }
    public double? CommunityRating { get; init; }
    public int? CommunityRatingCount { get; init; }
    public string? SchemaVersion { get; init; }
    public DateTimeOffset? CheckedAt { get; init; }
    public string? RadarStatus { get; init; }
    public string? RecommendedAction { get; init; }
    public bool WindowOpen { get; init; }
    public string? WindowId { get; init; }
    public string? WindowStatus { get; init; }
    public string? WindowTitle { get; init; }
    public string? WindowSummary { get; init; }
    public string? WindowHuman { get; init; }
    public DateTimeOffset? WindowOpenedAt { get; init; }
    public DateTimeOffset? WindowClosedAt { get; init; }
    public string? WindowScope { get; init; }
    public string? WindowSourceUrl { get; init; }
    public PredictionInfo? Prediction { get; init; }
    public string? Announcement { get; init; }
    public string? AnnouncementLabel { get; init; }
    public string? AnnouncementUpdatedLabel { get; init; }
    public string? AnnouncementSourceLabel { get; init; }
    public string? AnnouncementUrl { get; init; }
    public string? ResetRadar { get; init; }
    public string? ResetRadarTitle { get; init; }
    public string? ResetRadarUpdatedLabel { get; init; }
    public IReadOnlyList<ResetJudgementCard> ResetRadarCards { get; init; } = [];
    public IReadOnlyList<string> ResetRadarReasons { get; init; } = [];
    public string? CommunityKnowledge { get; init; }
    public string? CommunityPrompt { get; init; }
    public IReadOnlyList<QuotaEstimate> QuotaRadar { get; init; } = [];
    public string? QuotaRadarDate { get; init; }
    public DateTimeOffset? QuotaRadarUpdatedAt { get; init; }
    public string? QuotaRadarBasisWindowLabel { get; init; }
    public double? QuotaRadarCostUsd { get; init; }
    public long? QuotaRadarTotalTokens { get; init; }
    public double? QuotaRadarSevenDayTrendDelta { get; init; }
    public IReadOnlyList<ModelComparison> Comparisons { get; init; } = [];
    public IReadOnlyList<ResetCredit> ResetCredits { get; init; } = [];
    public int? AvailableResetCredits { get; init; }
    public int? TotalEarnedResetCredits { get; init; }
    public DateTimeOffset? ResetCreditsCheckedAt { get; init; }
    public ResetCreditFailureInfo? ResetCreditFailure { get; init; }
    public QuotaPacingSnapshot? QuotaPacing { get; init; }
    public IReadOnlyList<string> Errors { get; init; } = [];

    public string CompactTitle(AppSettings settings) => StatusTitleFormatter.Format(this, settings);

    public bool ActiveEntitlementEvent
    {
        get
        {
            return WindowOpen && !ActiveSpeedWindow;
        }
    }

    public bool ActiveSpeedWindow
    {
        get
        {
            if (!WindowOpen) return false;
            var joined = string.Join(" ", new[] { WindowId, WindowTitle, WindowSummary, WindowHuman, RecommendedAction }
                .Where(value => !string.IsNullOrWhiteSpace(value))).ToLowerInvariant();
            return joined.Contains("速蹬") || joined.Contains("speed-window") || joined.Contains("speed window")
                   || joined.Contains("use_remaining_tokens") || joined.Contains("use remaining tokens");
        }
    }

    public string? SpeedAlertKey => !ActiveSpeedWindow ? null
        : $"{WindowId ?? "unknown"}:{WindowOpenedAt?.ToUniversalTime().ToString("O") ?? "unknown"}";
    public string? ResetCloseKey
    {
        get
        {
            if (WindowStatus?.Equals("closed", StringComparison.OrdinalIgnoreCase) == true && WindowClosedAt is { } closed)
                return $"{WindowId ?? "unknown"}:{closed.ToUniversalTime():O}";
            var action = RecommendedAction?.ToLowerInvariant();
            var status = WindowStatus?.ToLowerInvariant();
            var text = string.Join(" ", new[] { action, status, WindowTitle, WindowSummary, WindowHuman }
                .Where(value => !string.IsNullOrWhiteSpace(value))).ToLowerInvariant();
            var completed = action == "reset_completed" || status?.Contains("confirmed") == true
                            || text.Contains("已完成重置") || text.Contains("已重置") || text.Contains("reset completed");
            if (!completed) return null;
            var eventAt = WindowClosedAt ?? WindowOpenedAt ?? CheckedAt;
            return $"{WindowId ?? "reset"}:{eventAt?.ToUniversalTime().ToString("O") ?? "unknown"}:{action ?? status ?? "completed"}";
        }
    }

    public HealthLevel Health => ActiveSpeedWindow || LimitReached || WeeklyRemaining <= 15 || IqScore < 80
        || string.Equals(IqStatus, "red", StringComparison.OrdinalIgnoreCase)
        ? HealthLevel.Critical
        : WeeklyRemaining <= 30 || IqScore < 95 || string.Equals(IqStatus, "yellow", StringComparison.OrdinalIgnoreCase)
            ? HealthLevel.Warning
            : WeeklyRemaining is null && IqScore is null ? HealthLevel.Unknown : HealthLevel.Good;
}

internal enum HealthLevel { Unknown, Good, Warning, Critical }
internal sealed record QuotaEstimate(string Tier, double? FiveHourUsd, double? SevenDayUsd, string? Basis = null);
internal sealed record ModelComparison(
    string Label, double? Iq, string? Status, int? Passed = null, int? Tasks = null,
    double? Rating = null, int? RatingCount = null, string? WallTime = null,
    double? CostUsd = null, string? CacheHitRate = null);
internal sealed record ResetCredit(
    string Title, string Status, DateTimeOffset? GrantedAt, DateTimeOffset? ExpiresAt, string? IdSuffix,
    string? ResetType = null, DateTimeOffset? RedeemStartedAt = null, DateTimeOffset? RedeemedAt = null)
{
    public bool IsAvailable => string.Equals(Status, "available", StringComparison.OrdinalIgnoreCase);
    public bool IsExpired(DateTimeOffset? now = null) => ExpiresAt is { } expiry && expiry <= (now ?? DateTimeOffset.Now);
}
internal sealed record PredictionInfo(
    string? Level, double? Probability24Hours, double? Probability48Hours, bool? ShouldNotify,
    string? ExpectedWindow, string? Summary, DateTimeOffset? UpdatedAt);
internal sealed record ResetJudgementCard(string? Label, string? Level, string? Summary);

internal static class DashboardPreviewFactory
{
    public static DashboardSnapshot Apply(DashboardSnapshot live, DashboardPreview preview)
    {
        var reset = DateTimeOffset.Now.AddDays(5);
        return preview switch
        {
            DashboardPreview.QualityNormal => live with
            {
                WeeklyRemaining = 97, WeeklyUsedPercent = 3, ShortRemaining = 99, ShortUsedPercent = 1,
                WeeklyResetsAt = reset, WeeklyWindowMinutes = 10_080, IqScore = 100, IqStatus = "green",
                WindowOpen = false, RadarStatus = "retired", RecommendedAction = "wait"
            },
            DashboardPreview.QualityLow => live with
            {
                WeeklyRemaining = 97, WeeklyUsedPercent = 3, ShortRemaining = 86, ShortUsedPercent = 14,
                WeeklyResetsAt = reset, WeeklyWindowMinutes = 10_080, IqScore = 62.5, IqStatus = "red",
                WindowOpen = false
            },
            DashboardPreview.SpeedWindow => live with
            {
                WeeklyRemaining = 97, WeeklyUsedPercent = 3, ShortRemaining = 86, ShortUsedPercent = 14,
                WeeklyResetsAt = reset, WeeklyWindowMinutes = 10_080, IqScore = 62.5, IqStatus = "red",
                WindowOpen = true, WindowId = "windows-preview-speed", WindowStatus = "open",
                WindowTitle = "Preview: Codex speed window", WindowSummary = "Preview mode: an active speed window should be visually urgent.",
                WindowOpenedAt = DateTimeOffset.Now, RecommendedAction = "speed_window_open",
                Prediction = new PredictionInfo("high", 88, 92, true, null, "Preview mode: active speed window.", DateTimeOffset.Now)
            },
            DashboardPreview.ResetConfirmed => live with
            {
                WeeklyRemaining = 97, WeeklyUsedPercent = 3, WeeklyResetsAt = reset, WeeklyWindowMinutes = 10_080,
                WindowOpen = false, WindowId = "windows-preview-reset", WindowStatus = "closed",
                WindowTitle = "Preview: CodexRadar recorded reset", WindowSummary = "Preview mode: a reset event recorded by CodexRadar.",
                WindowClosedAt = DateTimeOffset.Now, RecommendedAction = "wait"
            },
            DashboardPreview.Blocked => live with
            {
                WeeklyRemaining = 0, WeeklyUsedPercent = 100, ShortRemaining = 0, ShortUsedPercent = 100,
                WeeklyResetsAt = reset, WeeklyWindowMinutes = 10_080, LimitReached = true
            },
            _ => live
        };
    }
}
