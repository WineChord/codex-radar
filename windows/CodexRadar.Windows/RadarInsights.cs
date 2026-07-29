using System.Globalization;
using System.Text.Json;

namespace CodexRadar.Windows;

internal sealed record RadarInsightsEnvelope(
    string? GeneratedAt,
    string? SourceUpdatedAt,
    IReadOnlyList<RadarRecommendationGroup> Recommendations,
    RadarDegradationCollection DegradationAlerts)
{
    public DateTimeOffset? EffectiveTimestamp =>
        RadarJson.Date(SourceUpdatedAt ?? GeneratedAt);
}

internal sealed record RadarRecommendationGroup(
    string? Key,
    string? Title,
    string? Rule,
    IReadOnlyList<RadarRecommendationItem> Items)
{
    public IReadOnlyList<RadarRecommendationItem> ValidItems =>
        Items.Where(item => item.IsValid).ToArray();
}

internal sealed record RadarRecommendationItem(
    string? Model,
    string? Effort,
    double? Iq,
    double? AverageCostUsd,
    double? AverageDurationMinutes)
{
    public bool IsValid =>
        !string.IsNullOrWhiteSpace(Model)
        && !string.IsNullOrWhiteSpace(Effort)
        && Iq is double iq && double.IsFinite(iq) && iq >= 0
        && (AverageCostUsd is not double cost || double.IsFinite(cost) && cost >= 0)
        && (AverageDurationMinutes is not double duration || double.IsFinite(duration) && duration >= 0);
}

internal sealed record RadarDegradationCollection(
    string? Rule,
    IReadOnlyList<RadarDegradationAlert> Items)
{
    public IReadOnlyList<RadarDegradationAlert> ValidItems =>
        Items.Where(item => item.IsValid).ToArray();
}

internal sealed record RadarDegradationAlert(
    string? Model,
    string? Effort,
    double? Iq,
    double? From24HourHighIq,
    double? From48HourHighIq)
{
    public double LargestDrop => new[] { From24HourHighIq, From48HourHighIq }
        .Where(value => value is double number && double.IsFinite(number))
        .Select(value => value!.Value)
        .DefaultIfEmpty(0)
        .Max();

    public bool IsValid
    {
        get
        {
            var drops = new[] { From24HourHighIq, From48HourHighIq }
                .Where(value => value is not null)
                .Select(value => value!.Value)
                .ToArray();
            return !string.IsNullOrWhiteSpace(Model)
                   && !string.IsNullOrWhiteSpace(Effort)
                   && Iq is double iq && double.IsFinite(iq) && iq >= 0
                   && drops.All(drop => double.IsFinite(drop) && drop >= 0)
                   && LargestDrop > 0;
        }
    }
}

internal static class RadarInsightsParser
{
    private sealed record ParsedBody(
        int? Schema,
        string? GeneratedAt,
        string? SourceUpdatedAt,
        IReadOnlyList<RadarRecommendationGroup> Recommendations,
        RadarDegradationCollection DegradationAlerts);

    public static RadarInsightsEnvelope Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object)
            throw new JsonException("Radar insights root must be an object.");

        // Match the macOS decoder: validate the outer body even when a `data`
        // wrapper is present, and reject a declared wrapper of the wrong type.
        var outer = ParseBody(root);
        ParsedBody? wrapped = null;
        if (root.TryGetProperty("data", out var data))
        {
            if (data.ValueKind == JsonValueKind.Object)
                wrapped = ParseBody(data);
            else if (data.ValueKind != JsonValueKind.Null)
                throw new JsonException("Radar insights data must be an object.");
        }
        var schemas = new[] { outer.Schema, wrapped?.Schema }
            .Where(schema => schema is not null)
            .Select(schema => schema!.Value)
            .ToArray();
        if (schemas.Length == 0 || schemas.Any(schema => schema != 1))
            throw new JsonException("Unsupported radar insights schema.");

        var body = wrapped ?? outer;
        return new RadarInsightsEnvelope(
            body.GeneratedAt ?? outer.GeneratedAt,
            body.SourceUpdatedAt ?? outer.SourceUpdatedAt,
            body.Recommendations,
            body.DegradationAlerts);
    }

    public static bool ShouldAccept(RadarInsightsEnvelope? previous, RadarInsightsEnvelope candidate)
    {
        if (previous is null) return true;
        var candidateDate = candidate.EffectiveTimestamp;
        var previousDate = previous.EffectiveTimestamp;
        return (candidateDate, previousDate) switch
        {
            (DateTimeOffset next, DateTimeOffset current) => next >= current,
            (null, not null) => false,
            _ => true
        };
    }

    private static RadarRecommendationGroup ParseRecommendationGroup(JsonElement item)
    {
        if (item.ValueKind != JsonValueKind.Object)
            throw new JsonException(
                "Radar recommendation groups must be objects.");
        var values = Array(item, "items", "models", "recommendations")
            .Select(ParseRecommendationItem)
            .ToArray();
        return new RadarRecommendationGroup(
            Text(item, "key", "id"),
            Text(item, "title"),
            Text(item, "rule", "description"),
            values);
    }

    private static RadarDegradationCollection ParseDegradationCollection(JsonElement? value)
    {
        if (value is null)
            return new RadarDegradationCollection(null, []);
        var element = value.Value;
        IEnumerable<JsonElement> items;
        string? rule = null;
        if (element.ValueKind == JsonValueKind.Array)
        {
            items = element.EnumerateArray();
        }
        else if (element.ValueKind == JsonValueKind.Object)
        {
            rule = Text(element, "rule");
            items = Array(element, "items", "alerts");
        }
        else
        {
            throw new JsonException(
                "Radar degradation alerts must be an array or object.");
        }

        return new RadarDegradationCollection(
            rule,
            items.Select(ParseDegradationAlert)
            .ToArray());
    }

    private static RadarRecommendationItem ParseRecommendationItem(
        JsonElement item)
    {
        if (item.ValueKind != JsonValueKind.Object)
            throw new JsonException(
                "Radar recommendation items must be objects.");
        return new RadarRecommendationItem(
            Text(item, "model"),
            Text(item, "effort"),
            Number(item, "iq", "current_iq"),
            Number(
                item,
                "average_cost_usd",
                "average_price_usd",
                "price_usd",
                "price"),
            Number(
                item,
                "average_duration_minutes",
                "average_minutes",
                "minutes"));
    }

    private static RadarDegradationAlert ParseDegradationAlert(
        JsonElement item)
    {
        if (item.ValueKind != JsonValueKind.Object)
            throw new JsonException(
                "Radar degradation alerts must be objects.");
        return new RadarDegradationAlert(
            Text(item, "model"),
            Text(item, "effort"),
            Number(item, "iq", "current_iq"),
            Number(
                item,
                "from_24h_high_iq",
                "degradation_24h_iq",
                "drop_24h",
                "drop24h"),
            Number(
                item,
                "from_48h_high_iq",
                "degradation_48h_iq",
                "drop_48h",
                "drop48h"));
    }

    private static ParsedBody ParseBody(JsonElement element)
    {
        return new ParsedBody(
            DeclaredSchema(element),
            Text(element, "generated_at"),
            Timestamp(element, "source_updated_at"),
            Array(
                    element,
                    "recommendations",
                    "station_recommendations",
                    "station_recs")
                .Select(ParseRecommendationGroup)
                .ToArray(),
            ParseDegradationCollection(
                First(
                    element,
                    "degradation_alerts",
                    "alerts",
                    "degradation")));
    }

    private static int? DeclaredSchema(JsonElement element)
    {
        if (!element.TryGetProperty("schema", out var schema)) return null;
        if (schema.ValueKind == JsonValueKind.Number && schema.TryGetInt32(out var number))
            return number;
        if (schema.ValueKind == JsonValueKind.String
            && int.TryParse(schema.GetString()?.Trim(), NumberStyles.Integer,
                CultureInfo.InvariantCulture, out number))
            return number;
        throw new JsonException("Radar insights schema must be an integer.");
    }

    private static string? Timestamp(JsonElement element, params string[] names)
    {
        var value = First(element, names);
        if (value is null) return null;
        if (value.Value.ValueKind == JsonValueKind.String)
        {
            var text = value.Value.GetString()?.Trim();
            return RadarJson.Date(text) is null ? null : text;
        }
        if (value.Value.ValueKind != JsonValueKind.Object) return null;
        return value.Value.EnumerateObject()
            .Select(property => property.Value.ValueKind == JsonValueKind.String
                ? property.Value.GetString()?.Trim()
                : null)
            .Where(candidate => RadarJson.Date(candidate) is not null)
            .OrderByDescending(candidate => RadarJson.Date(candidate))
            .FirstOrDefault();
    }

    private static string? Text(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value)
                || value.ValueKind != JsonValueKind.String)
                continue;
            var text = value.GetString()?.Trim();
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        return null;
    }

    private static double? Number(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value))
                continue;
            if (value.ValueKind == JsonValueKind.Number
                && value.TryGetDouble(out var number))
                return number;
            if (value.ValueKind == JsonValueKind.String
                && double.TryParse(
                    value.GetString()?.Trim(),
                    NumberStyles.Float,
                    CultureInfo.InvariantCulture,
                    out number))
                return number;
        }
        return null;
    }

    private static IEnumerable<JsonElement> Array(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object) return [];
        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out var value))
                continue;
            if (value.ValueKind == JsonValueKind.Null) return [];
            if (value.ValueKind == JsonValueKind.Array)
                return value.EnumerateArray();
            throw new JsonException(
                $"{name} must be an array.");
        }
        return [];
    }

    private static JsonElement? First(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names)
            if (element.TryGetProperty(name, out var value))
                return value;
        return null;
    }
}
