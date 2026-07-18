using System.Text.Json;

namespace CodexRadar.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            SelfTest.Run();
            return;
        }

        using var mutex = new Mutex(true, @"Local\CodexRadarSentinel.Windows", out var firstInstance);
        if (!firstInstance)
        {
            MessageBox.Show("Codex Radar Sentinel 已经在系统托盘中运行。", "Codex Radar Sentinel",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            return;
        }

        ApplicationConfiguration.Initialize();
        using var context = new TrayApplicationContext();
        Application.Run(context);
    }
}

internal static class SelfTest
{
    public static void Run()
    {
        static void Assert(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }
        static void AssertThrows<T>(Action action, string message) where T : Exception
        {
            try { action(); }
            catch (T) { return; }
            throw new InvalidOperationException(message);
        }

        Assert(RadarJson.RemainingPercent(34.6) == 65, "remaining percentage rounding");
        Assert(RadarJson.RemainingPercent(35.5) == 65, "midpoint percentage rounds like Swift");
        Assert(RadarJson.RemainingPercent(69.5) == 31, "quota midpoint does not cross warning threshold");
        Assert(RadarJson.RemainingPercent(130) == 0, "remaining percentage clamp");
        Assert(RadarJson.QualityLabel(112, "green", true) == "正常", "Chinese quality label");
        Assert(RadarJson.QualityLabel(55, "red", false) == "low", "English low IQ label");
        Assert(AppServerClient.ChooseWindow(new[] { (300d, 20d), (10080d, 40d) }, 10080)?.Used == 40,
            "weekly app-server window selection");
        Assert(AppServerClient.JsonLineEncoding.GetPreamble().Length == 0,
            "app-server JSON Lines input must not emit a UTF-8 BOM");
        Assert(AppServerClient.ShouldTryNextCandidate(new AppServerRpcException(-32601, "Method not found")),
            "an incompatible quota RPC falls through to another Codex candidate");
        Assert(!AppServerClient.ShouldTryNextCandidate(new AppServerRpcException(-32000, "authentication required")),
            "account authentication failures must not cycle through Codex candidates");
        Assert(!AppServerClient.ShouldTryNextCandidate(new TimeoutException("quota timed out")),
            "a quota timeout must not multiply across every Codex candidate");
        Assert(!AppServerClient.ShouldTryNextStartCandidate(
                new AppServerRpcException(-32000, "authentication required")),
            "initialize authentication failures must not cycle through Codex candidates");
        Assert(!AppServerClient.ShouldTryNextStartCandidate(new TimeoutException("initialize timed out")),
            "an initialize timeout must not multiply across every Codex candidate");
        Assert(AppServerClient.ShouldTryNextStartCandidate(new System.ComponentModel.Win32Exception(2)),
            "an executable-specific startup failure falls through to another candidate");
        using (var rateLimitDocument = JsonDocument.Parse("""
            {
              "rateLimits": {
                "primary": { "usedPercent": 20, "windowDurationMins": 300, "resetsAt": 1783789200 },
                "secondary": { "usedPercent": 40, "windowDurationMins": 10080, "resetsAt": 1784394000 },
                "credits": null, "planType": "pro", "rateLimitReachedType": null
              },
              "rateLimitsByLimitId": null
            }
            """))
        {
            var quota = AppServerClient.ParseRateLimits(rateLimitDocument.RootElement);
            Assert(quota.Short == 80 && quota.Weekly == 60 && quota.PlanType == "pro",
                "null rateLimitsByLimitId falls back to rateLimits");
        }
        using (var durationlessRateLimitDocument = JsonDocument.Parse("""
            {
              "rateLimits": {
                "primary": { "usedPercent": 12, "windowDurationMins": null, "resetsAt": 1783789200 },
                "secondary": { "usedPercent": 34, "resetsAt": 1784394000 },
                "credits": null, "planType": "plus", "rateLimitReachedType": null
              }
            }
            """))
        {
            var quota = AppServerClient.ParseRateLimits(durationlessRateLimitDocument.RootElement);
            Assert(quota.Short == 88 && quota.Weekly == 66
                   && quota.ShortDurationMinutes is null && quota.WeeklyDurationMinutes is null,
                "durationless app-server buckets match macOS primary/secondary fallback");
        }
        using (var emptyRateLimitDocument = JsonDocument.Parse("""
            { "rateLimits": { "primary": null, "secondary": null, "rateLimitReachedType": null } }
            """))
        {
            var quota = AppServerClient.ParseRateLimits(emptyRateLimitDocument.RootElement);
            Assert(quota.Short is null && quota.Weekly is null,
                "missing app-server windows remain unavailable instead of becoming 100 percent");
        }
        using (var mixedDurationRateLimitDocument = JsonDocument.Parse("""
            {
              "rateLimits": {
                "primary": { "usedPercent": 12, "windowDurationMins": null, "resetsAt": 1783789200 },
                "secondary": { "usedPercent": 34, "windowDurationMins": 10080, "resetsAt": 1784394000 }
              }
            }
            """))
        {
            var quota = AppServerClient.ParseRateLimits(mixedDurationRateLimitDocument.RootElement);
            Assert(quota.Short == 88 && quota.Weekly == 66
                   && quota.ShortDurationMinutes is null && quota.WeeklyDurationMinutes == 10_080,
                "mixed-duration buckets use the macOS nil-as-zero shortest fallback");
        }

        var options = new AppSettings
        {
            Chinese = false,
            PreciseIq = false,
            SelectedStatusMetrics = [StatusMetric.WeeklyQuota, StatusMetric.CodexIq, StatusMetric.Signal]
        };
        var status = new DashboardSnapshot { WeeklyRemaining = 96, IqScore = 112.9, IqStatus = "green" };
        Assert(status.CompactTitle(options) == "96%/112/ok", "Windows status summary matches macOS formatting");
        var dividedIqOptions = new AppSettings
        {
            Chinese = false,
            IqDisplayMode = StatusBarIqDisplayMode.DividedBy10Decimal,
            SelectedStatusMetrics = [StatusMetric.CodexIq]
        };
        Assert(new DashboardSnapshot { IqScore = 62.5 }.CompactTitle(dividedIqOptions) == "6.3",
            "divided IQ midpoint rounds like Swift");
        dividedIqOptions.IqDisplayMode = StatusBarIqDisplayMode.Raw;
        dividedIqOptions.PreciseIq = true;
        Assert(new DashboardSnapshot { IqScore = 112.25 }.CompactTitle(dividedIqOptions) == "112.3",
            "precise IQ midpoint rounds like Swift");

        var speed = status with
        {
            WindowOpen = true, WindowId = "official-window", WindowOpenedAt = DateTimeOffset.UnixEpoch,
            RecommendedAction = "use_remaining_tokens"
        };
        Assert(speed.ActiveSpeedWindow && !speed.ActiveEntitlementEvent, "explicit speed action classification");
        var entitlement = speed with { RecommendedAction = "reset_completed", WindowStatus = "community_confirmed" };
        Assert(!entitlement.ActiveSpeedWindow && entitlement.ActiveEntitlementEvent && entitlement.ResetCloseKey is not null,
            "completed entitlement is not misclassified as speed");

        var pacingNow = new DateTimeOffset(2026, 7, 11, 12, 0, 0, TimeSpan.Zero);
        var pacing = QuotaPacingCalculator.Calculate(new DashboardSnapshot
        {
            WeeklyUsedPercent = 10, WeeklyWindowMinutes = 100, WeeklyResetsAt = pacingNow.AddMinutes(50)
        }, options, pacingNow);
        Assert(pacing?.RoundedTargetUsed == 50 && pacing.Status == QuotaPacingStatus.UnderTarget,
            "time-proportional pacing calculation");
        var midpointPacing = new QuotaPacingSnapshot(QuotaPacingStrategy.TimeProportional,
            35.5, 36, .5, 64.5, pacingNow, pacingNow.AddDays(1));
        Assert(midpointPacing.RoundedCurrentRemaining == 65 && midpointPacing.RoundedElapsed == 65
               && midpointPacing.RoundedRemainingDelta == 1,
            "pacing midpoint rounding matches Swift");
        var negativeMidpointPacing = new QuotaPacingSnapshot(QuotaPacingStrategy.TimeProportional,
            34.5, 26, -8.5, 0, pacingNow, pacingNow.AddDays(1));
        Assert(negativeMidpointPacing.RoundedCurrentUsed == 35 && negativeMidpointPacing.RoundedRemainingDelta == -9,
            "negative pacing midpoint rounds like Swift");

        var notificationSettings = new AppSettings
        {
            Chinese = false,
            NotificationMemory = new NotificationMemory { Initialized = true }
        };
        var resetAt = pacingNow.AddDays(5);
        var before = new DashboardSnapshot { WeeklyRemaining = 50, WeeklyResetsAt = resetAt, IqScore = 100 };
        var urgent = speed with { WeeklyRemaining = 10, WeeklyResetsAt = resetAt, IqScore = 100 };
        var events = NotificationPolicy.Evaluate(before, urgent, notificationSettings, pacingNow);
        Assert(events.Any(item => item.Identifier.StartsWith("speed-window-open-"))
               && events.Any(item => item.Identifier.StartsWith("weekly-critical-")),
            "one refresh preserves multiple notifications");

        var predictionSettings = new AppSettings
        {
            Chinese = false, PredictionNotifications = false,
            NotificationMemory = new NotificationMemory { Initialized = true }
        };
        var lowPrediction = before with { Prediction = new PredictionInfo("low", .1, .2, false, null, null, pacingNow) };
        var highPrediction = before with { Prediction = new PredictionInfo("high", .125, .92, true, null, null, pacingNow.AddMinutes(1)) };
        var hiddenEvents = NotificationPolicy.Evaluate(lowPrediction, highPrediction, predictionSettings, pacingNow);
        Assert(hiddenEvents.Any(item => item.Body.Contains("13%")), "prediction midpoint probability rounds like Swift");
        predictionSettings.PredictionNotifications = true;
        Assert(!NotificationPolicy.Evaluate(highPrediction, highPrediction, predictionSettings, pacingNow.AddMinutes(1))
                .Any(item => item.Identifier.StartsWith("prediction-")),
            "disabled categories still advance notification memory");

        Assert(SemanticVersion.Parse("1.2.3-beta") < SemanticVersion.Parse("1.2.3"), "semantic prerelease ordering");
        AssertThrows<FormatException>(() => SemanticVersion.Parse("1.2.3+build"), "release build metadata must be rejected");
        var architecture = AppUpdateService.ArchitectureLabel;
        AppUpdateService.EnsureWindowsAsset($"CodexRadarSentinel-1.2.3-Windows-{architecture}.zip");
        AssertThrows<InvalidDataException>(() => AppUpdateService.EnsureWindowsAsset("CodexRadarSentinel-1.2.3-macOS.zip"),
            "Windows updater must reject macOS assets");
        AssertThrows<InvalidDataException>(() => AppUpdateService.EnsureGitHubAssetUri(new Uri("https://example.com/file.zip")),
            "Windows updater must reject non-repository download URLs");

        var html = """
                   <title>7.11_pm GPT-5.5 high: IQ指数 101.5, 19/20, 费用 $2.50, 耗时 3分钟, cache命中率 66.0%</title>
                   <section class="reset-judgement"><div class="reset-judgement-head"><strong>重置雷达</strong></div>
                   <h2>状态 <em>12:00</em></h2><article class="reset-judgement-card"><span>硬重置</span><strong>high</strong><p>测试摘要</p></article><li>测试依据</li></section>
                   <section class="community-knowledge"><article class="community-knowledge-card"><h2>重置卡自查</h2><code data-site-announcement-prompt>unsafe remote prompt</code></article></section>
                   """;
        var homepage = CodexRadarHtmlParser.Parse(html, pacingNow);
        Assert(homepage.IqScore == 101.5 && homepage.ResetRadarCards.Count == 1
               && homepage.CommunityKnowledge == "重置卡自查", "homepage fallback parser");

        using var currentDocument = JsonDocument.Parse("""
            {
              "schema_version": "2.0", "monitored_at": "2026-07-11T12:00:00Z",
              "status": "active", "window_open": true, "recommended_action": "use_remaining_tokens",
              "last_window": { "id": "official", "status": "open", "title": "Official window", "opened_at": "2026-07-11T11:00:00Z" },
              "prediction": { "level": "medium_high", "probability_24h": 0.4, "probability_48h": 0.7, "should_notify": true },
              "model_iq": {
                "latest": { "date": "2026-07-11-pm", "model": "gpt-5.5", "reasoning_effort": "high", "iq_score": 101.5, "status": "green", "passed": 19, "valid_tasks": 20, "wall_seconds": 150 },
                "comparisons": { "gpt_5_4_high": { "label": "GPT-5.4 high", "latest": { "iq_score": 98, "status": "green", "passed": 18, "valid_tasks": 20 } } },
                "quota_radar": {
                  "date": "2026-07-11-pm", "basis_window_label": "20x Pro", "cost_usd": 2.5, "total_tokens": 1234,
                  "rows": [{ "tier": "20x Pro", "basis": "measured 7d", "five_h": 276.44, "seven_d": 1658.63 }],
                  "trend": [{ "seven_d_20x": 1600 }, { "seven_d_20x": 1658.63 }]
                }
              },
              "reset_judgement": { "title": "Reset", "cards": [{ "label": "Hard", "level": "high", "summary": "Test" }], "reasons": ["Evidence"] },
              "community_knowledge": { "title": "Knowledge", "prompt": "remote" },
              "site_announcement": { "label": "Notice", "message": "Hello", "source_url": "https://codexradar.com/" }
            }
            """);
        var current = RadarService.ParseCurrent(currentDocument.RootElement);
        Assert(current.WindowOpen && current.RecommendedAction == "use_remaining_tokens" && current.IqScore == 101.5
               && current.WallTime == "3 min",
            "current.json core fields");
        Assert(current.Comparisons.Count == 1 && current.QuotaRadar.Count == 1
               && current.QuotaRadarSevenDayTrendDelta is > 58 and < 59,
            "current.json comparison and quota radar fields");
        Assert(current.ResetRadarCards.Count == 1 && current.CommunityKnowledge == "Knowledge" && current.Announcement == "Hello",
            "current.json public dashboard sections");

        using var windowDocument = JsonDocument.Parse("""
            {
              "schema_version": "2.0", "status": "active",
              "window": { "open": true, "status": "none", "action": "speed_window_open", "message": "45 min", "opened_at": "2026-07-11T11:00:00Z" }
            }
            """);
        var normalizedWindow = RadarService.ParseCurrent(windowDocument.RootElement);
        Assert(normalizedWindow.WindowOpen && normalizedWindow.WindowStatus == "open" && normalizedWindow.WindowHuman == "45 min",
            "v2 open window payload normalization matches macOS");

        using var closedWindowDocument = JsonDocument.Parse("""
            {
              "schema_version": "2.0",
              "window": { "open": false, "status": "none", "message": "closed", "closed_at": "2026-07-11T11:45:00Z" }
            }
            """);
        var normalizedClosedWindow = RadarService.ParseCurrent(closedWindowDocument.RootElement);
        Assert(!normalizedClosedWindow.WindowOpen && normalizedClosedWindow.WindowStatus == "closed" && normalizedClosedWindow.WindowHuman == "无窗",
            "v2 closed window payload normalization matches macOS");
    }
}
