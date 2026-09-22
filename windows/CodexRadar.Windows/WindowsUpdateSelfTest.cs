using System.Text.Json;

namespace CodexRadar.Windows;

internal static class WindowsUpdateSelfTest
{
    public static void Run()
    {
        static void Check(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }

        using (var handler = RadarService.CreatePublicHttpHandler())
        {
            Check(!handler.UseCookies
                  && handler.AutomaticDecompression.HasFlag(System.Net.DecompressionMethods.GZip)
                  && handler.AutomaticDecompression.HasFlag(System.Net.DecompressionMethods.Deflate)
                  && handler.AutomaticDecompression.HasFlag(System.Net.DecompressionMethods.Brotli),
                "Public requests must support compressed feeds without enabling cookies.");
        }

        foreach (var (permission, spend, blocked, confirms) in new[]
        {
            ("", "false", false, true),
            ("\"ordinaryUsageAllowed\":true,", "false", false, true),
            ("\"ordinaryUsageAllowed\":false,", "false", true, false),
            ("\"ordinaryUsageAllowed\":null,", "false", false, false),
            ("\"ordinaryUsageAllowed\":true,", "true", true, false)
        })
        {
            using var document = JsonDocument.Parse("{" + permission + "\"rateLimits\":{"
                + "\"primary\":{\"usedPercent\":10,\"windowDurationMins\":300},"
                + "\"secondary\":{\"usedPercent\":20,\"windowDurationMins\":10080},"
                + "\"spendControlReached\":" + spend + "}}");
            var quota = AppServerClient.ParseRateLimits(document.RootElement);
            Check(quota.Blocked == blocked && quota.CanConfirmWeeklyRecovery == confirms,
                "Explicit usage permission and spend limits must override remaining percentages.");
        }

        var now = DateTimeOffset.UtcNow;
        var efficiency = IntelligenceEfficiencyParser.Parse("""
            {"schema":2,"points":[{"model":"gpt-6-astra","effort":"low","iq":97.35,
              "passed":98.0,"valid_tasks":151.0,"cache_hit_rate":0.943371}]}
            """);
        Check(efficiency.UsablePoints is [{ Passed: 98, ValidTasks: 151 }],
            "Integral JSON decimals preserve current distributed task counts.");
        var merged = IntelligenceEfficiencyParser.Merge(new PublicRadarData(), efficiency);
        Check(merged.IntelligenceEfficiencyPairKeys.Contains("gpt-6-astra/low")
              && merged.CacheHitRate?.StartsWith("94.3", StringComparison.Ordinal) == true,
            "Current source configurations and fractional cache rates remain complete.");
        try
        {
            _ = IntelligenceEfficiencyParser.Parse("""{"schema":2,"points":[{"passed":98.5}]}""");
            throw new InvalidOperationException("Fractional task counts must not be rounded.");
        }
        catch (JsonException) { }
        var settings = new AppSettings();
        var low = new DashboardSnapshot { WeeklyRemaining = 10, WeeklyResetsAt = now.AddDays(1) };
        var recovered = low with { WeeklyRemaining = 90, WeeklyResetsAt = now.AddDays(8) };
        _ = NotificationPolicy.Evaluate(null, low, settings, now);
        _ = NotificationPolicy.Evaluate(low, recovered, settings, now);
        Check(settings.NotificationMemory.PendingWeeklyRestoreKey is not null, "Recovery needs confirmation.");
        Check(!NotificationPolicy.Evaluate(recovered, recovered with { CanConfirmWeeklyRecovery = false }, settings, now)
                .Any(item => item.Identifier.StartsWith("weekly-restored-", StringComparison.Ordinal))
              && settings.NotificationMemory.PendingWeeklyRestoreKey is null,
            "Unknown permission must clear pending recovery without notifying.");

        var average = new RadarDegradationAlert("model", "high", 90, 20, null, Average24HourIq: 95);
        Check(average.IsValid && average.Preferred24HourDrop == 5 && average.Uses24HourAverage,
            "Average-based degradation takes precedence over legacy high-water marks.");
        Check((average with { From24HourAverageIq = 3 }).LargestDrop == 3,
            "Explicit average drops take precedence over computed differences.");
        Check(!(average with { Average24HourIq = double.NaN }).IsValid,
            "Non-finite averages must not appear as valid alerts.");

        var current = CodexRadarHtmlParser.Parse("""
            <section data-kind="notice" class="wide site-announcement current">
              <span class="site-announcement-label">Important</span>
              <strong class="site-announcement-headline">Headline</strong>
              <p class="site-announcement-lead">First paragraph.</p>
              <p class="site-announcement-lead">Second paragraph.</p>
              <a href="/notice" class="pro-subscription-announcement-link">Official source</a>
            </section>
            <section data-kind="speed" class="compact fast-radar">
              <h2>Fast Radar</h2>
              <div class="fast-simple-row"><strong>Model high <small>details</small></strong>
                <span>40</span><span>60</span><strong class="fast-simple-ratio">1.5×</strong></div>
            </section>
            <details class="fast-radar-explain"><summary>Method</summary><p>Three independent runs.</p></details>
            <section class="community-knowledge">
              <article class="community-knowledge-card"><h2>Guide</h2>
                <div class="community-knowledge-card-main"><img alt="Accessible guide description" src="/guide.png"></div>
                <a href="https://example.org/guide">Read guide</a></article>
            </section>
            """, now);
        Check(current.Announcement == "Headline\n\nFirst paragraph.\n\nSecond paragraph."
              && current.AnnouncementUrl == "https://codexradar.com/notice",
            "Current notices preserve every paragraph and resolve safe relative sources.");
        Check(current.FastRadar is { Summary.Count: 1, Rows.Count: 0 }
              && current.FastRadar.Summary[0].Label == "Model high · TPS"
              && current.FastRadar.Method == "Three independent runs.",
            "Current Fast Radar summaries and external methodology remain available without legacy rows.");
        Check(current.CommunityKnowledges.Single() is
            { Prompt: "Accessible guide description", SourceUrl: "https://example.org/guide" },
            "Image-only guides retain accessible text and their public source.");
        Check(PublicWebLink.Normalize("https://user:secret@example.org/") is null
              && PublicWebLink.Normalize("javascript:alert(1)") is null
              && PublicWebLink.Normalize("file:///C:/example") is null,
            "Public links must not open credentials, scripts, or local files.");

        var attempts = 0;
        var delays = 0;
        var result = RateLimitReadRecovery.ReadAsync<int>(_ => ++attempts == 1
                ? Task.FromException<int>(new TimeoutException()) : Task.FromResult(42),
            CancellationToken.None, (duration, _) =>
            {
                Check(duration == TimeSpan.FromSeconds(1), "Quota retry delay is bounded.");
                delays++;
                return Task.CompletedTask;
            }).GetAwaiter().GetResult();
        Check(result == 42 && attempts == 2 && delays == 1, "A transient read retries exactly once.");
        Check(!RateLimitReadRecovery.ShouldRetry(new AppServerRpcException(-32000, "authentication required"))
              && !RateLimitReadRecovery.ShouldRetry(new OperationCanceledException()),
            "Authentication and cancellation must not trigger read retries.");
        attempts = 0;
        try
        {
            _ = RateLimitReadRecovery.ReadAsync<int>(_ =>
                {
                    attempts++;
                    return Task.FromException<int>(new TimeoutException());
                }, CancellationToken.None, (_, _) => Task.CompletedTask).GetAwaiter().GetResult();
            throw new InvalidOperationException("A persistent read failure was swallowed.");
        }
        catch (TimeoutException) { Check(attempts == 2, "Persistent failures must not create a retry loop."); }
        Check(ResetCreditProtectionService.RevocationBlockReason(ResetCreditRevocationReason.UserDisabled) is null
              && ResetCreditProtectionService.RevocationBlockReason(ResetCreditRevocationReason.ClockChanged)
              == ResetCreditProtectionBlockReason.ClockChanged,
            "Persisted revocation reasons distinguish user choice from safety failures.");
    }
}
