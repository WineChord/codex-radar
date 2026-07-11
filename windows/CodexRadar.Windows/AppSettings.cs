using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace CodexRadar.Windows;

internal sealed class AppSettings
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunName = "Codex Radar Sentinel";
    private static readonly string SettingsDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CodexRadarSentinel");
    private static readonly string SettingsPath = Path.Combine(SettingsDirectory, "settings.json");
    internal static readonly string InstallerFailureMarkerPath = Path.Combine(SettingsDirectory, "installer-failure.json");

    public bool Chinese { get; set; } = true;
    public DashboardTextSize TextSize { get; set; } = DashboardTextSize.Large;
    public bool PreciseIq { get; set; }
    public StatusBarIqDisplayMode IqDisplayMode { get; set; } = StatusBarIqDisplayMode.Raw;
    public bool ShowPercentSymbol { get; set; } = true;
    public StatusBarSeparator Separator { get; set; } = StatusBarSeparator.Slash;
    public StatusBarHorizontalPadding HorizontalPadding { get; set; } = StatusBarHorizontalPadding.System;
    public StatusBarFontScale FontScale { get; set; } = StatusBarFontScale.Normal;
    public QuotaPacingStrategy PacingStrategy { get; set; } = QuotaPacingStrategy.TimeProportional;
    public bool UseChinaHolidays { get; set; } = true;
    public List<StatusMetric> SelectedStatusMetrics { get; set; } =
        [StatusMetric.WeeklyQuota, StatusMetric.CodexIq, StatusMetric.Signal];
    public bool PredictionNotifications { get; set; } = true;
    public bool IqNotifications { get; set; } = true;
    public bool NotificationSound { get; set; }
    public bool AutomaticUpdates { get; set; } = true;
    public bool AutoResetCreditCheck { get; set; } = true;
    public DateTimeOffset? LastResetCreditCheck { get; set; }
    public List<ResetCredit> CachedResetCredits { get; set; } = [];
    public int? CachedAvailableResetCredits { get; set; }
    public int? CachedTotalEarnedResetCredits { get; set; }
    public ResetCreditFailureInfo? LastResetCreditFailure { get; set; }
    public string? DismissedSpeedAlertKey { get; set; }
    public NotificationMemory NotificationMemory { get; set; } = new();
    public string? LastInstallerFailureVersion { get; set; }
    public DateTimeOffset? LastInstallerFailureAt { get; set; }

    [JsonIgnore]
    public DashboardPreview Preview { get; set; } = DashboardPreview.Live;

    public static AppSettings Load()
    {
        AppSettings settings;
        try
        {
            settings = File.Exists(SettingsPath)
                ? JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(SettingsPath)) ?? new AppSettings()
                : new AppSettings();
        }
        catch { settings = new AppSettings(); }

        settings.SelectedStatusMetrics ??= [];
        settings.CachedResetCredits ??= [];
        settings.NotificationMemory ??= new NotificationMemory();
        settings.CachedResetCredits = settings.CachedResetCredits.OfType<ResetCredit>().ToList();
        settings.SelectedStatusMetrics = Enum.GetValues<StatusMetric>()
            .Where(metric => settings.SelectedStatusMetrics.Contains(metric)).ToList();
        if (settings.SelectedStatusMetrics.Count == 0)
            settings.SelectedStatusMetrics = [StatusMetric.WeeklyQuota, StatusMetric.CodexIq, StatusMetric.Signal];
        var changed = settings.ImportInstallerFailureMarker();
        if (settings.LastInstallerFailureVersion == AppUpdateService.CurrentVersion)
        {
            settings.LastInstallerFailureVersion = null;
            settings.LastInstallerFailureAt = null;
            changed = true;
        }
        settings.Preview = PreviewFromEnvironment();
        if (changed)
        {
            try { settings.Save(); } catch { }
        }
        return settings;
    }

    private bool ImportInstallerFailureMarker()
    {
        if (!File.Exists(InstallerFailureMarkerPath)) return false;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(InstallerFailureMarkerPath));
            var root = document.RootElement;
            if (!root.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.String
                || !root.TryGetProperty("occurred_at", out var occurred) || occurred.ValueKind != JsonValueKind.String
                || !DateTimeOffset.TryParse(occurred.GetString(), out var occurredAt)) return false;
            LastInstallerFailureVersion = version.GetString();
            LastInstallerFailureAt = occurredAt;
            File.Delete(InstallerFailureMarkerPath);
            return true;
        }
        catch { return false; }
    }

    private static DashboardPreview PreviewFromEnvironment()
    {
        var raw = Environment.GetEnvironmentVariable("CODEX_RADAR_PREVIEW");
        return Enum.TryParse<DashboardPreview>(raw, true, out var value) ? value : DashboardPreview.Live;
    }

    public void Save()
    {
        Directory.CreateDirectory(SettingsDirectory);
        var temporary = SettingsPath + $".{Environment.ProcessId}.tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, SettingsPath, true);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
        }
    }

    public AppSettings CreateRefreshSnapshot() => new()
    {
        Chinese = Chinese,
        PacingStrategy = PacingStrategy,
        UseChinaHolidays = UseChinaHolidays,
        CachedResetCredits = [.. CachedResetCredits],
        CachedAvailableResetCredits = CachedAvailableResetCredits,
        CachedTotalEarnedResetCredits = CachedTotalEarnedResetCredits,
        LastResetCreditCheck = LastResetCreditCheck,
        LastResetCreditFailure = LastResetCreditFailure
    };

    public static bool StartsWithWindows
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunName) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value)
                key.SetValue(RunName, $"\"{Environment.ProcessPath}\" --startup");
            else
                key.DeleteValue(RunName, false);
        }
    }
}
