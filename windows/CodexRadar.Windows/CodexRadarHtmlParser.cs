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
        var communities = ParseCommunityKnowledges(html);
        var community = communities.FirstOrDefault();
        var announcement = ParseAnnouncement(html);
        var fastRadar = ParseFastRadar(html);
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
            CommunityKnowledge = community?.Title,
            CommunityPrompt = community?.Prompt,
            CommunityKnowledges = communities,
            FastRadar = fastRadar,
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
        var cards = Matches(
                @"<article\s+class=[""'][^""']*reset-judgement-card[^""']*[""'][^>]*>(.*?)</article>",
                section)
            .Select(groups => groups[0])
            .Select(card =>
            {
                var label = Clean(Capture(@"<span(?:\s+[^>]*)?>(.*?)</span>", card));
                var state = Clean(Capture(
                    @"<em\s+class=[""'][^""']*reset-judgement-state[^""']*[""'][^>]*>(.*?)</em>",
                    card));
                var headline = Clean(Capture(@"<strong(?:\s+[^>]*)?>(.*?)</strong>", card));
                var detail = Clean(Capture(@"<p(?:\s+[^>]*)?>(.*?)</p>", card));
                var level = state.Length == 0 ? headline : state;
                var summary = state.Length == 0
                    ? detail
                    : string.Join(" — ", new[] { headline, detail }.Where(value => value.Length > 0));
                return new ResetJudgementCard(label, level, summary);
            })
            .Where(card => !string.IsNullOrWhiteSpace(card.Label)
                           && !string.IsNullOrWhiteSpace(card.Level)
                           && !string.IsNullOrWhiteSpace(card.Summary))
            .ToArray();
        var reasons = Matches(@"<li>(.*?)</li>", section).Select(x => Clean(x[0])).Where(x => x.Length > 0).ToArray();
        return (Empty(title), Empty(updated), cards, reasons);
    }

    private static IReadOnlyList<CommunityKnowledgeInfo>
        ParseCommunityKnowledges(string html)
    {
        var section = ElementByClass("section", "community-knowledge", html);
        if (section is null) return [];
        return Matches(
                @"<article\s+class=[""'][^""']*community-knowledge-card[^""']*[""'][^>]*>(.*?)</article>",
                section)
            .Select(groups => groups[0])
            .Select(card =>
            {
                var prompt = Empty(CleanMultiline(Capture(
                    @"<(?:code|div)[^>]*data-site-announcement-prompt[^>]*>(.*?)</(?:code|div)>", card)));
                var main = ElementByClass("div", "community-knowledge-card-main", card) ?? card;
                prompt ??= Empty(Clean(Capture(@"<p\b[^>]*>(.*?)</p>", main)));
                prompt ??= Empty(Clean(Capture(@"<img\b[^>]*\salt=[""']([^""']+)[""']", main)));
                var source = SourceLink(card);
                return new CommunityKnowledgeInfo(
                    Empty(Clean(Capture(@"<h2\b[^>]*>(.*?)</h2>", card))),
                    prompt, source.Url, source.Label);
            })
            .Where(item => !string.IsNullOrWhiteSpace(item.Title)
                           && !string.IsNullOrWhiteSpace(item.Prompt))
            .ToArray();
    }

    private static FastRadarInfo? ParseFastRadar(string html)
    {
        var section = ElementByClass("section", "fast-radar", html);
        if (section is null) return null;

        var updated = Clean(Capture(
            @"<h2>.*?<em>(.*?)</em>.*?</h2>", section));
        var title = Clean(Capture(@"<h2>(.*?)</h2>", section));
        if (updated.Length > 0)
            title = title.Replace(
                updated, "", StringComparison.Ordinal).Trim();
        var subtitle = Clean(Capture(
            @"<div\s+class=[""']fast-radar-head[""'][^>]*>.*?</h2>\s*</div>\s*<span>(.*?)</span>",
            section));
        var summarySection = Capture(
            @"<div\s+class=[""']fast-radar-summary[""'][^>]*>(.*?)</div>\s*<div\s+class=[""']fast-radar-table[""']",
            section) ?? "";
        var summary = Matches(
                @"<div\b[^>]*>\s*<span\b[^>]*>(.*?)</span>\s*<strong\b[^>]*>(.*?)</strong>\s*</div>",
                summarySection)
            .Select(groups => new FastRadarSummaryItem(
                Empty(Clean(groups[0])),
                Empty(Clean(groups[1]))))
            .Where(item => item.Label is not null
                           && item.Value is not null)
            .ToArray();
        if (summary.Length == 0)
        {
            summary = Matches(ClassElementPattern("div", "fast-simple-row"), section)
                .Select(groups => groups[0])
                .Select(row => new FastRadarSummaryItem(
                    Empty(Clean(Regex.Replace(
                        Capture(@"<strong\b[^>]*>(.*?)</strong>", row) ?? "",
                        @"<small\b[^>]*>.*?</small>", "", RegexOptions.Singleline | RegexOptions.IgnoreCase))) is { } model
                        ? model + " · TPS" : null,
                    Empty(Clean(ElementByClass("strong", "fast-simple-ratio", row)))))
                .Where(item => item.Label is not null && item.Value is not null)
                .ToArray();
        }
        var rows = Matches(
                @"<div\s+class=[""']fast-radar-row[""'][^>]*>\s*<div\s+class=[""']fast-radar-model[""'][^>]*>.*?<strong>(.*?)</strong></div>\s*<div\s+class=[""']fast-radar-metric[^""']*[""'][^>]*data-label=[""']([^""']+)[""'][^>]*>\s*<span>(.*?)</span>\s*<strong>(.*?)</strong>\s*</div>\s*<div\s+class=[""']fast-radar-metric[^""']*[""'][^>]*data-label=[""']([^""']+)[""'][^>]*>\s*<span>(.*?)</span>\s*<strong>(.*?)</strong>\s*</div>\s*<div\s+class=[""']fast-radar-metric[^""']*[""'][^>]*data-label=[""']([^""']+)[""'][^>]*>\s*<span>(.*?)</span>\s*<strong>(.*?)</strong>\s*</div>\s*</div>",
                section)
            .Where(groups => groups.Length == 10)
            .Select(groups => new FastRadarRow(
                Empty(Clean(groups[0])),
                FastMetric(groups[1], groups[2], groups[3]),
                FastMetric(groups[4], groups[5], groups[6]),
                FastMetric(groups[7], groups[8], groups[9])))
            .Where(row => row.Model is not null)
            .ToArray();
        var explanation = ElementByClass("(?:div|details)", "fast-radar-explain", html);
        var method = Empty(CleanMultiline(explanation is null ? null
            : Capture(@"<p\b[^>]*>(.*?)</p>", explanation)));
        if (summary.Length == 0 && rows.Length == 0) return null;
        return new FastRadarInfo(
            Empty(title) ?? "Fast 雷达",
            Empty(updated),
            Empty(subtitle),
            summary,
            rows,
            method);
    }

    private static FastRadarMetric FastMetric(
        string? label,
        string? range,
        string? value) => new(
        Empty(Clean(label)),
        Empty(Clean(range)),
        Empty(Clean(value)));

    private static (string? Label, string? Message, string? Updated, string? SourceLabel, string? SourceUrl) ParseAnnouncement(string html)
    {
        var section = ElementByClass("section", "site-announcement", html);
        if (section is null) return (null, null, null, null, null);
        var label = Clean(ElementByClass("span", "site-announcement-label", section)
                          ?? Capture(@"<span\b[^>]*>(.*?)</span>", section));
        var updated = Clean(ElementByClass("span", "site-announcement-updated", section)
                            ?? ElementByClass("span", "site-announcement-lead", section));
        var headline = Empty(Clean(ElementByClass("strong", "site-announcement-headline", section)));
        var detail = Empty(Clean(ElementByClass("p", "site-announcement-reset-detail", section)));
        var source = SourceLink(section, "site-announcement-source", "pro-subscription-announcement-link");
        var paragraph = Capture(@"<p\b[^>]*>(.*?)</p>", section) ?? "";
        var messageHtml = Regex.Replace(paragraph, ClassElementPattern("a", "site-announcement-source"), "",
            RegexOptions.Singleline | RegexOptions.IgnoreCase);
        messageHtml = Regex.Replace(messageHtml, ClassElementPattern("span", "site-announcement-updated"), "",
            RegexOptions.Singleline | RegexOptions.IgnoreCase);
        var leads = Matches(ClassElementPattern("p", "site-announcement-lead"), section)
            .Select(groups => Clean(groups[0])).Where(value => value.Length > 0);
        var message = headline is null ? Clean(messageHtml)
            : detail is not null ? headline + " — " + detail
            : string.Join("\n\n", new[] { headline }.Concat(leads));
        return (Empty(label) ?? "公告", Empty(message), Empty(updated), source.Label, source.Url);
    }

    private static (string? Url, string? Label) SourceLink(string html, params string[] classes)
    {
        foreach (var link in Matches(@"<a\b([^>]*)>(.*?)</a>", html))
        {
            var tokens = (Capture(@"\bclass\s*=\s*[""']([^""']*)[""']", link[0]) ?? "")
                .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (classes.Length > 0 && !classes.Any(value => tokens.Contains(value, StringComparer.OrdinalIgnoreCase)))
                continue;
            var url = PublicWebLink.Normalize(WebUtility.HtmlDecode(
                Capture(@"\bhref\s*=\s*[""']([^""']+)[""']", link[0])), allowRelative: true);
            if (url is not null) return (url, Empty(Clean(link[1])));
        }
        return (null, null);
    }

    private static string ClassElementPattern(string tag, string className) =>
        $@"<{tag}\b(?=[^>]*\sclass\s*=\s*[""'][^""']*(?<![\w-]){Regex.Escape(className)}(?![\w-])[^""']*[""'])[^>]*>(.*?)</{tag}>";

    private static string? ElementByClass(string tag, string className, string html) =>
        Capture(ClassElementPattern(tag, className), html);

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
