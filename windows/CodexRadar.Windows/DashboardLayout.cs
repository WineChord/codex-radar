namespace CodexRadar.Windows;

internal enum DashboardSection
{
    Quota,
    ModelIq,
    ResetCredits,
    UsagePace,
    Insights,
    RadarDetails,
    TaskbarGuide,
    DisplayAndAlerts,
    Updates,
    Preview
}

internal enum DashboardDisclosure
{
    QuotaHistory,
    ModelIqDetails,
    RadarInsightsDetails
}

internal sealed record DashboardSectionResolution(
    bool IsVisible,
    bool IsExpanded,
    bool CanHide,
    bool CanCollapse);

internal static class DashboardLayout
{
    public static readonly DashboardSection[] DefaultOrder =
    [
        DashboardSection.Quota,
        DashboardSection.ModelIq,
        DashboardSection.ResetCredits,
        DashboardSection.UsagePace,
        DashboardSection.Insights,
        DashboardSection.RadarDetails,
        DashboardSection.TaskbarGuide,
        DashboardSection.DisplayAndAlerts,
        DashboardSection.Updates,
        DashboardSection.Preview
    ];

    public static readonly HashSet<DashboardSection> DefaultExpanded =
    [
        DashboardSection.Quota,
        DashboardSection.ModelIq,
        DashboardSection.UsagePace,
        DashboardSection.Insights
    ];

    public static DashboardSection ParentSection(
        DashboardDisclosure disclosure) => disclosure switch
    {
        DashboardDisclosure.QuotaHistory => DashboardSection.Quota,
        DashboardDisclosure.ModelIqDetails => DashboardSection.ModelIq,
        DashboardDisclosure.RadarInsightsDetails =>
            DashboardSection.Insights,
        _ => throw new ArgumentOutOfRangeException(
            nameof(disclosure))
    };

    public static IReadOnlyList<DashboardDisclosure> Children(
        DashboardSection section) =>
        Enum.GetValues<DashboardDisclosure>()
            .Where(disclosure =>
                ParentSection(disclosure) == section)
            .ToArray();

    public static List<DashboardSection> NormalizeOrder(
        IEnumerable<DashboardSection>? proposed)
    {
        var seen = new HashSet<DashboardSection>();
        var normalized = (proposed ?? [])
            .Where(Enum.IsDefined)
            .Where(section => seen.Add(section))
            .ToList();
        if (normalized.Count == 0) return [.. DefaultOrder];

        for (var defaultIndex = 0; defaultIndex < DefaultOrder.Length; defaultIndex++)
        {
            var section = DefaultOrder[defaultIndex];
            if (seen.Contains(section)) continue;
            DashboardSection? preceding = DefaultOrder.Take(defaultIndex).Reverse()
                .Where(candidate => seen.Contains(candidate))
                .Cast<DashboardSection?>()
                .FirstOrDefault();
            DashboardSection? following = DefaultOrder.Skip(defaultIndex + 1)
                .Where(candidate => seen.Contains(candidate))
                .Cast<DashboardSection?>()
                .FirstOrDefault();
            if (preceding is DashboardSection precedingSection)
            {
                normalized.Insert(normalized.IndexOf(precedingSection) + 1, section);
            }
            else if (following is DashboardSection followingSection)
            {
                normalized.Insert(normalized.IndexOf(followingSection), section);
            }
            else
            {
                normalized.Add(section);
            }
            seen.Add(section);
        }
        return normalized;
    }

    public static Dictionary<DashboardSection, bool> NormalizeExpansion(
        IReadOnlyDictionary<DashboardSection, bool>? proposed)
    {
        return Enum.GetValues<DashboardSection>().ToDictionary(
            section => section,
            section => proposed?.TryGetValue(section, out var expanded) == true
                ? expanded
                : DefaultExpanded.Contains(section));
    }

    public static Dictionary<DashboardSection, bool> NormalizeVisibility(
        IReadOnlyDictionary<DashboardSection, bool>? proposed) =>
        Enum.GetValues<DashboardSection>().ToDictionary(
            section => section,
            section =>
                proposed?.TryGetValue(
                    section,
                    out var visible) != true
                || visible);

    public static Dictionary<DashboardDisclosure, bool>
        NormalizeDisclosureVisibility(
            IReadOnlyDictionary<DashboardDisclosure, bool>? proposed) =>
        Enum.GetValues<DashboardDisclosure>().ToDictionary(
            disclosure => disclosure,
            disclosure =>
                proposed?.TryGetValue(
                    disclosure,
                    out var visible) != true
                || visible);

    public static bool IsDefault(
        IReadOnlyList<DashboardSection> order,
        IReadOnlyDictionary<DashboardSection, bool> expansion,
        IReadOnlyDictionary<DashboardSection, bool>? visibility = null,
        IReadOnlyDictionary<DashboardDisclosure, bool>?
            disclosureVisibility = null) =>
        order.SequenceEqual(DefaultOrder)
        && Enum.GetValues<DashboardSection>().All(section =>
            expansion.TryGetValue(section, out var expanded)
            && expanded == DefaultExpanded.Contains(section))
        && NormalizeVisibility(visibility).Values.All(value => value)
        && NormalizeDisclosureVisibility(
            disclosureVisibility).Values.All(value => value);

    public static DashboardSectionResolution Resolve(
        DashboardSection section,
        bool preferredVisible,
        bool preferredExpanded,
        ResetCreditProtectionStatus resetCreditStatus,
        bool requiresUpdateAttention)
    {
        var forced = section switch
        {
            DashboardSection.ResetCredits =>
                resetCreditStatus.NeedsAttention,
            DashboardSection.Updates =>
                requiresUpdateAttention,
            _ => false
        };
        return new DashboardSectionResolution(
            preferredVisible || forced,
            preferredExpanded || forced,
            CanHide: !forced,
            CanCollapse: !forced);
    }
}
