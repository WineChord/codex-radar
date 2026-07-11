using System.Globalization;
using System.Net.Http.Headers;
using System.Text.Json;

namespace CodexRadar.Windows;

internal sealed class RadarService : IAsyncDisposable
{
    private readonly HttpClient _http = new()
    {
        BaseAddress = new Uri("https://codexradar.com/"),
        Timeout = TimeSpan.FromSeconds(15)
    };
    private readonly AppServerClient _appServer = new();

    public RadarService() => _http.DefaultRequestHeaders.UserAgent.ParseAdd($"CodexRadarSentinel-Windows/{AppUpdateService.CurrentVersion}");

    public Task<DashboardSnapshot> RefreshAsync(AppSettings settings, CancellationToken cancellationToken) =>
        RefreshAsync(settings, null, cancellationToken);

    public async Task<DashboardSnapshot> RefreshAsync(
        AppSettings settings, DashboardSnapshot? previous, CancellationToken cancellationToken)
    {
        // AppSettings belongs to the UI thread. Capture everything this refresh
        // needs before the first await so continuations never observe a partly
        // updated settings object while the user is editing preferences.
        var refreshSettings = settings.CreateRefreshSnapshot();
        var errors = new List<string>();
        var next = previous ?? new DashboardSnapshot();
        var publicTask = ReadPublicRadarAsync(cancellationToken);
        // Binary discovery and Process.Start have a synchronous prefix. Run it
        // away from the WinForms thread so a refresh can never delay first paint.
        var quotaTask = Task.Run(() => _appServer.ReadRateLimitsAsync(cancellationToken), cancellationToken);
        OperationCanceledException? cancellation = null;
        try { next = ApplyPublic(next, await publicTask.ConfigureAwait(false)); }
        catch (OperationCanceledException ex) when (cancellationToken.IsCancellationRequested) { cancellation = ex; }
        catch (Exception ex) { errors.Add($"CodexRadar: {Friendly(ex, refreshSettings.Chinese)}"); }
        try { next = ApplyQuota(next, await quotaTask.ConfigureAwait(false)); }
        catch (OperationCanceledException ex) when (cancellationToken.IsCancellationRequested) { cancellation ??= ex; }
        catch (Exception ex) { errors.Add($"Codex: {Friendly(ex, refreshSettings.Chinese)}"); }
        if (cancellation is not null) throw new OperationCanceledException(cancellation.Message, cancellation, cancellationToken);

        next = next with
        {
            RefreshedAt = DateTimeOffset.Now,
            ResetCredits = refreshSettings.CachedResetCredits,
            AvailableResetCredits = refreshSettings.CachedAvailableResetCredits,
            TotalEarnedResetCredits = refreshSettings.CachedTotalEarnedResetCredits,
            ResetCreditsCheckedAt = refreshSettings.LastResetCreditCheck,
            ResetCreditFailure = refreshSettings.LastResetCreditFailure,
            Errors = errors
        };
        return next with { QuotaPacing = QuotaPacingCalculator.Calculate(next, refreshSettings) };
    }

    private async Task<PublicRadarData> ReadPublicRadarAsync(CancellationToken cancellationToken)
    {
        var currentTask = _http.GetStringAsync("current.json", cancellationToken);
        var ratingsTask = ReadRatingsAsync(cancellationToken);
        var body = await currentTask.ConfigureAwait(false);
        PublicRadarData current;
        if (body.TrimStart().StartsWith('<'))
        {
            current = CodexRadarHtmlParser.Parse(body);
            if (current.IqScore is null) throw new InvalidDataException("CodexRadar homepage did not include readable Model IQ data.");
        }
        else
        {
            using var document = JsonDocument.Parse(body);
            current = ParseCurrent(document.RootElement);
            if (current.IqScore is null || current.ResetRadarCards.Count == 0
                || current.CommunityKnowledge is null || current.Announcement is null)
            {
                try
                {
                    var homepage = CodexRadarHtmlParser.Parse(
                        await _http.GetStringAsync("", cancellationToken).ConfigureAwait(false));
                    current = MergeHomepage(current, homepage);
                }
                catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
                catch { /* JSON remains authoritative when the optional homepage fallback fails. */ }
            }
        }
        var ratings = await ratingsTask.ConfigureAwait(false);
        return ApplyRatings(current, ratings);
    }

    private async Task<IReadOnlyList<ModelRatingInfo>> ReadRatingsAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var response = await _http.GetAsync("api/model-ratings", cancellationToken).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return [];
            using var document = JsonDocument.Parse(
                await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false));
            if (document.RootElement.Array("models") is not JsonElement models) return [];
            return models.EnumerateArray().Select(item => new ModelRatingInfo(
                item.String("id"), item.String("label"), item.String("group"),
                item.Number("average"), item.Int32("count"))).ToArray();
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch { return []; }
    }

    internal static PublicRadarData ParseCurrent(JsonElement root)
    {
        var modelIq = root.Object("model_iq");
        var latest = modelIq?.Object("latest");
        var comparisons = new List<ModelComparison>();
        if (modelIq?.Object("comparisons") is JsonElement comparisonMap)
        {
            comparisons.AddRange(comparisonMap.EnumerateObject().Select(property =>
            {
                var item = property.Value;
                var snapshot = item.Object("latest");
                return snapshot is null ? null : ParseModel(snapshot.Value,
                    item.String("label") ?? ModelName(snapshot.Value) ?? property.Name);
            }).Where(item => item is not null)!);
        }
        comparisons = comparisons.OrderByDescending(item => ModelVersion(item!.Label))
            .ThenBy(item => EffortRank(item!.Label)).Cast<ModelComparison>().ToList();

        var quotaRows = new List<QuotaEstimate>();
        var quotaRadar = modelIq?.Object("quota_radar") ?? root.Object("quota_radar");
        if (quotaRadar?.Array("rows") is JsonElement rows)
            quotaRows.AddRange(rows.EnumerateArray().Select(row => new QuotaEstimate(row.String("tier") ?? "--",
                row.Number("five_h"), row.Number("seven_d"), row.String("basis"))));
        double? trendDelta = null;
        if (quotaRadar?.Array("trend") is JsonElement trend && trend.GetArrayLength() >= 2)
        {
            var previous = trend[trend.GetArrayLength() - 2].Number("seven_d_20x");
            var current = trend[trend.GetArrayLength() - 1].Number("seven_d_20x");
            if (previous is double before && current is double after) trendDelta = after - before;
        }

        var announcement = root.Object("site_announcement");
        var reset = root.Object("reset_judgement");
        var community = root.Object("community_knowledge");
        var window = root.Object("window");
        var recent = root.Array("recent_windows");
        JsonElement? lastWindow = root.Object("last_window");
        var selectedWindowPayload = false;
        var windowOpen = root.Bool("window_open") ?? window?.Bool("open") ?? false;
        if (lastWindow is null && windowOpen && window is not null)
        {
            lastWindow = window;
            selectedWindowPayload = true;
        }
        if (lastWindow is null && recent is { } recentWindows && recentWindows.GetArrayLength() > 0) lastWindow = recentWindows[0];
        if (lastWindow is null && window is not null)
        {
            lastWindow = window;
            selectedWindowPayload = true;
        }
        var windowStatus = lastWindow?.String("status");
        var windowHuman = lastWindow?.String("window_human", "message");
        if (selectedWindowPayload)
        {
            var payloadOpen = window?.Bool("open");
            if (payloadOpen == true && windowStatus == "none") windowStatus = "open";
            else if (payloadOpen != true && window?.String("closed_at") is not null) windowStatus = "closed";
            windowHuman = payloadOpen == true ? window?.String("message") : "无窗";
        }
        var action = root.String("recommended_action") ?? window?.String("action");
        var prediction = root.Object("prediction");
        var resetCards = reset?.Array("cards") is JsonElement cards
            ? cards.EnumerateArray().Select(card => new ResetJudgementCard(card.String("label"), card.String("level"), card.String("summary"))).ToArray()
            : [];
        var resetReasons = reset?.Array("reasons") is JsonElement reasons
            ? reasons.EnumerateArray().Select(reason => reason.GetString()).Where(reason => !string.IsNullOrWhiteSpace(reason)).Cast<string>().ToArray()
            : [];

        return new PublicRadarData
        {
            SchemaVersion = root.String("schema_version"),
            CheckedAt = RadarJson.Date(root.String("checked_at", "monitored_at")),
            RadarStatus = root.String("status"), RecommendedAction = action,
            IqDate = latest?.String("date"), IqScore = latest?.Number("iq_score", "score"), IqStatus = latest?.String("status"),
            ModelLabel = latest is null ? null : ModelName(latest.Value), Passed = latest?.Int32("passed"),
            ValidTasks = latest?.Int32("valid_tasks", "tasks"), WallTime = latest?.String("wall_time_human") ?? Minutes(latest?.Int32("wall_seconds")),
            CostUsd = latest?.Number("cost_usd"), CacheHitRate = CacheRate(latest), Comparisons = comparisons,
            WindowOpen = windowOpen, WindowId = lastWindow?.String("id"), WindowStatus = windowStatus,
            WindowTitle = lastWindow?.String("title"), WindowSummary = lastWindow?.String("summary", "message"),
            WindowHuman = windowHuman, WindowScope = lastWindow?.String("scope"),
            WindowOpenedAt = RadarJson.Date(lastWindow?.String("opened_at")), WindowClosedAt = RadarJson.Date(lastWindow?.String("closed_at")),
            WindowSourceUrl = lastWindow?.String("source_url") ?? window?.String("source_url"),
            Prediction = prediction is null ? null : ParsePrediction(prediction.Value),
            AnnouncementLabel = announcement?.String("label"), Announcement = announcement?.String("message"),
            AnnouncementUpdatedLabel = announcement?.String("updated_label"), AnnouncementSourceLabel = announcement?.String("source_label"),
            AnnouncementUrl = announcement?.String("source_url"),
            ResetRadarTitle = reset?.String("title"), ResetRadarUpdatedLabel = reset?.String("updated_label"),
            ResetRadarCards = resetCards, ResetRadarReasons = resetReasons, ResetRadar = ResetText(reset?.String("title"), resetCards, resetReasons),
            CommunityKnowledge = community?.String("title"), CommunityPrompt = community?.String("prompt"),
            QuotaRadar = quotaRows, QuotaRadarDate = quotaRadar?.String("date"),
            QuotaRadarUpdatedAt = RadarJson.Date(quotaRadar?.String("updated_at")), QuotaRadarBasisWindowLabel = quotaRadar?.String("basis_window_label"),
            QuotaRadarCostUsd = quotaRadar?.Number("cost_usd"), QuotaRadarTotalTokens = quotaRadar?.Int64("total_tokens"),
            QuotaRadarSevenDayTrendDelta = trendDelta
        };
    }

    private static PublicRadarData MergeHomepage(PublicRadarData current, PublicRadarData homepage) => current with
    {
        IqDate = current.IqDate ?? homepage.IqDate, IqScore = current.IqScore ?? homepage.IqScore,
        IqStatus = current.IqStatus ?? homepage.IqStatus, ModelLabel = current.ModelLabel ?? homepage.ModelLabel,
        Passed = current.Passed ?? homepage.Passed, ValidTasks = current.ValidTasks ?? homepage.ValidTasks,
        WallTime = current.WallTime ?? homepage.WallTime, CostUsd = current.CostUsd ?? homepage.CostUsd,
        CacheHitRate = current.CacheHitRate ?? homepage.CacheHitRate,
        Comparisons = current.Comparisons.Count > 0 ? current.Comparisons : homepage.Comparisons,
        ResetRadarTitle = current.ResetRadarTitle ?? homepage.ResetRadarTitle,
        ResetRadarUpdatedLabel = current.ResetRadarUpdatedLabel ?? homepage.ResetRadarUpdatedLabel,
        ResetRadarCards = current.ResetRadarCards.Count > 0 ? current.ResetRadarCards : homepage.ResetRadarCards,
        ResetRadarReasons = current.ResetRadarReasons.Count > 0 ? current.ResetRadarReasons : homepage.ResetRadarReasons,
        ResetRadar = current.ResetRadar ?? homepage.ResetRadar,
        CommunityKnowledge = current.CommunityKnowledge ?? homepage.CommunityKnowledge,
        CommunityPrompt = current.CommunityPrompt ?? homepage.CommunityPrompt,
        AnnouncementLabel = current.AnnouncementLabel ?? homepage.AnnouncementLabel,
        Announcement = current.Announcement ?? homepage.Announcement,
        AnnouncementUpdatedLabel = current.AnnouncementUpdatedLabel ?? homepage.AnnouncementUpdatedLabel,
        AnnouncementSourceLabel = current.AnnouncementSourceLabel ?? homepage.AnnouncementSourceLabel,
        AnnouncementUrl = current.AnnouncementUrl ?? homepage.AnnouncementUrl
    };

    private static PublicRadarData ApplyRatings(PublicRadarData data, IReadOnlyList<ModelRatingInfo> ratings)
    {
        var updated = data.Comparisons.Select(model =>
        {
            var rating = MatchRating(ratings, model.Label);
            return model with { Rating = rating?.Average, RatingCount = rating?.Count };
        }).ToArray();
        var primaryRating = MatchRating(ratings, data.ModelLabel);
        return data with { Comparisons = updated, CommunityRating = primaryRating?.Average, CommunityRatingCount = primaryRating?.Count };
    }

    private static ModelRatingInfo? MatchRating(IEnumerable<ModelRatingInfo> ratings, string? label)
    {
        if (string.IsNullOrWhiteSpace(label)) return ratings.FirstOrDefault();
        var normalized = NormalizeModel(label);
        return ratings.FirstOrDefault(rating => NormalizeModel(rating.Id) == normalized || NormalizeModel(rating.Label) == normalized)
               ?? ratings.FirstOrDefault(rating => !string.IsNullOrWhiteSpace(rating.Group) && normalized.StartsWith(NormalizeModel(rating.Group)));
    }

    private static DashboardSnapshot ApplyPublic(DashboardSnapshot state, PublicRadarData data) => state with
    {
        SchemaVersion = data.SchemaVersion, CheckedAt = data.CheckedAt, RadarStatus = data.RadarStatus,
        RecommendedAction = data.RecommendedAction, IqDate = data.IqDate, IqScore = data.IqScore, IqStatus = data.IqStatus,
        ModelLabel = data.ModelLabel, Passed = data.Passed, ValidTasks = data.ValidTasks, WallTime = data.WallTime,
        CostUsd = data.CostUsd, CacheHitRate = data.CacheHitRate, CommunityRating = data.CommunityRating,
        CommunityRatingCount = data.CommunityRatingCount, Comparisons = data.Comparisons,
        WindowOpen = data.WindowOpen, WindowId = data.WindowId, WindowStatus = data.WindowStatus, WindowTitle = data.WindowTitle,
        WindowSummary = data.WindowSummary, WindowHuman = data.WindowHuman, WindowScope = data.WindowScope,
        WindowOpenedAt = data.WindowOpenedAt, WindowClosedAt = data.WindowClosedAt, WindowSourceUrl = data.WindowSourceUrl,
        Prediction = data.Prediction, AnnouncementLabel = data.AnnouncementLabel, Announcement = data.Announcement,
        AnnouncementUpdatedLabel = data.AnnouncementUpdatedLabel, AnnouncementSourceLabel = data.AnnouncementSourceLabel,
        AnnouncementUrl = data.AnnouncementUrl, ResetRadarTitle = data.ResetRadarTitle,
        ResetRadarUpdatedLabel = data.ResetRadarUpdatedLabel, ResetRadarCards = data.ResetRadarCards,
        ResetRadarReasons = data.ResetRadarReasons, ResetRadar = data.ResetRadar,
        CommunityKnowledge = data.CommunityKnowledge, CommunityPrompt = data.CommunityPrompt,
        QuotaRadar = data.QuotaRadar, QuotaRadarDate = data.QuotaRadarDate, QuotaRadarUpdatedAt = data.QuotaRadarUpdatedAt,
        QuotaRadarBasisWindowLabel = data.QuotaRadarBasisWindowLabel, QuotaRadarCostUsd = data.QuotaRadarCostUsd,
        QuotaRadarTotalTokens = data.QuotaRadarTotalTokens, QuotaRadarSevenDayTrendDelta = data.QuotaRadarSevenDayTrendDelta
    };

    private static DashboardSnapshot ApplyQuota(DashboardSnapshot state, LocalQuotaResult quota) => state with
    {
        WeeklyRemaining = quota.Weekly, ShortRemaining = quota.Short,
        WeeklyUsedPercent = quota.WeeklyUsed, ShortUsedPercent = quota.ShortUsed,
        WeeklyWindowMinutes = quota.WeeklyDurationMinutes, ShortWindowMinutes = quota.ShortDurationMinutes,
        WeeklyResetsAt = quota.WeeklyReset, ShortResetsAt = quota.ShortReset,
        LimitReached = quota.Blocked, PlanType = quota.PlanType, CreditsBalance = quota.CreditsBalance
    };

    public async Task<ResetCreditFetchResult> RefreshResetCreditsAsync(CancellationToken cancellationToken)
    {
        var path = Environment.GetEnvironmentVariable("CODEX_RADAR_CODEX_AUTH_PATH")
                   ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "auth.json");
        if (!File.Exists(path)) throw new ResetCreditException("authFileMissing", "未找到 ~/.codex/auth.json，请先登录 Codex。");
        JsonDocument auth;
        try { auth = JsonDocument.Parse(await File.ReadAllTextAsync(path, cancellationToken).ConfigureAwait(false)); }
        catch (JsonException ex) { throw new ResetCreditException("invalidAuthFile", "Codex 登录文件不是可读取的 JSON。", ex); }
        using (auth)
        {
            var token = auth.RootElement.String("access_token", "accessToken")
                        ?? auth.RootElement.Object("tokens")?.String("access_token", "accessToken");
            if (string.IsNullOrWhiteSpace(token)) throw new ResetCreditException("accessTokenMissing", "Codex 登录文件中没有 access token，请重新登录。");
            using var request = new HttpRequestMessage(HttpMethod.Get,
                "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits");
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            request.Headers.UserAgent.ParseAdd($"CodexRadarSentinel-Windows/{AppUpdateService.CurrentVersion}");
            using var response = await _http.SendAsync(request, cancellationToken).ConfigureAwait(false);
            if (response.StatusCode is System.Net.HttpStatusCode.Unauthorized or System.Net.HttpStatusCode.Forbidden)
                throw new ResetCreditException("unauthorized", $"Codex 凭证无效（HTTP {(int)response.StatusCode}），请重新登录。");
            if (!response.IsSuccessStatusCode) throw new ResetCreditException("service", $"Reset credit 服务返回 HTTP {(int)response.StatusCode}。");
            var body = await response.Content.ReadAsStringAsync(cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(body)) throw new ResetCreditException("responseChanged", "Reset credit 服务返回了空响应。");
            try
            {
                using var result = JsonDocument.Parse(body);
                if (result.RootElement.Array("credits") is not JsonElement items)
                    throw new ResetCreditException("responseChanged", "Reset credit 接口格式已变化。");
                var credits = items.EnumerateArray().Select(item =>
                {
                    var id = item.String("id");
                    return new ResetCredit(item.String("title") ?? item.String("reset_type") ?? "Full reset (Weekly + 5h)",
                        item.String("status") ?? "unknown", RadarJson.Date(item.String("granted_at")),
                        RadarJson.Date(item.String("expires_at")), id is { Length: > 6 } ? id[^6..] : id,
                        item.String("reset_type"), RadarJson.Date(item.String("redeem_started_at")), RadarJson.Date(item.String("redeemed_at")));
                }).OrderByDescending(credit => credit.IsAvailable).ThenBy(credit => credit.ExpiresAt ?? DateTimeOffset.MaxValue).ToArray();
                return new ResetCreditFetchResult(credits, result.RootElement.Int32("available_count") ?? credits.Count(credit => credit.IsAvailable),
                    result.RootElement.Int32("total_earned_count"), DateTimeOffset.Now);
            }
            catch (ResetCreditException) { throw; }
            catch (JsonException ex) { throw new ResetCreditException("responseChanged", "Reset credit 接口格式已变化。", ex); }
        }
    }

    private static PredictionInfo ParsePrediction(JsonElement value) => new(value.String("level"),
        value.Number("probability_24h"), value.Number("probability_48h"), value.Bool("should_notify"),
        value.String("expected_window"), value.String("reasoning_summary", "summary"), RadarJson.Date(value.String("updated_at")));
    private static ModelComparison ParseModel(JsonElement value, string label) => new(label,
        value.Number("iq_score", "score"), value.String("status"), value.Int32("passed"), value.Int32("valid_tasks", "tasks"),
        null, null, value.String("wall_time_human") ?? Minutes(value.Int32("wall_seconds")), value.Number("cost_usd"), CacheRate(value));
    private static string? ModelName(JsonElement value)
    {
        var model = value.String("model"); var effort = value.String("reasoning_effort");
        return string.Join(" ", new[] { model, effort }.Where(x => !string.IsNullOrWhiteSpace(x))) is { Length: > 0 } name ? name : null;
    }
    private static string? CacheRate(JsonElement? value)
    {
        var cached = value?.Number("cached_input_tokens"); var input = value?.Number("input_tokens");
        return cached is double c && input is double i && i > 0 ? $"{c / i * 100:0.0}%" : null;
    }
    private static string? Minutes(int? seconds) => seconds is int value
        ? $"{Math.Max(1, (int)Math.Round(value / 60d, MidpointRounding.AwayFromZero))} min"
        : null;
    private static string? ResetText(string? title, IEnumerable<ResetJudgementCard> cards, IEnumerable<string> reasons)
    {
        var lines = cards.Select(card => string.Join(" · ", new[] { card.Label, card.Level, card.Summary }.Where(x => !string.IsNullOrWhiteSpace(x))))
            .Concat(reasons).Where(line => line.Length > 0).ToArray();
        return lines.Length > 0 ? string.Join(Environment.NewLine, lines) : title;
    }
    private static double ModelVersion(string label)
    {
        var match = System.Text.RegularExpressions.Regex.Match(label, @"(\d+(?:\.\d+)?)");
        return match.Success && double.TryParse(match.Value, CultureInfo.InvariantCulture, out var value) ? value : 0;
    }
    private static int EffortRank(string label)
    {
        var value = label.ToLowerInvariant();
        return value.Contains("ultra") ? 0 : value.Contains("max") ? 1 : value.Contains("xhigh") ? 2
            : value.Contains("high") ? 3 : value.Contains("medium") ? 4 : value.Contains("low") ? 5 : 9;
    }
    private static string NormalizeModel(string? value) => System.Text.RegularExpressions.Regex.Replace(value?.ToLowerInvariant() ?? "", "[^a-z0-9]+", "-").Trim('-');
    private static string Friendly(Exception ex, bool chinese) => ex switch
    {
        TaskCanceledException => chinese ? "请求超时" : "request timed out",
        TimeoutException => chinese ? "请求超时" : "request timed out",
        OperationCanceledException => chinese ? "请求已取消" : "request cancelled",
        HttpRequestException => chinese ? "网络请求失败" : "network request failed",
        JsonException => chinese ? "数据格式已变化" : "response format changed",
        _ => ex.Message
    };
    public void Abort()
    {
        try { _http.CancelPendingRequests(); } catch { }
        _appServer.Abort();
    }

    public async ValueTask DisposeAsync()
    {
        try { await _appServer.DisposeAsync().ConfigureAwait(false); }
        finally { _http.Dispose(); }
    }
}

internal sealed record PublicRadarData
{
    public string? SchemaVersion { get; init; }
    public DateTimeOffset? CheckedAt { get; init; }
    public string? RadarStatus { get; init; }
    public string? RecommendedAction { get; init; }
    public string? IqDate { get; init; }
    public double? IqScore { get; init; }
    public string? IqStatus { get; init; }
    public string? ModelLabel { get; init; }
    public int? Passed { get; init; }
    public int? ValidTasks { get; init; }
    public string? WallTime { get; init; }
    public double? CostUsd { get; init; }
    public string? CacheHitRate { get; init; }
    public double? CommunityRating { get; init; }
    public int? CommunityRatingCount { get; init; }
    public bool WindowOpen { get; init; }
    public string? WindowId { get; init; }
    public string? WindowStatus { get; init; }
    public string? WindowTitle { get; init; }
    public string? WindowSummary { get; init; }
    public string? WindowHuman { get; init; }
    public string? WindowScope { get; init; }
    public DateTimeOffset? WindowOpenedAt { get; init; }
    public DateTimeOffset? WindowClosedAt { get; init; }
    public string? WindowSourceUrl { get; init; }
    public PredictionInfo? Prediction { get; init; }
    public string? AnnouncementLabel { get; init; }
    public string? Announcement { get; init; }
    public string? AnnouncementUpdatedLabel { get; init; }
    public string? AnnouncementSourceLabel { get; init; }
    public string? AnnouncementUrl { get; init; }
    public string? ResetRadarTitle { get; init; }
    public string? ResetRadarUpdatedLabel { get; init; }
    public IReadOnlyList<ResetJudgementCard> ResetRadarCards { get; init; } = [];
    public IReadOnlyList<string> ResetRadarReasons { get; init; } = [];
    public string? ResetRadar { get; init; }
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
}

internal sealed record ModelRatingInfo(string? Id, string? Label, string? Group, double? Average, int? Count);
internal sealed record ResetCreditFetchResult(IReadOnlyList<ResetCredit> Credits, int? Available, int? TotalEarned, DateTimeOffset CheckedAt);
internal sealed class ResetCreditException(string kind, string message, Exception? inner = null) : Exception(message, inner)
{
    public string Kind { get; } = kind;
}

internal static class RadarJson
{
    public static int RemainingPercent(double used) =>
        (int)Math.Round(Math.Clamp(100 - used, 0, 100), MidpointRounding.AwayFromZero);
    public static string QualityLabel(double? iq, string? status, bool chinese)
    {
        if (iq is null) return "--";
        if (status?.Equals("red", StringComparison.OrdinalIgnoreCase) == true || iq < 80) return chinese ? "低" : "low";
        if (status?.Equals("yellow", StringComparison.OrdinalIgnoreCase) == true || iq < 95) return chinese ? "中" : "med";
        return chinese ? "正常" : "ok";
    }
    public static DateTimeOffset? Date(string? value) => DateTimeOffset.TryParse(value, out var date) ? date.ToLocalTime() : null;
    public static JsonElement? Object(this JsonElement value, params string[] names) => Find(value, JsonValueKind.Object, names);
    public static JsonElement? Array(this JsonElement value, params string[] names) => Find(value, JsonValueKind.Array, names);
    public static string? String(this JsonElement value, params string[] names)
    {
        var item = Find(value, null, names); return item?.ValueKind == JsonValueKind.String ? item.Value.GetString() : null;
    }
    public static double? Number(this JsonElement value, params string[] names)
    {
        var item = Find(value, null, names);
        if (item?.ValueKind == JsonValueKind.Number && item.Value.TryGetDouble(out var number)) return number;
        return item?.ValueKind == JsonValueKind.String && double.TryParse(item.Value.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out number) ? number : null;
    }
    public static int? Int32(this JsonElement value, params string[] names) => Number(value, names) is double number ? (int)number : null;
    public static long? Int64(this JsonElement value, params string[] names) => Number(value, names) is double number ? (long)number : null;
    public static bool? Bool(this JsonElement value, params string[] names)
    {
        var item = Find(value, null, names); return item?.ValueKind switch { JsonValueKind.True => true, JsonValueKind.False => false, _ => null };
    }
    private static JsonElement? Find(JsonElement value, JsonValueKind? kind, IEnumerable<string> names)
    {
        if (value.ValueKind != JsonValueKind.Object) return null;
        foreach (var name in names) if (value.TryGetProperty(name, out var item) && (kind is null || item.ValueKind == kind)) return item;
        return null;
    }
}
