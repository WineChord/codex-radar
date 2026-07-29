using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CodexRadar.Windows;

internal sealed record IntelligenceEfficiencyEnvelope(
    int? Schema,
    string? Type,
    string? SourceUpdatedAt,
    IReadOnlyList<IntelligenceEfficiencyPoint> Points)
{
    public IReadOnlyList<IntelligenceEfficiencyPoint> UsablePoints =>
        Points.Where(point => point.IsUsable).ToArray();
}

internal sealed record IntelligenceEfficiencyPoint(
    string? Model,
    string? Effort,
    double? Iq,
    int? Passed,
    int? ValidTasks,
    double? AveragePriceUsd,
    double? AverageMinutes,
    string? LatestGradedAt,
    double? CacheHitRate)
{
    public string? PairKey =>
        string.IsNullOrWhiteSpace(Model) || string.IsNullOrWhiteSpace(Effort)
            ? null
            : $"{Model.Trim().ToLowerInvariant()}/{Effort.Trim().ToLowerInvariant()}";

    public bool IsUsable =>
        PairKey is not null
        && Iq is double iq && double.IsFinite(iq)
        && ValidTasks is int tasks && tasks > 0
        && Passed is int passed && passed >= 0 && passed <= tasks
        && (AveragePriceUsd is not double cost || double.IsFinite(cost) && cost >= 0)
        && (AverageMinutes is not double duration || double.IsFinite(duration) && duration >= 0);
}

internal static class IntelligenceEfficiencyParser
{
    private const string DistributedSourceUrl = "https://deng.codexradar.com";

    public static IntelligenceEfficiencyEnvelope Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new JsonException("Intelligence Efficiency root must be an object.");
        IReadOnlyList<IntelligenceEfficiencyPoint> points = [];
        if (root.TryGetProperty("points", out var values)
            && values.ValueKind != JsonValueKind.Null)
        {
            if (values.ValueKind != JsonValueKind.Array)
                throw new JsonException(
                    "Intelligence Efficiency points must be an array.");
            points = values.EnumerateArray().Select(ParsePoint).ToArray();
        }
        return new IntelligenceEfficiencyEnvelope(
            StrictNullableInt(root, "schema"),
            StrictNullableString(root, "type"),
            StrictNullableString(root, "source_updated_at"),
            points);
    }

    public static PublicRadarData Merge(
        PublicRadarData current,
        IntelligenceEfficiencyEnvelope envelope)
    {
        var points = envelope.UsablePoints;
        if (points.Count == 0) return current;

        var currentPrimaryKey = PairKey(current.ModelName, current.ReasoningEffort)
                                ?? PairKeyFromLabel(current.ModelLabel);
        var primaryPoint = currentPrimaryKey is null
            ? null
            : points.FirstOrDefault(point => point.PairKey == currentPrimaryKey);
        if (primaryPoint is null && current.IqScore is null)
            primaryPoint = PreferredPrimary(points);

        var mergedComparisons = new List<ModelComparison>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var comparison in current.Comparisons)
        {
            var pair = PairKey(comparison.Model, comparison.Effort)
                       ?? PairKeyFromLabel(comparison.Label);
            var point = pair is null ? null : points.FirstOrDefault(candidate => candidate.PairKey == pair);
            if (point is not null && point.PairKey != primaryPoint?.PairKey)
            {
                mergedComparisons.Add(MergeComparison(comparison, point, envelope.SourceUpdatedAt));
                seen.Add(point.PairKey!);
            }
            else if (pair != primaryPoint?.PairKey)
            {
                mergedComparisons.Add(comparison);
                if (pair is not null) seen.Add(pair);
            }
        }

        foreach (var point in points)
        {
            if (point.PairKey == primaryPoint?.PairKey || point.PairKey is null || !seen.Add(point.PairKey))
                continue;
            mergedComparisons.Add(CreateComparison(point, envelope.SourceUpdatedAt));
        }

        mergedComparisons = mergedComparisons
            .OrderByDescending(comparison => ModelVersion(comparison.Model ?? comparison.Label))
            .ThenBy(comparison => ModelFamilyRank(comparison.Model ?? comparison.Label))
            .ThenBy(comparison => EffortRank(comparison.Effort ?? comparison.Label))
            .ThenBy(comparison => comparison.Label, StringComparer.Ordinal)
            .ToList();

        var allTasks = new List<int>();
        var hasPrimary = primaryPoint is not null
                         || current.IqScore is not null
                         || current.ValidTasks is not null;
        if ((primaryPoint?.ValidTasks ?? current.ValidTasks) is int primaryTasks)
            allTasks.Add(primaryTasks);
        allTasks.AddRange(mergedComparisons
            .Where(comparison => comparison.Tasks is > 0)
            .Select(comparison => comparison.Tasks!.Value));
        int? validCells = null;
        if (allTasks.Count == mergedComparisons.Count + (hasPrimary ? 1 : 0))
        {
            var total = 0;
            var overflow = false;
            foreach (var value in allTasks)
            {
                var next = (long)total + value;
                if (next > int.MaxValue)
                {
                    overflow = true;
                    break;
                }
                total = (int)next;
            }
            if (!overflow) validCells = total;
        }

        if (primaryPoint is null)
        {
            return current with
            {
                Comparisons = mergedComparisons,
                IqDataSourceUrl = current.IqDataSourceUrl ?? DistributedSourceUrl,
                IqValidCells = validCells ?? current.IqValidCells,
                IqSourceUpdatedAt = RadarJson.Date(envelope.SourceUpdatedAt) ?? current.IqSourceUpdatedAt
            };
        }

        var label = string.IsNullOrWhiteSpace(current.ModelLabel)
            ? ModelLabel(primaryPoint.Model, primaryPoint.Effort)
            : current.ModelLabel;
        return current with
        {
            IqDate = primaryPoint.LatestGradedAt ?? envelope.SourceUpdatedAt ?? current.IqDate,
            IqScore = primaryPoint.Iq ?? current.IqScore,
            IqStatus = QualityStatus(primaryPoint.Iq) ?? current.IqStatus,
            ModelLabel = label,
            ModelName = primaryPoint.Model ?? current.ModelName,
            ReasoningEffort = primaryPoint.Effort ?? current.ReasoningEffort,
            Passed = primaryPoint.Passed ?? current.Passed,
            ValidTasks = primaryPoint.ValidTasks ?? current.ValidTasks,
            AverageCostUsd = primaryPoint.AveragePriceUsd ?? current.AverageCostUsd,
            AverageTaskMinutes = primaryPoint.AverageMinutes ?? current.AverageTaskMinutes,
            CacheHitRate = CacheRate(primaryPoint.CacheHitRate) ?? current.CacheHitRate,
            Comparisons = mergedComparisons,
            IqDataSourceUrl = current.IqDataSourceUrl ?? DistributedSourceUrl,
            IqValidCells = validCells ?? current.IqValidCells,
            IqSourceUpdatedAt = RadarJson.Date(envelope.SourceUpdatedAt) ?? current.IqSourceUpdatedAt
        };
    }

    private static IntelligenceEfficiencyPoint ParsePoint(JsonElement item)
    {
        if (item.ValueKind != JsonValueKind.Object)
            throw new JsonException(
                "Intelligence Efficiency points must be objects.");
        return new IntelligenceEfficiencyPoint(
            StrictNullableString(item, "model"),
            StrictNullableString(item, "effort"),
            StrictNullableDouble(item, "iq"),
            StrictNullableInt(item, "passed"),
            StrictNullableInt(item, "valid_tasks"),
            StrictNullableDouble(item, "average_price_usd"),
            StrictNullableDouble(item, "average_minutes"),
            StrictNullableString(item, "latest_graded_at"),
            StrictNullableDouble(item, "cache_hit_rate"));
    }

    private static ModelComparison MergeComparison(
        ModelComparison existing,
        IntelligenceEfficiencyPoint point,
        string? sourceUpdatedAt) => existing with
        {
            Iq = point.Iq ?? existing.Iq,
            Status = QualityStatus(point.Iq) ?? existing.Status,
            Passed = point.Passed ?? existing.Passed,
            Tasks = point.ValidTasks ?? existing.Tasks,
            CacheHitRate = CacheRate(point.CacheHitRate) ?? existing.CacheHitRate,
            Model = point.Model ?? existing.Model,
            Effort = point.Effort ?? existing.Effort,
            AverageCostUsd = point.AveragePriceUsd ?? existing.AverageCostUsd,
            AverageMinutes = point.AverageMinutes ?? existing.AverageMinutes,
            LatestGradedAt = point.LatestGradedAt ?? sourceUpdatedAt ?? existing.LatestGradedAt
        };

    private static ModelComparison CreateComparison(
        IntelligenceEfficiencyPoint point,
        string? sourceUpdatedAt) => new(
        ModelLabel(point.Model, point.Effort),
        point.Iq,
        QualityStatus(point.Iq),
        point.Passed,
        point.ValidTasks,
        CacheHitRate: CacheRate(point.CacheHitRate),
        Model: point.Model,
        Effort: point.Effort,
        AverageCostUsd: point.AveragePriceUsd,
        AverageMinutes: point.AverageMinutes,
        LatestGradedAt: point.LatestGradedAt ?? sourceUpdatedAt);

    private static IntelligenceEfficiencyPoint PreferredPrimary(
        IReadOnlyList<IntelligenceEfficiencyPoint> points) =>
        points.FirstOrDefault(point => point.PairKey == "gpt-5.6-sol/max")
        ?? points.MaxBy(point => point.Iq ?? double.NegativeInfinity)!;

    private static string ModelLabel(string? model, string? effort)
    {
        var normalized = model?.Trim() ?? "";
        var parts = normalized.Split('-', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length >= 3 && parts[0].Equals("gpt", StringComparison.OrdinalIgnoreCase)
                              && new[] { "sol", "terra", "luna" }.Contains(parts[^1],
                                  StringComparer.OrdinalIgnoreCase))
        {
            normalized = string.Join("-", parts[..^1]).ToUpperInvariant()
                         + " " + CultureInfo.InvariantCulture.TextInfo.ToTitleCase(parts[^1].ToLowerInvariant());
        }
        else if (normalized.StartsWith("gpt-", StringComparison.OrdinalIgnoreCase))
        {
            normalized = normalized.ToUpperInvariant();
        }
        return string.Join(" ", new[] { normalized, effort?.Trim() }
            .Where(value => !string.IsNullOrWhiteSpace(value)));
    }

    private static string? PairKey(string? model, string? effort) =>
        string.IsNullOrWhiteSpace(model) || string.IsNullOrWhiteSpace(effort)
            ? null
            : $"{model.Trim().ToLowerInvariant()}/{effort.Trim().ToLowerInvariant()}";

    private static string? PairKeyFromLabel(string? label)
    {
        if (string.IsNullOrWhiteSpace(label)) return null;
        var match = Regex.Match(label.Trim(),
            @"^(?<model>gpt-[a-z0-9.\-]+)\s+(?<effort>ultra|max|xhigh|high|medium|low)$",
            RegexOptions.IgnoreCase);
        return match.Success ? PairKey(match.Groups["model"].Value, match.Groups["effort"].Value) : null;
    }

    private static int? StrictNullableInt(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return null;
        if (value.ValueKind == JsonValueKind.Null) return null;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
        throw new JsonException($"{name} must be an integer.");
    }

    private static double? StrictNullableDouble(
        JsonElement element,
        string name)
    {
        if (!element.TryGetProperty(name, out var value)
            || value.ValueKind == JsonValueKind.Null)
            return null;
        if (value.ValueKind == JsonValueKind.Number
            && value.TryGetDouble(out var number))
            return number;
        throw new JsonException($"{name} must be a number.");
    }

    private static string? StrictNullableString(
        JsonElement element,
        string name)
    {
        if (!element.TryGetProperty(name, out var value)
            || value.ValueKind == JsonValueKind.Null)
            return null;
        if (value.ValueKind == JsonValueKind.String)
            return value.GetString();
        throw new JsonException($"{name} must be a string.");
    }

    private static string? QualityStatus(double? value) => value switch
    {
        < 80 => "red",
        < 95 => "yellow",
        double => "green",
        _ => null
    };

    private static string? CacheRate(double? value) =>
        value is double number && double.IsFinite(number) ? $"{number:0.0}%" : null;

    private static double ModelVersion(string label)
    {
        var match = Regex.Match(label, @"(\d+(?:\.\d+)?)");
        return match.Success && double.TryParse(match.Value, NumberStyles.Float,
            CultureInfo.InvariantCulture, out var value) ? value : 0;
    }

    private static int ModelFamilyRank(string label)
    {
        var value = label.ToLowerInvariant();
        return value.Contains("sol") ? 0 : value.Contains("terra") ? 1 : value.Contains("luna") ? 2 : 9;
    }

    private static int EffortRank(string label)
    {
        var value = label.ToLowerInvariant();
        return value.Contains("ultra") ? 0 : value.Contains("max") ? 1 : value.Contains("xhigh") ? 2
            : value.Contains("high") ? 3 : value.Contains("medium") ? 4 : value.Contains("low") ? 5 : 9;
    }
}
