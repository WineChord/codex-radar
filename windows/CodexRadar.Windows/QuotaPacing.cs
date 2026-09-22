namespace CodexRadar.Windows;

internal sealed record QuotaPacingSnapshot(
    QuotaPacingStrategy Strategy,
    double CurrentUsedPercent,
    double TargetUsedPercent,
    double DeltaToTargetPercent,
    double ElapsedWindowPercent,
    DateTimeOffset WindowStart,
    DateTimeOffset ResetAt)
{
    public int RoundedCurrentUsed => Round(CurrentUsedPercent);
    public int RoundedTargetUsed => Round(TargetUsedPercent);
    public int RoundedCurrentRemaining => Round(100 - CurrentUsedPercent);
    public int RoundedTargetRemaining => Round(100 - TargetUsedPercent);
    public int RoundedRemainingDelta => (int)Math.Round(
        (100 - CurrentUsedPercent) - (100 - TargetUsedPercent), MidpointRounding.AwayFromZero);
    public int RoundedElapsed => Round(ElapsedWindowPercent);
    public QuotaPacingStatus Status => DeltaToTargetPercent >= 8 ? QuotaPacingStatus.UnderTarget
        : DeltaToTargetPercent <= -8 ? QuotaPacingStatus.OverTarget : QuotaPacingStatus.OnPace;
    private static int Round(double value) =>
        (int)Math.Round(Math.Clamp(value, 0, 100), MidpointRounding.AwayFromZero);
}

internal static class QuotaPacingCalculator
{
    private static readonly HashSet<string> ChinaHolidays2026 =
    [
        "2026-01-01", "2026-01-02", "2026-01-03",
        "2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19", "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23",
        "2026-04-04", "2026-04-05", "2026-04-06",
        "2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05",
        "2026-06-19", "2026-06-20", "2026-06-21",
        "2026-09-25", "2026-09-26", "2026-09-27",
        "2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05", "2026-10-06", "2026-10-07"
    ];
    private static readonly HashSet<string> ChinaMakeupWorkdays2026 =
        ["2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10"];

    public static QuotaPacingSnapshot? Calculate(DashboardSnapshot state, AppSettings settings, DateTimeOffset? now = null)
    {
        if (state.WeeklyUsedPercent is not double used || state.WeeklyResetsAt is not { } reset
            || state.WeeklyWindowMinutes is not double minutes || minutes <= 0) return null;
        var duration = TimeSpan.FromMinutes(minutes);
        var start = reset - duration;
        var current = now ?? DateTimeOffset.Now;
        if (current < start) current = start;
        if (current > reset) current = reset;
        var elapsed = current - start;
        var ratio = Math.Clamp(elapsed.TotalSeconds / duration.TotalSeconds, 0, 1);
        var target = settings.PacingStrategy switch
        {
            QuotaPacingStrategy.SevenDay => DailyTarget(elapsed, duration),
            QuotaPacingStrategy.ReserveTwenty => ReserveTarget(elapsed, duration),
            QuotaPacingStrategy.WorkdayWeighted => WeightedTarget(start, current, reset, settings.UseChinaHolidays),
            QuotaPacingStrategy.FrontLoaded => FrontLoadedTarget(ratio),
            _ => ratio * 100
        };
        used = Math.Clamp(used, 0, 100);
        target = Math.Clamp(target, 0, 100);
        return new QuotaPacingSnapshot(settings.PacingStrategy, used, target, target - used,
            ratio * 100, start, reset);
    }

    private static double DailyTarget(TimeSpan elapsed, TimeSpan duration)
    {
        if (elapsed <= TimeSpan.Zero) return 0;
        var totalDays = Math.Max(1, (int)Math.Ceiling(duration.TotalDays));
        var elapsedDays = Math.Min(totalDays, (int)Math.Ceiling(elapsed.TotalDays));
        return (double)elapsedDays / totalDays * 100;
    }

    private static double ReserveTarget(TimeSpan elapsed, TimeSpan duration)
    {
        var finalRelease = TimeSpan.FromSeconds(Math.Min(86_400, duration.TotalSeconds * .2));
        var mainSeconds = Math.Max(duration.TotalSeconds - finalRelease.TotalSeconds, 1);
        if (elapsed.TotalSeconds <= mainSeconds) return elapsed.TotalSeconds / mainSeconds * 80;
        var finalElapsed = Math.Clamp(elapsed.TotalSeconds - mainSeconds, 0, finalRelease.TotalSeconds);
        return 80 + (finalRelease.TotalSeconds > 0 ? finalElapsed / finalRelease.TotalSeconds : 1) * 20;
    }

    private static double FrontLoadedTarget(double elapsedRatio) => elapsedRatio <= .5
        ? elapsedRatio / .5 * 70
        : 70 + ((elapsedRatio - .5) / .5) * 30;

    private static double WeightedTarget(DateTimeOffset start, DateTimeOffset now, DateTimeOffset reset, bool chinaCalendar)
    {
        var total = WeightedDayBudget(start, reset, chinaCalendar);
        if (total <= 0 || now <= start) return 0;
        var currentDayEnd = new DateTimeOffset(now.Date.AddDays(1), now.Offset);
        var elapsed = WeightedDayBudget(start, currentDayEnd < reset ? currentDayEnd : reset, chinaCalendar);
        return elapsed / total * 100;
    }

    private static double WeightedDayBudget(DateTimeOffset start, DateTimeOffset end, bool chinaCalendar)
    {
        if (end <= start) return 0;
        var cursor = new DateTimeOffset(start.Date, start.Offset);
        var total = 0d;
        while (cursor < end)
        {
            var next = cursor.AddDays(1);
            var segmentEnd = next < end ? next : end;
            var dayFraction = (segmentEnd - cursor).TotalSeconds / (next - cursor).TotalSeconds;
            total += dayFraction * DayWeight(cursor, chinaCalendar);
            cursor = segmentEnd;
        }
        return total;
    }

    private static double DayWeight(DateTimeOffset date, bool chinaCalendar)
    {
        var key = date.ToString("yyyy-MM-dd");
        if (chinaCalendar && ChinaMakeupWorkdays2026.Contains(key)) return 1;
        if (chinaCalendar && ChinaHolidays2026.Contains(key)) return .35;
        return date.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday ? .35 : 1;
    }
}
