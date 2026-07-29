using System.Net;
using System.Text.RegularExpressions;

namespace CodexRadar.Windows;

internal static partial class CodexRadarHtmlParser
{
    public static PublicRadarData Parse(string html, DateTimeOffset? checkedAt = null)
    {
        var now = checkedAt ?? DateTimeOffset.Now;
        var data = ParseModelIq(html, now) ?? new PublicRadarData();
        var reset = ParseResetJudgement(html);
        var community = ParseCommunityKnowledge(html);
        var announcement = ParseAnnouncement(html);
        return data with
        {
            SchemaVersion = "homepage-fallback-v1",
            CheckedAt = now,
            RadarStatus = "retired",
            RecommendedAction = "wait",
            WindowOpen = false,
            WindowId = "codexradar-reset-radar-retired",
            WindowStatus = "retired",
            WindowTitle = "CodexRadar model quality radar",
            WindowHuman = "none",
            WindowScope = "CodexRadar model quality radar",
            WindowSummary = "CodexRadar homepage fallback: Model IQ and public radar signals.",
            Prediction = data.Prediction ?? new PredictionInfo("low", 0, 0, false, null,
                "Legacy reset prediction and speed-window alerts are retired.", now),
            ResetRadarTitle = reset.Title,
            ResetRadarUpdatedLabel = reset.Updated,
            ResetRadarCards = reset.Cards,
            ResetRadarReasons = reset.Reasons,
            ResetRadar = ResetText(reset),
            CommunityKnowledge = community.Title,
            CommunityPrompt = community.Prompt,
            AnnouncementLabel = announcement.Label,
            Announcement = announcement.Message,
            AnnouncementUpdatedLabel = announcement.Updated,
            AnnouncementSourceLabel = announcement.SourceLabel,
            AnnouncementUrl = announcement.SourceUrl
        };
    }

    private static PublicRadarData? ParseModelIq(string html, DateTimeOffset checkedAt)
    {
        var distributed = ParseDistributedModelIq(html);
        if (distributed is not null) return distributed;

        var snapshots = new List<HomepageIq>();
        foreach (Match match in IqTitleRegex().Matches(html))
        {
            var monthText = NonEmpty(match.Groups[1].Value, match.Groups[3].Value);
            var dayText = NonEmpty(match.Groups[2].Value, match.Groups[4].Value);
            if (!int.TryParse(monthText, out var month) || !int.TryParse(dayText, out var day)
                || !double.TryParse(match.Groups[7].Value, System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var score)
                || !int.TryParse(match.Groups[8].Value, out var passed)
                || !int.TryParse(match.Groups[9].Value, out var tasks)) continue;
            _ = double.TryParse(match.Groups[10].Value, System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var cost);
            _ = int.TryParse(match.Groups[11].Value, out var minutes);
            _ = double.TryParse(match.Groups[12].Value, System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var parsedCache);
            var parts = Regex.Split(Clean(match.Groups[6].Value), @"\s+").Where(x => x.Length > 0).ToArray();
            snapshots.Add(new HomepageIq(month, day, match.Groups[5].Value.ToLowerInvariant(),
                parts.FirstOrDefault(), parts.Length > 1 ? string.Join(" ", parts.Skip(1)) : null,
                score, passed, tasks, match.Groups[10].Success ? cost : null,
                match.Groups[11].Success ? minutes * 60 : null, match.Groups[12].Success ? parsedCache : null));
        }
        var latest = snapshots.MaxBy(x => x.SortKey);
        if (latest is null) return null;
        var comparisons = snapshots.GroupBy(x => x.ModelKey).Select(group => group.MaxBy(x => x.SortKey)!)
            .Where(x => x.ModelKey != latest.ModelKey).Select(x => x.Comparison()).ToList();
        return new PublicRadarData
        {
            IqDate = latest.Date(checkedAt.Year), IqScore = latest.Score, IqStatus = IqStatus(latest.Score),
            ModelLabel = latest.Label, ModelName = latest.Model, ReasoningEffort = latest.Effort,
            Passed = latest.Passed, ValidTasks = latest.Tasks,
            CostUsd = latest.Cost, WallTime = latest.WallSeconds is int seconds ? $"{Math.Max(1, seconds / 60)} min" : null,
            CacheHitRate = latest.CacheRate is double displayCache ? $"{displayCache:0.0}%" : null,
            Comparisons = comparisons
        };
    }

    private static PublicRadarData? ParseDistributedModelIq(string html)
    {
        var chart = Capture(@"<div\s+class=[""']model-iq-chart-view[""']\s+data-model-iq-chart-view=[""']iq[""']>(.*?)</div>", html);
        if (chart is null) return null;
        var snapshots = Matches(
                @"<circle[^>]+data-model-key=[""']([^""']+)[""'][^>]+data-model-iq-tooltip-key=[""']iq\|([^|""']+)\|[^""']+[""'][^>]+aria-label=[""']([^""']+)[""'][^>]*>",
                chart)
            .Select(groups => groups.Length == 3
                ? DistributedHomepageIq.Parse(groups[0], groups[1], Clean(groups[2]))
                : null)
            .Where(snapshot => snapshot is not null)
            .Cast<DistributedHomepageIq>()
            .ToArray();
        if (snapshots.Length == 0) return null;
        var latestByModel = snapshots.GroupBy(snapshot => snapshot.ModelKey)
            .Select(group => group.MaxBy(snapshot => snapshot.TimestampDate)!)
            .ToArray();
        var primary = latestByModel.FirstOrDefault(snapshot => snapshot.ModelKey == "gpt_56_sol_max")
                      ?? latestByModel.MaxBy(snapshot => snapshot.TimestampDate);
        if (primary is null) return null;
        return new PublicRadarData
        {
            IqDate = primary.Timestamp,
            IqScore = primary.Score,
            IqStatus = IqStatus(primary.Score),
            ModelLabel = primary.Label,
            ModelName = primary.Model,
            ReasoningEffort = primary.Effort,
            Passed = primary.Passed,
            ValidTasks = primary.Tasks,
            AverageCostUsd = primary.AverageCostUsd,
            AverageTaskMinutes = primary.AverageTaskMinutes,
            CacheHitRate = $"{primary.CacheHitRate:0.0}%",
            Comparisons = latestByModel.Where(snapshot => snapshot.ModelKey != primary.ModelKey)
                .Select(snapshot => snapshot.Comparison()).ToArray(),
            IqDataSourceUrl = "https://deng.codexradar.com",
            IqSourceUpdatedAt = primary.TimestampDate
        };
    }

    private static (string? Title, string? Updated, IReadOnlyList<ResetJudgementCard> Cards, IReadOnlyList<string> Reasons) ParseResetJudgement(string html)
    {
        var section = Capture(@"<section\s+class=[""']reset-judgement[""'][^>]*>(.*?)</section>", html);
        if (section is null) return (null, null, [], []);
        var title = Clean(Capture(@"<div\s+class=[""']reset-judgement-head[""']>.*?<strong>(.*?)</strong>", section));
        var updated = Clean(Capture(@"<h2>.*?<em>(.*?)</em>.*?</h2>", section));
        var cards = Matches(@"<article\s+class=[""']reset-judgement-card[^""']*[""']>\s*<span>(.*?)</span>\s*<strong>(.*?)</strong>\s*<p>(.*?)</p>", section)
            .Select(groups => new ResetJudgementCard(Clean(groups[0]), Clean(groups[1]), Clean(groups[2]))).ToArray();
        var reasons = Matches(@"<li>(.*?)</li>", section).Select(x => Clean(x[0])).Where(x => x.Length > 0).ToArray();
        return (Empty(title), Empty(updated), cards, reasons);
    }

    private static (string? Title, string? Prompt) ParseCommunityKnowledge(string html)
    {
        var section = Capture(@"<section\s+class=[""']community-knowledge[""'][^>]*>(.*?)</section>", html);
        var card = section is null ? null : Capture(@"<article\s+class=[""']community-knowledge-card[""'][^>]*>(.*?)</article>", section);
        if (card is null) return (null, null);
        return (Empty(Clean(Capture(@"<h2>(.*?)</h2>", card))),
            Empty(CleanMultiline(Capture(@"<code[^>]*data-site-announcement-prompt[^>]*>(.*?)</code>", card))));
    }

    private static (string? Label, string? Message, string? Updated, string? SourceLabel, string? SourceUrl) ParseAnnouncement(string html)
    {
        var section = Capture(@"<section\s+class=[""']site-announcement[""'][^>]*>(.*?)</section>", html);
        var paragraph = section is null ? null : Capture(@"<p>(.*?)</p>", section);
        if (section is null || paragraph is null) return (null, null, null, null, null);
        var label = Clean(Capture(@"<span>(.*?)</span>", section));
        var updated = Clean(Capture(@"<span\s+class=[""']site-announcement-updated[""'][^>]*>(.*?)</span>", paragraph));
        var source = Matches(@"<a\s+class=[""']site-announcement-source[""']\s+href=[""']([^""']+)[""'][^>]*>(.*?)</a>", paragraph).FirstOrDefault();
        var messageHtml = Regex.Replace(paragraph, @"<a\s+class=[""']site-announcement-source[^>]*>.*?</a>", "", RegexOptions.Singleline | RegexOptions.IgnoreCase);
        messageHtml = Regex.Replace(messageHtml, @"<br\s*/?>\s*<span\s+class=[""']site-announcement-updated[""'][^>]*>.*?</span>", "", RegexOptions.Singleline | RegexOptions.IgnoreCase);
        var message = Clean(messageHtml);
        return (Empty(label) ?? "公告", Empty(message), Empty(updated), source is { Length: >= 2 } ? Empty(Clean(source[1])) : null,
            source is { Length: >= 2 } ? Empty(Clean(source[0])) : null);
    }

    private static string? ResetText((string? Title, string? Updated, IReadOnlyList<ResetJudgementCard> Cards, IReadOnlyList<string> Reasons) reset)
    {
        var lines = reset.Cards.Select(card => string.Join(" · ", new[] { card.Label, card.Level, card.Summary }
            .Where(x => !string.IsNullOrWhiteSpace(x)))).Concat(reset.Reasons).Where(x => x.Length > 0).ToArray();
        return lines.Length > 0 ? string.Join(Environment.NewLine, lines) : reset.Title;
    }

    private static string? Capture(string pattern, string text)
    {
        var match = Regex.Match(text, pattern, RegexOptions.Singleline | RegexOptions.IgnoreCase);
        return match.Success && match.Groups.Count > 1 ? match.Groups[1].Value : null;
    }
    private static IEnumerable<string[]> Matches(string pattern, string text) => Regex.Matches(text, pattern,
            RegexOptions.Singleline | RegexOptions.IgnoreCase).Cast<Match>()
        .Select(match => match.Groups.Cast<Group>().Skip(1).Select(group => group.Value).ToArray());
    private static string Clean(string? value) => Regex.Replace(WebUtility.HtmlDecode(Regex.Replace(value ?? "", "<[^>]+>", "")), @"\s+", " ").Trim();
    private static string CleanMultiline(string? value) => string.Join("\n", WebUtility.HtmlDecode(Regex.Replace(value ?? "", "<[^>]+>", ""))
        .Replace("\r\n", "\n").Replace('\r', '\n').Split('\n').Select(line => line.Trim())).Trim();
    private static string? Empty(string? value) => string.IsNullOrWhiteSpace(value) ? null : value;
    private static string NonEmpty(string first, string second) => first.Length > 0 ? first : second;
    private static string IqStatus(double score) => score < 80 ? "red" : score < 95 ? "yellow" : "green";

    [GeneratedRegex(@"<title>\s*(?:(\d{1,2})月(\d{1,2})日|(\d{1,2})\.(\d{1,2})(?:[_-]([A-Za-z0-9_]+))?)\s+([^:]+):\s*IQ指数\s*([0-9]+(?:\.[0-9]+)?),\s*(\d+)/(\d+)(?:,\s*费用\s*\$([0-9]+(?:\.[0-9]+)?),\s*耗时\s*([0-9]+)分钟,\s*cache命中率\s*([0-9]+(?:\.[0-9]+)?)%)?", RegexOptions.IgnoreCase)]
    private static partial Regex IqTitleRegex();

    private sealed record HomepageIq(int Month, int Day, string Phase, string? Model, string? Effort,
        double Score, int Passed, int Tasks, double? Cost, int? WallSeconds, double? CacheRate)
    {
        public int SortKey => Month * 1_000_000 + Day * 10_000 + PhaseRank * 1_000 + ModelPriority;
        public string ModelKey => Regex.Replace(string.Join("-", new[] { Model, Effort }.Where(x => !string.IsNullOrWhiteSpace(x))).ToLowerInvariant(), "[^a-z0-9]+", "_").Trim('_') is { Length: > 0 } key ? key : "unknown";
        public string Label => string.Join(" ", new[] { Model?.StartsWith("gpt-", StringComparison.OrdinalIgnoreCase) == true ? Model.ToUpperInvariant() : Model, Effort }.Where(x => !string.IsNullOrWhiteSpace(x)));
        public string Date(int year) => $"{year:0000}-{Month:00}-{Day:00}{(Phase.Length > 0 ? $"-{Phase}" : "")}";
        public ModelComparison Comparison() => new(Label, Score, IqStatus(Score), Passed, Tasks, null, null,
            WallSeconds is int seconds ? $"{Math.Max(1, seconds / 60)} min" : null, Cost,
            CacheRate is double cache ? $"{cache:0.0}%" : null);
        private int PhaseRank => Phase switch { "pm" => 2, "am" => 1, _ => 0 };
        private int ModelPriority
        {
            get
            {
                var match = Regex.Match(Model ?? "", @"(\d+(?:\.\d+)?)");
                var version = match.Success && double.TryParse(match.Value, System.Globalization.CultureInfo.InvariantCulture, out var number) ? number : 0;
                var effort = Effort?.ToLowerInvariant() ?? "";
                var rank = effort.Contains("xhigh") ? 3 : effort.Contains("high") ? 2 : effort.Contains("medium") ? 1 : 0;
                return (int)(version * 10) * 10 + rank;
            }
        }
    }

    private sealed record DistributedHomepageIq(
        string ModelKey,
        string Timestamp,
        string Label,
        string? Model,
        string? Effort,
        double Score,
        int Passed,
        int Tasks,
        double AverageCostUsd,
        int AverageTaskMinutes,
        double CacheHitRate)
    {
        private static readonly Regex AriaLabelRegex = new(
            @"^[^\s]+\s+(.+?):\s*IQ指数\s*([0-9]+(?:\.[0-9]+)?),\s*(\d+)/(\d+),\s*平均费用\s*\$([0-9]+(?:\.[0-9]+)?),\s*平均耗时\s*(\d+)分钟,\s*cache命中率\s*([0-9]+(?:\.[0-9]+)?)%$",
            RegexOptions.CultureInvariant);

        public DateTimeOffset TimestampDate => RadarJson.Date(Timestamp) ?? DateTimeOffset.MinValue;

        public static DistributedHomepageIq? Parse(
            string modelKey,
            string timestamp,
            string ariaLabel)
        {
            var match = AriaLabelRegex.Match(ariaLabel);
            if (!match.Success
                || !double.TryParse(match.Groups[2].Value,
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var score)
                || !int.TryParse(match.Groups[3].Value, out var passed)
                || !int.TryParse(match.Groups[4].Value, out var tasks)
                || !double.TryParse(match.Groups[5].Value,
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var cost)
                || !int.TryParse(match.Groups[6].Value, out var minutes)
                || !double.TryParse(match.Groups[7].Value,
                    System.Globalization.NumberStyles.Float,
                    System.Globalization.CultureInfo.InvariantCulture, out var cache))
                return null;
            var (model, effort, label) = ModelParts(modelKey);
            return new DistributedHomepageIq(
                modelKey,
                timestamp,
                label ?? match.Groups[1].Value,
                model,
                effort,
                score,
                passed,
                tasks,
                cost,
                minutes,
                cache);
        }

        public ModelComparison Comparison() => new(
            Label,
            Score,
            IqStatus(Score),
            Passed,
            Tasks,
            CacheHitRate: $"{CacheHitRate:0.0}%",
            Model: Model,
            Effort: Effort,
            AverageCostUsd: AverageCostUsd,
            AverageMinutes: AverageTaskMinutes,
            LatestGradedAt: Timestamp);

        private static (string? Model, string? Effort, string? Label) ModelParts(string modelKey)
        {
            var parts = modelKey.Split('_', StringSplitOptions.RemoveEmptyEntries).ToList();
            if (parts.LastOrDefault() == "distributed") parts.RemoveAt(parts.Count - 1);
            if (parts.Count < 3 || parts[0] != "gpt" || parts[1].Length < 2)
                return (null, null, null);
            var version = $"{parts[1][0]}.{parts[1][1..]}";
            var families = new HashSet<string>(["sol", "terra", "luna"]);
            var family = parts.Count >= 4 && families.Contains(parts[2]) ? parts[2] : null;
            var effortIndex = family is null ? 2 : 3;
            if (effortIndex >= parts.Count) return (null, null, null);
            var effort = parts[effortIndex];
            var model = $"gpt-{version}" + (family is null ? "" : $"-{family}");
            var familyLabel = family is null ? null
                : char.ToUpperInvariant(family[0]) + family[1..];
            var label = string.Join(" ", new[] { $"GPT-{version}", familyLabel, effort }
                .Where(value => !string.IsNullOrWhiteSpace(value)));
            return (model, effort, label);
        }
    }
}
