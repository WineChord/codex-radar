using System.Text.Json.Serialization;

namespace CodexRadar.Windows;

internal enum DashboardTextSize { Medium, Large, ExtraLarge }
internal enum StatusMetric { WeeklyQuota, ShortQuota, QuotaPace, CodexIq, Signal }
internal enum StatusBarIqDisplayMode { Raw, DividedBy10Integer, DividedBy10Decimal }
internal enum StatusBarSeparator { Slash, NarrowSlash, ThinSpace, Dot, None }
internal enum StatusBarHorizontalPadding { System, Compact, Tight }
internal enum StatusBarFontScale { Normal, Compact, Tiny }
internal enum QuotaPacingStrategy { TimeProportional, SevenDay, ReserveTwenty, WorkdayWeighted, FrontLoaded }
internal enum QuotaPacingStatus { UnderTarget, OnPace, OverTarget }
internal enum DashboardPreview { Live, QualityNormal, QualityLow, SpeedWindow, ResetConfirmed, Blocked }

internal sealed record NotificationMemory
{
    public bool Initialized { get; set; }
    public string? LastSpeedOpenKey { get; set; }
    public string? LastResetCloseKey { get; set; }
    public string? LastPredictionKey { get; set; }
    public string? LastIqKey { get; set; }
    public string? LastWeeklyWarningKey { get; set; }
    public string? LastWeeklyCriticalKey { get; set; }
    public string? LastWeeklyRestoreKey { get; set; }
    public DateTimeOffset? LastWeeklyWarningAt { get; set; }
    public DateTimeOffset? LastWeeklyCriticalAt { get; set; }
    public string? PendingWeeklyRestoreKey { get; set; }
}

internal sealed record ResetCreditFailureInfo(string Kind, string Detail, DateTimeOffset OccurredAt, bool Automatic);

internal static class StatusTitleFormatter
{
    private static readonly StatusMetric[] OrderedMetrics =
        [StatusMetric.WeeklyQuota, StatusMetric.ShortQuota, StatusMetric.QuotaPace, StatusMetric.CodexIq, StatusMetric.Signal];

    public static string Format(DashboardSnapshot state, AppSettings options)
    {
        var selected = options.SelectedStatusMetrics.Count == 0
            ? new HashSet<StatusMetric> { StatusMetric.WeeklyQuota }
            : options.SelectedStatusMetrics.ToHashSet();
        var values = OrderedMetrics.Where(selected.Contains).Select(metric => Value(metric, state, options));
        return string.Join(Separator(options.Separator), values);
    }

    public static string Value(StatusMetric metric, DashboardSnapshot state, AppSettings options) => metric switch
    {
        StatusMetric.WeeklyQuota => Percent(state.WeeklyRemaining, options.ShowPercentSymbol),
        StatusMetric.ShortQuota => Percent(state.ShortRemaining, options.ShowPercentSymbol),
        StatusMetric.QuotaPace => state.QuotaPacing is { } pace
            ? (options.Chinese ? "应" : "R") + Percent(pace.RoundedTargetRemaining, options.ShowPercentSymbol) : "-",
        StatusMetric.CodexIq => FormatIq(state.IqScore, options),
        StatusMetric.Signal => Signal(state, options.Chinese),
        _ => "-"
    };

    public static string Signal(DashboardSnapshot state, bool chinese)
    {
        if (state.ActiveSpeedWindow) return chinese ? "速蹬" : "speed";
        if (state.LimitReached) return chinese ? "限额" : "limit";
        if (state.IqScore is double score)
        {
            if (state.IqStatus?.Equals("red", StringComparison.OrdinalIgnoreCase) == true || score < 80)
                return chinese ? "低" : "low";
            if (state.IqStatus?.Equals("yellow", StringComparison.OrdinalIgnoreCase) == true || score < 95)
                return chinese ? "中" : "med";
            return chinese ? "正常" : "ok";
        }
        if (state.ActiveEntitlementEvent) return chinese ? "权益" : "event";
        return state.Prediction?.Level?.ToLowerInvariant() switch
        {
            "high" => chinese ? "高" : "high",
            "medium_high" or "medium-high" => chinese ? "中高" : "med-high",
            "medium" => chinese ? "中" : "med",
            "medium_low" or "medium-low" => chinese ? "中低" : "med-low",
            "low" => chinese ? "低" : "low",
            _ => "-"
        };
    }

    private static string FormatIq(double? value, AppSettings options)
    {
        if (value is not double score || !double.IsFinite(score)) return "--";
        return options.IqDisplayMode switch
        {
            StatusBarIqDisplayMode.DividedBy10Integer => ((int)(score / 10)).ToString(),
            StatusBarIqDisplayMode.DividedBy10Decimal => OneDecimal(score / 10),
            _ => options.PreciseIq ? OneDecimal(score) : ((int)score).ToString()
        };
    }

    private static string OneDecimal(double value) =>
        Math.Round(value, 1, MidpointRounding.AwayFromZero).ToString("0.0");

    private static string Percent(int? value, bool symbol) => value is int number ? $"{number}{(symbol ? "%" : "")}" : "--";
    private static string Separator(StatusBarSeparator separator) => separator switch
    {
        StatusBarSeparator.NarrowSlash => "⁄",
        StatusBarSeparator.ThinSpace => " ",
        StatusBarSeparator.Dot => "·",
        StatusBarSeparator.None => "",
        _ => "/"
    };
}
