using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Win32;

namespace CodexRadar.Windows;

internal sealed class AppSettings
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunName = "Codex Radar Sentinel";
    internal static readonly string SettingsDirectory =
        ResolveSettingsDirectory();
    private static readonly string SettingsPath = Path.Combine(SettingsDirectory, "settings.json");
    private static readonly object SaveGate = new();
    internal static readonly string InstallerFailureMarkerPath = Path.Combine(SettingsDirectory, "installer-failure.json");

    private static string ResolveSettingsDirectory()
    {
        var validationRoot = Environment.GetEnvironmentVariable(
            "CODEX_RADAR_VALIDATION_DATA_ROOT");
        if (!string.IsNullOrWhiteSpace(validationRoot))
        {
            if (!Path.IsPathFullyQualified(validationRoot))
                throw new InvalidOperationException(
                    "CODEX_RADAR_VALIDATION_DATA_ROOT must be an absolute path.");
            return Path.Combine(
                Path.GetFullPath(validationRoot),
                "CodexRadarSentinel");
        }
        return Path.Combine(
            Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData),
            "CodexRadarSentinel");
    }

    public bool Chinese { get; set; } = true;
    public DashboardTextSize TextSize { get; set; } = DashboardTextSize.Large;
    public bool PreciseIq { get; set; }
    public StatusDisplayMode StatusDisplayMode { get; set; } = StatusDisplayMode.NotificationArea;
    public StatusBarIqDisplayMode IqDisplayMode { get; set; } = StatusBarIqDisplayMode.Raw;
    public bool ShowPercentSymbol { get; set; } = true;
    public StatusBarSeparator Separator { get; set; } = StatusBarSeparator.Slash;
    public StatusBarHorizontalPadding HorizontalPadding { get; set; } = StatusBarHorizontalPadding.System;
    public StatusBarFontScale FontScale { get; set; } = StatusBarFontScale.Normal;
    public List<DashboardSection> DashboardSectionOrder { get; set; } =
        [.. DashboardLayout.DefaultOrder];
    public Dictionary<DashboardSection, bool> DashboardSectionExpansion { get; set; } =
        DashboardLayout.NormalizeExpansion(null);
    public Dictionary<DashboardSection, bool> DashboardSectionVisibility { get; set; } =
        DashboardLayout.NormalizeVisibility(null);
    public Dictionary<DashboardDisclosure, bool> DashboardDisclosureVisibility { get; set; } =
        DashboardLayout.NormalizeDisclosureVisibility(null);
    public bool QuotaHistoryExpanded { get; set; }
    public QuotaHistoryRange QuotaHistoryRange { get; set; } =
        QuotaHistoryRange.Hours24;
    public bool ModelIqDetailsExpanded { get; set; }
    public bool RadarInsightsDetailsExpanded { get; set; }
    public bool LayoutDiscoveryTipDismissed { get; set; }
    public QuotaPacingStrategy PacingStrategy { get; set; } = QuotaPacingStrategy.TimeProportional;
    public bool UseChinaHolidays { get; set; } = true;
    public List<StatusMetric> SelectedStatusMetrics { get; set; } =
        [StatusMetric.WeeklyQuota, StatusMetric.CodexIq, StatusMetric.Signal];
    public bool PredictionNotifications { get; set; } = true;
    public bool IqNotifications { get; set; } = true;
    public bool NotificationSound { get; set; }
    public bool AutomaticUpdates { get; set; } = true;
    public bool AutoResetCreditCheck { get; set; } = true;
    public bool ResetCreditProtectionEnabled { get; set; }
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
        var legacyResetCreditIdentifierFound = false;
        try
        {
            if (File.Exists(SettingsPath))
            {
                var json = File.ReadAllText(SettingsPath);
                legacyResetCreditIdentifierFound = json.Contains(
                    "\"IdSuffix\"", StringComparison.OrdinalIgnoreCase);
                settings = JsonSerializer.Deserialize<AppSettings>(json) ?? new AppSettings();
            }
            else
            {
                settings = new AppSettings();
            }
        }
        catch { settings = new AppSettings(); }

        settings.SelectedStatusMetrics ??= [];
        settings.DashboardSectionOrder = DashboardLayout.NormalizeOrder(
            settings.DashboardSectionOrder);
        settings.DashboardSectionExpansion = DashboardLayout.NormalizeExpansion(
            settings.DashboardSectionExpansion);
        settings.DashboardSectionVisibility = DashboardLayout.NormalizeVisibility(
            settings.DashboardSectionVisibility);
        settings.DashboardDisclosureVisibility =
            DashboardLayout.NormalizeDisclosureVisibility(
                settings.DashboardDisclosureVisibility);
        settings.CachedResetCredits ??= [];
        settings.NotificationMemory ??= new NotificationMemory();
        if (!Enum.IsDefined(settings.StatusDisplayMode))
            settings.StatusDisplayMode = StatusDisplayMode.NotificationArea;
        if (!Enum.IsDefined(settings.QuotaHistoryRange))
            settings.QuotaHistoryRange =
                QuotaHistoryRange.Hours24;
        var cachedResetCredits = settings.CachedResetCredits.OfType<ResetCredit>().ToList();
        var invalidCachedFingerprintFound = cachedResetCredits.Any(
            credit => !ResetCreditPrivacy.IsValidFingerprint(credit.Fingerprint));
        settings.CachedResetCredits = cachedResetCredits
            .Select(ResetCreditPrivacy.NormalizeCachedCredit)
            .ToList();
        settings.SelectedStatusMetrics = Enum.GetValues<StatusMetric>()
            .Where(metric => settings.SelectedStatusMetrics.Contains(metric)).ToList();
        if (settings.SelectedStatusMetrics.Count == 0)
            settings.SelectedStatusMetrics = [StatusMetric.WeeklyQuota, StatusMetric.CodexIq, StatusMetric.Signal];
        var changed = legacyResetCreditIdentifierFound
                      || invalidCachedFingerprintFound
                      || settings.ImportInstallerFailureMarker();
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
        lock (SaveGate)
        {
            Directory.CreateDirectory(SettingsDirectory);
            var temporary = SettingsPath + $".{Environment.ProcessId}.{Guid.NewGuid():N}.tmp";
            try
            {
                File.WriteAllText(
                    temporary,
                    JsonSerializer.Serialize(
                        this,
                        new JsonSerializerOptions { WriteIndented = true }));
                File.Move(temporary, SettingsPath, true);
            }
            finally
            {
                try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
            }
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

    public bool IsDashboardSectionExpanded(DashboardSection section) =>
        DashboardSectionExpansion.TryGetValue(section, out var expanded)
            ? expanded
            : DashboardLayout.DefaultExpanded.Contains(section);

    public void SetDashboardSectionExpanded(DashboardSection section, bool expanded) =>
        DashboardSectionExpansion[section] = expanded;

    public bool IsDashboardSectionVisible(
        DashboardSection section) =>
        DashboardSectionVisibility.TryGetValue(
            section,
            out var visible)
            ? visible
            : true;

    public void SetDashboardSectionVisible(
        DashboardSection section,
        bool visible) =>
        DashboardSectionVisibility[section] = visible;

    public bool IsDashboardDisclosureExpanded(
        DashboardDisclosure disclosure) => disclosure switch
    {
        DashboardDisclosure.QuotaHistory =>
            QuotaHistoryExpanded,
        DashboardDisclosure.ModelIqDetails =>
            ModelIqDetailsExpanded,
        DashboardDisclosure.RadarInsightsDetails =>
            RadarInsightsDetailsExpanded,
        _ => false
    };

    public void SetDashboardDisclosureExpanded(
        DashboardDisclosure disclosure,
        bool expanded)
    {
        switch (disclosure)
        {
            case DashboardDisclosure.QuotaHistory:
                QuotaHistoryExpanded = expanded;
                break;
            case DashboardDisclosure.ModelIqDetails:
                ModelIqDetailsExpanded = expanded;
                break;
            case DashboardDisclosure.RadarInsightsDetails:
                RadarInsightsDetailsExpanded = expanded;
                break;
        }
    }

    public bool IsDashboardDisclosureVisible(
        DashboardDisclosure disclosure) =>
        DashboardDisclosureVisibility.TryGetValue(
            disclosure,
            out var visible)
            ? visible
            : true;

    public void SetDashboardDisclosureVisible(
        DashboardDisclosure disclosure,
        bool visible) =>
        DashboardDisclosureVisibility[disclosure] =
            visible;

    public void MoveDashboardSection(DashboardSection section, int offset)
    {
        DashboardSectionOrder = DashboardLayout.NormalizeOrder(DashboardSectionOrder);
        var source = DashboardSectionOrder.IndexOf(section);
        if (source < 0) return;
        var target = Math.Clamp(source + offset, 0, DashboardSectionOrder.Count - 1);
        MoveDashboardSectionTo(
            section,
            target,
            normalizeFirst: false);
    }

    public void MoveDashboardSectionTo(
        DashboardSection section,
        int targetIndex,
        bool normalizeFirst = true)
    {
        if (normalizeFirst)
            DashboardSectionOrder =
                DashboardLayout.NormalizeOrder(
                    DashboardSectionOrder);
        var source = DashboardSectionOrder.IndexOf(section);
        if (source < 0) return;
        var target = Math.Clamp(
            targetIndex,
            0,
            DashboardSectionOrder.Count - 1);
        if (source == target) return;
        DashboardSectionOrder.RemoveAt(source);
        DashboardSectionOrder.Insert(target, section);
    }

    public void ResetDashboardLayout()
    {
        DashboardSectionOrder = [.. DashboardLayout.DefaultOrder];
        DashboardSectionExpansion = DashboardLayout.NormalizeExpansion(null);
        DashboardSectionVisibility =
            DashboardLayout.NormalizeVisibility(null);
        DashboardDisclosureVisibility =
            DashboardLayout.NormalizeDisclosureVisibility(null);
        QuotaHistoryExpanded = false;
        ModelIqDetailsExpanded = false;
        RadarInsightsDetailsExpanded = false;
    }

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
