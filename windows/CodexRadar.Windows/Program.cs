using System.Text.Json;

namespace CodexRadar.Windows;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (args.Contains("--self-test", StringComparer.OrdinalIgnoreCase))
        {
            RunDiagnostic(SelfTest.Run);
            return;
        }
        if (args.Contains("--ui-self-test", StringComparer.OrdinalIgnoreCase))
        {
            RunDiagnostic(() => DashboardVisualSmoke.Run());
            return;
        }
        if (args.Contains(
                "--taskbar-ui-self-test",
                StringComparer.OrdinalIgnoreCase))
        {
            RunDiagnostic(() => TaskbarStatusVisualSmoke.Run());
            return;
        }
        var renderIndex = Array.FindIndex(
            args,
            argument => argument.Equals(
                "--render-preview",
                StringComparison.OrdinalIgnoreCase));
        if (renderIndex >= 0)
        {
            RunDiagnostic(() =>
            {
                if (renderIndex + 1 >= args.Length)
                    throw new ArgumentException(
                        "--render-preview requires an output PNG path.");
                DashboardVisualSmoke.Run(
                    Path.GetFullPath(args[renderIndex + 1]));
            });
            return;
        }
        var taskbarRenderIndex = Array.FindIndex(
            args,
            argument => argument.Equals(
                "--render-taskbar-preview",
                StringComparison.OrdinalIgnoreCase));
        if (taskbarRenderIndex >= 0)
        {
            RunDiagnostic(() =>
            {
                if (taskbarRenderIndex + 1 >= args.Length)
                    throw new ArgumentException(
                        "--render-taskbar-preview requires an output PNG path.");
                TaskbarStatusVisualSmoke.Run(
                    Path.GetFullPath(args[taskbarRenderIndex + 1]));
            });
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

    private static void RunDiagnostic(Action action)
    {
        try
        {
            action();
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex);
            Environment.ExitCode = 1;
        }
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
        Assert(new AppSettings().StatusDisplayMode == StatusDisplayMode.NotificationArea,
            "existing installs default to the notification-area location");
        Assert(JsonSerializer.Deserialize<AppSettings>("{}")?.StatusDisplayMode == StatusDisplayMode.NotificationArea,
            "settings migration preserves the existing notification-area behavior");
        var signatureTime = new DateTimeOffset(2026, 7, 11, 12, 0, 0, TimeSpan.Zero);
        var signatureAtNoon = DashboardForm.BuildContentSignature(
            status with { RefreshedAt = signatureTime }, options, new AppUpdateStatus(AppUpdatePhase.Idle), false,
            signatureTime);
        var signatureOneMinuteLater = DashboardForm.BuildContentSignature(
            status with { RefreshedAt = signatureTime.AddMinutes(1) }, options, new AppUpdateStatus(AppUpdatePhase.Idle), false,
            signatureTime.AddMinutes(1));
        Assert(signatureAtNoon == signatureOneMinuteLater,
            "refresh timestamps update dashboard chrome without rebuilding the card tree");
        Assert(signatureAtNoon != DashboardForm.BuildContentSignature(
                status with { WeeklyRemaining = 95, RefreshedAt = signatureTime.AddMinutes(1) },
                options, new AppUpdateStatus(AppUpdatePhase.Idle), false, signatureTime.AddMinutes(1)),
            "rendered data changes replace the dashboard card tree");
        var signatureHistory = new QuotaHistoryTimeline(
            [
                new QuotaHistorySample(
                    signatureTime.AddMinutes(-5),
                    80,
                    null)
            ]);
        Assert(
            DashboardForm.BuildContentSignature(
                status,
                options,
                new AppUpdateStatus(
                    AppUpdatePhase.Idle),
                false,
                signatureTime,
                signatureHistory,
                signatureTime)
            == DashboardForm.BuildContentSignature(
                status,
                options,
                new AppUpdateStatus(
                    AppUpdatePhase.Idle),
                false,
                signatureTime.AddMinutes(1),
                signatureHistory,
                signatureTime.AddMinutes(1)),
            "collapsed quota history does not rebuild the dashboard each minute");
        options.QuotaHistoryExpanded = true;
        Assert(
            DashboardForm.BuildContentSignature(
                status,
                options,
                new AppUpdateStatus(
                    AppUpdatePhase.Idle),
                false,
                signatureTime,
                signatureHistory,
                signatureTime)
            != DashboardForm.BuildContentSignature(
                status,
                options,
                new AppUpdateStatus(
                    AppUpdatePhase.Idle),
                false,
                signatureTime.AddMinutes(1),
                signatureHistory,
                signatureTime.AddMinutes(1)),
            "visible quota-history time windows advance every minute");
        var taskbarTextBounds = TaskbarStatusForm.CalculateHorizontalBounds(
            new Rectangle(0, 1040, 1920, 40),
            new Rectangle(1700, 1040, 220, 40),
            new Size(128, 30),
            4);
        Assert(taskbarTextBounds.Right == 1696 && taskbarTextBounds.Top == 1045,
            "taskbar text is centered immediately left of the notification area");
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

        var historyEpoch =
            DateTimeOffset.FromUnixTimeSeconds(
                1_700_000_000);
        DateTimeOffset HistoryDate(double seconds) =>
            historyEpoch.AddSeconds(seconds);
        QuotaHistorySample HistorySample(
            double seconds,
            double remaining,
            DateTimeOffset? resetsAt = null) =>
            new(
                HistoryDate(seconds),
                remaining,
                resetsAt);

        var firstHistoryReset =
            HistoryDate(7 * 86_400);
        var secondHistoryReset =
            HistoryDate(14 * 86_400);
        var recordedHistory = new QuotaHistoryTimeline();
        Assert(recordedHistory.Record(
                HistorySample(
                    0,
                    90,
                    firstHistoryReset),
                HistoryDate(0)),
            "quota history records its first sample");
        Assert(!recordedHistory.Record(
                HistorySample(
                    60,
                    90,
                    firstHistoryReset),
                HistoryDate(60)),
            "quota history suppresses unchanged sub-five-minute samples");
        Assert(recordedHistory.Record(
                HistorySample(
                    120,
                    89.7,
                    firstHistoryReset),
                HistoryDate(120)),
            "quota history records a quarter-point change");
        Assert(!recordedHistory.Record(
                HistorySample(
                    180,
                    89.6,
                    firstHistoryReset),
                HistoryDate(180)),
            "quota history applies the change threshold to the last record");
        Assert(recordedHistory.Record(
                HistorySample(
                    420,
                    89.6,
                    firstHistoryReset),
                HistoryDate(420)),
            "quota history records five-minute heartbeats");
        Assert(recordedHistory.Record(
                HistorySample(
                    480,
                    89.6,
                    secondHistoryReset),
                HistoryDate(480))
               && recordedHistory.Samples
                   .Select(sample => sample.Timestamp)
                   .SequenceEqual(
                       [
                           HistoryDate(0),
                           HistoryDate(120),
                           HistoryDate(420),
                           HistoryDate(480)
                       ]),
            "quota history records reset-boundary changes");

        var rejectedHistory = new QuotaHistoryTimeline(
            [HistorySample(100, 80)]);
        Assert(
            !rejectedHistory.Record(
                HistorySample(99, 79),
                HistoryDate(101))
            && !rejectedHistory.Record(
                HistorySample(101, 101),
                HistoryDate(101))
            && !rejectedHistory.Record(
                HistorySample(
                    101,
                    double.NaN),
                HistoryDate(101))
            && !rejectedHistory.Record(
                HistorySample(10_000, 79),
                HistoryDate(101))
            && rejectedHistory.Samples.Count == 1,
            "quota history rejects invalid, out-of-order, and future samples");

        var retentionNow =
            HistoryDate(40 * 86_400);
        var retainedHistory = new QuotaHistoryTimeline(
            [
                HistorySample(0, 100),
                HistorySample(8 * 86_400, 80),
                HistorySample(9 * 86_400, 70),
                new QuotaHistorySample(
                    retentionNow,
                    60,
                    null)
            ]);
        retainedHistory.Prune(retentionNow);
        Assert(
            retainedHistory.Samples
                .Select(sample => sample.Timestamp)
                .SequenceEqual(
                    [
                        HistoryDate(9 * 86_400),
                        retentionNow
                    ]),
            "quota history keeps the inclusive 31-day boundary");

        var resetTimeline = new QuotaHistoryTimeline(
            [
                HistorySample(
                    9_600,
                    25,
                    HistoryDate(20_000)),
                HistorySample(
                    9_700,
                    31,
                    HistoryDate(20_000)),
                HistorySample(
                    9_800,
                    37,
                    HistoryDate(
                        20_000 + 7 * 86_400)),
                HistorySample(
                    9_900,
                    92,
                    HistoryDate(
                        20_000 + 7 * 86_400))
            ]);
        var observedResets = resetTimeline.ResetEvents(
            QuotaHistoryRange.Hours24,
            HistoryDate(10_000));
        Assert(
            observedResets.Count == 2
            && observedResets[0].Timestamp
            == HistoryDate(9_800)
            && Math.Abs(
                observedResets[0].Increase - 6) < .001
            && observedResets[1].Timestamp
            == HistoryDate(9_900),
            "quota history reset detection matches the observed thresholds");

        var summaryTimeline = new QuotaHistoryTimeline(
            [
                HistorySample(9_600, 90),
                HistorySample(9_700, 70),
                HistorySample(9_800, 100),
                HistorySample(9_900, 92)
            ]);
        var historySummary = summaryTimeline.Summary(
            QuotaHistoryRange.Hours24,
            HistoryDate(10_000));
        Assert(
            Math.Abs(
                historySummary.ObservedConsumption
                - 28) < .001
            && historySummary.ResetCount == 1
            && historySummary.SampleCount == 4,
            "quota history consumption never subtracts reset increases");

        var nearestTimeline = new QuotaHistoryTimeline(
            [
                HistorySample(9_700, 80),
                HistorySample(9_800, 70),
                HistorySample(9_900, 60)
            ]);
        Assert(
            nearestTimeline.NearestSample(
                    HistoryDate(9_760),
                    QuotaHistoryRange.Hours24,
                    HistoryDate(10_000))
                ?.Timestamp
            == HistoryDate(9_800)
            && nearestTimeline.NearestSample(
                    HistoryDate(9_750),
                    QuotaHistoryRange.Hours24,
                    HistoryDate(10_000))
                ?.Timestamp
            == HistoryDate(9_700),
            "quota history nearest-point ties choose the earlier sample");

        var denseHistorySamples = Enumerable.Range(
                0,
                120)
            .Select(index =>
                HistorySample(
                    index * 60,
                    index == 40
                        ? 12
                        : index == 41
                            ? 100
                            : 80 - index * .1))
            .ToArray();
        var denseHistory = new QuotaHistoryTimeline(
            denseHistorySamples);
        var downsampled = denseHistory.DisplaySamples(
            QuotaHistoryRange.Hours24,
            HistoryDate(86_400));
        Assert(
            downsampled.Any(sample =>
                sample.Timestamp
                == HistoryDate(0))
            && downsampled.Any(sample =>
                sample.Timestamp
                == HistoryDate(40 * 60))
            && downsampled.Any(sample =>
                sample.Timestamp
                == HistoryDate(41 * 60))
            && downsampled.Any(sample =>
                sample.Timestamp
                == HistoryDate(119 * 60))
            && downsampled.Count
            < denseHistorySamples.Length,
            "quota history display buckets preserve endpoints, extrema, and resets");

        var observationAt =
            HistoryDate(20_000);
        var observedSnapshot = new DashboardSnapshot
        {
            QuotaObservedAt = observationAt,
            WeeklyUsedPercent = 26.625,
            WeeklyRemaining = 1,
            WeeklyResetsAt = secondHistoryReset
        };
        var observedSample =
            QuotaHistoryObservationPolicy.CreateSample(
                observedSnapshot,
                previousObservation: null,
                DashboardPreview.Live);
        Assert(
            observedSample is not null
            && Math.Abs(
                observedSample.RemainingPercent
                - 73.375) < .001
            && QuotaHistoryObservationPolicy.CreateSample(
                observedSnapshot,
                observationAt,
                DashboardPreview.Live) is null
            && QuotaHistoryObservationPolicy.CreateSample(
                observedSnapshot with
                {
                    QuotaObservedAt =
                        observationAt.AddMinutes(1),
                    WeeklyUsedPercent = null
                },
                observationAt,
                DashboardPreview.Live) is null
            && QuotaHistoryObservationPolicy.CreateSample(
                observedSnapshot,
                previousObservation: null,
                DashboardPreview.QualityLow)
            is null,
            "quota history records only new live weekly observations at double precision");
        var hiddenHistorySettings =
            new AppSettings();
        hiddenHistorySettings
            .SetDashboardSectionVisible(
                DashboardSection.Quota,
                false);
        hiddenHistorySettings
            .SetDashboardDisclosureVisible(
                DashboardDisclosure.QuotaHistory,
                false);
        Assert(
            QuotaHistoryObservationPolicy.CreateSample(
                observedSnapshot,
                previousObservation: null,
                hiddenHistorySettings.Preview)
            is not null,
            "hidden quota presentation continues background recording");

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

        var layout = DashboardLayout.NormalizeOrder(
            [
                DashboardSection.Updates,
                DashboardSection.Quota,
                DashboardSection.Updates
            ]);
        Assert(layout.Count == DashboardLayout.DefaultOrder.Length
               && layout.Distinct().Count() == layout.Count
               && layout.IndexOf(DashboardSection.Quota)
               < layout.IndexOf(DashboardSection.ModelIq)
               && layout.IndexOf(DashboardSection.Updates)
               < layout.IndexOf(DashboardSection.Preview),
            "dashboard layout migration inserts missing sections by the macOS anchors");
        Assert(DashboardLayout.IsDefault(
                DashboardLayout.DefaultOrder,
                DashboardLayout.NormalizeExpansion(null)),
            "dashboard default order and expansion match macOS");
        Assert(
            DashboardLayout.Children(
                DashboardSection.Quota)
                .SequenceEqual(
                    [DashboardDisclosure.QuotaHistory])
            && DashboardLayout.Children(
                DashboardSection.ModelIq)
                .SequenceEqual(
                    [DashboardDisclosure.ModelIqDetails])
            && DashboardLayout.Children(
                DashboardSection.Insights)
                .SequenceEqual(
                    [DashboardDisclosure.RadarInsightsDetails])
            && Enum.GetValues<DashboardDisclosure>()
                .All(disclosure =>
                    DashboardLayout.Children(
                            DashboardLayout.ParentSection(
                                disclosure))
                        .Count(item =>
                            item == disclosure) == 1),
            "nested dashboard disclosures have one parent");
        var layoutSettings = new AppSettings
        {
            Chinese = false,
            TextSize = DashboardTextSize.ExtraLarge,
            AutomaticUpdates = false
        };
        layoutSettings.SetDashboardSectionExpanded(
            DashboardSection.Quota,
            false);
        layoutSettings.SetDashboardSectionVisible(
            DashboardSection.Quota,
            false);
        layoutSettings.SetDashboardDisclosureVisible(
            DashboardDisclosure.QuotaHistory,
            false);
        Assert(
            !layoutSettings.IsDashboardSectionVisible(
                DashboardSection.Quota)
            && !layoutSettings.IsDashboardSectionExpanded(
                DashboardSection.Quota),
            "hiding a section preserves its expansion preference");
        layoutSettings.ResetDashboardLayout();
        Assert(
            layoutSettings.Chinese == false
            && layoutSettings.TextSize
            == DashboardTextSize.ExtraLarge
            && !layoutSettings.AutomaticUpdates
            && DashboardLayout.IsDefault(
                layoutSettings.DashboardSectionOrder,
                layoutSettings.DashboardSectionExpansion,
                layoutSettings.DashboardSectionVisibility,
                layoutSettings
                    .DashboardDisclosureVisibility)
            && !layoutSettings.QuotaHistoryExpanded
            && !layoutSettings.ModelIqDetailsExpanded
            && !layoutSettings.RadarInsightsDetailsExpanded,
            "restoring dashboard layout leaves unrelated settings unchanged");

        foreach (var attentionKind in new[]
                 {
                     ResetCreditProtectionStatusKind.Using,
                     ResetCreditProtectionStatusKind.Reconciling,
                     ResetCreditProtectionStatusKind.Missed,
                     ResetCreditProtectionStatusKind.Blocked
                 })
        {
            var forced = DashboardLayout.Resolve(
                DashboardSection.ResetCredits,
                preferredVisible: false,
                preferredExpanded: false,
                new ResetCreditProtectionStatus(
                    attentionKind),
                requiresUpdateAttention: false);
            Assert(
                forced
                    == new DashboardSectionResolution(
                        true,
                        true,
                        false,
                        false),
                "reset-credit attention temporarily forces visibility");
        }
        var routineReset = DashboardLayout.Resolve(
            DashboardSection.ResetCredits,
            preferredVisible: false,
            preferredExpanded: false,
            ResetCreditProtectionStatus.Disabled,
            requiresUpdateAttention: false);
        Assert(
            routineReset
                == new DashboardSectionResolution(
                    false,
                    false,
                    true,
                    true),
            "routine reset-credit state restores saved visibility");
        var failedUpdate = DashboardLayout.Resolve(
            DashboardSection.Updates,
            preferredVisible: false,
            preferredExpanded: false,
            ResetCreditProtectionStatus.Disabled,
            requiresUpdateAttention: true);
        var routineUpdate = DashboardLayout.Resolve(
            DashboardSection.Updates,
            preferredVisible: false,
            preferredExpanded: false,
            ResetCreditProtectionStatus.Disabled,
            requiresUpdateAttention: false);
        Assert(
            !failedUpdate.CanHide
            && failedUpdate.IsExpanded
            && !routineUpdate.IsVisible,
            "only failed updates temporarily override layout preferences");

        var efficiencyPoints = Enumerable.Range(0, 19).Select(index =>
        {
            var model = index == 0 ? "gpt-5.6-sol" : $"gpt-5.{index}-terra";
            var effort = index == 0 ? "max" : "high";
            return $$"""
                     {
                       "model": "{{model}}", "effort": "{{effort}}",
                       "iq": {{120 - index}}, "passed": 19,
                       "valid_tasks": 20, "average_price_usd": 1.25,
                       "average_minutes": 2.5, "cache_hit_rate": 66
                     }
                     """;
        });
        var efficiency = IntelligenceEfficiencyParser.Parse(
            $$"""
              {
                "schema": 1,
                "type": "intelligence_efficiency",
                "source_updated_at": "2026-07-29T00:00:00Z",
                "points": [{{string.Join(",", efficiencyPoints)}}]
              }
              """);
        var mergedEfficiency = IntelligenceEfficiencyParser.Merge(
            new PublicRadarData(),
            efficiency);
        Assert(mergedEfficiency.ModelName == "gpt-5.6-sol"
               && mergedEfficiency.ReasoningEffort == "max"
               && mergedEfficiency.Comparisons.Count == 18
               && mergedEfficiency.IqValidCells == 380
               && mergedEfficiency.AverageCostUsd == 1.25
               && mergedEfficiency.AverageTaskMinutes == 2.5
               && mergedEfficiency.IqDataSourceUrl
               == "https://deng.codexradar.com",
            "19-point intelligence-efficiency merge matches macOS");

        var insights = RadarInsightsParser.Parse("""
            {
              "schema": "1",
              "generated_at": "2026-07-29T00:00:00Z",
              "data": {
                "schema": 1,
                "source_updated_at": {
                  "older": "2026-07-28T00:00:00Z",
                  "latest": "2026-07-29T01:00:00Z"
                },
                "station_recs": [{
                  "id": "best_value", "description": "lowest cost",
                  "models": [
                    {
                      "model": "gpt-5.6-sol", "effort": "max",
                      "current_iq": "118.5", "average_price_usd": "1.25",
                      "average_minutes": "2.5"
                    },
                    { "model": "", "effort": "high", "iq": 100 }
                  ]
                }],
                "alerts": {
                  "rule": "drop",
                  "alerts": [{
                    "model": "gpt-5.5", "effort": "high",
                    "current_iq": "90", "drop24h": "7.5"
                  }]
                }
              }
            }
            """);
        Assert(insights.Recommendations.Count == 1
               && insights.Recommendations[0].ValidItems.Count == 1
               && insights.DegradationAlerts.ValidItems.Count == 1
               && insights.EffectiveTimestamp
               == new DateTimeOffset(
                   2026, 7, 29, 1, 0, 0, TimeSpan.Zero).ToLocalTime(),
            "radar-insights aliases, numeric strings, filtering, and dynamic timestamp");
        var olderInsights = RadarInsightsParser.Parse("""
            {
              "schema": 1,
              "source_updated_at": "2026-07-28T00:00:00Z",
              "recommendations": []
            }
            """);
        Assert(!RadarInsightsParser.ShouldAccept(insights, olderInsights),
            "radar-insights rejects timestamp regression");
        AssertThrows<JsonException>(
            () => RadarInsightsParser.Parse(
                """{ "schema": 2, "recommendations": [] }"""),
            "radar-insights fails closed on unsupported schemas");
        AssertThrows<JsonException>(
            () => RadarInsightsParser.Parse(
                """{ "schema": 1, "data": [], "recommendations": [] }"""),
            "radar-insights rejects a malformed data wrapper like macOS");
        AssertThrows<JsonException>(
            () => RadarInsightsParser.Parse(
                """
                {
                  "schema": 1,
                  "recommendations": {},
                  "data": { "schema": 1, "recommendations": [] }
                }
                """),
            "radar-insights validates the outer body even with a valid wrapper");

        const string rawCreditId =
            "credit-private-do-not-persist-123456";
        var rawCreditFingerprint =
            ResetCreditPrivacy.Fingerprint(rawCreditId);
        Assert(ResetCreditPrivacy.IsValidFingerprint(rawCreditFingerprint)
               && !rawCreditFingerprint.Contains(
                   rawCreditId, StringComparison.Ordinal),
            "reset-credit fingerprint is irreversible fixed-width SHA-256");
        var cachedCreditJson = JsonSerializer.Serialize(
            new AppSettings
            {
                CachedResetCredits =
                [
                    new ResetCredit(
                        "Private credit",
                        "available",
                        pacingNow,
                        pacingNow.AddHours(1),
                        rawCreditFingerprint,
                        "codexRateLimits")
                ]
            });
        Assert(!cachedCreditJson.Contains(
                   rawCreditId, StringComparison.Ordinal)
               && !cachedCreditJson.Contains(
                   "IdSuffix", StringComparison.OrdinalIgnoreCase),
            "settings cache contains fingerprints and no raw ID suffix field");

        using var protectionRateLimitsDocument = JsonDocument.Parse(
            $$"""
              {
                "rateLimitResetCredits": {
                  "availableCount": 2,
                  "credits": [
                    {
                      "id": "{{rawCreditId}}", "resetType": "codexRateLimits",
                      "status": "available", "grantedAt": 1785250000,
                      "expiresAt": 1785265600
                    },
                    {
                      "id": "later-private-credit", "resetType": "codexRateLimits",
                      "status": "available", "grantedAt": 1785250000,
                      "expiresAt": 1785269200
                    }
                  ]
                }
              }
              """);
        var protectionSummary =
            ProtectionRateLimitResponse.Parse(
                protectionRateLimitsDocument.RootElement).ResetCredits!;
        var protectionNow =
            DateTimeOffset.FromUnixTimeSeconds(1785264000);
        var protectionDecision =
            ResetCreditExpiryProtectionPolicy.Decide(
                protectionSummary, protectionNow);
        Assert(protectionDecision.Kind
               == ResetCreditProtectionDecisionKind.Ready
               && protectionDecision.Target?.CreditFingerprint
               == rawCreditFingerprint,
            "reset-credit policy selects the earliest supported expiry");
        var secondDecision =
            ResetCreditExpiryProtectionPolicy.Decide(
                protectionSummary,
                protectionNow,
                new HashSet<string>([rawCreditFingerprint]));
        Assert(secondDecision.Target?.CreditFingerprint
               == ResetCreditPrivacy.Fingerprint(
                   "later-private-credit"),
            "tombstoned reset credits are never selected again");
        Assert(ResetCreditExpiryProtectionPolicy.Decide(
                   protectionSummary with { AvailableCount = 3 },
                   protectionNow).Kind
               == ResetCreditProtectionDecisionKind.DetailsIncomplete,
            "auto-use fails closed when available count and details disagree");

        var clockAnchor = new ResetCreditProtectionClockSample(
            pacingNow, 100);
        var consent = new ResetCreditProtectionConsent(
            2,
            ResetCreditPrivacy.Fingerprint("chatgpt:user@example.invalid"),
            Guid.NewGuid().ToString(),
            pacingNow,
            new HashSet<string>([rawCreditFingerprint]),
            clockAnchor);
        Assert(ResetCreditProtectionAuthorization.ClockDiscontinuity(
                   consent,
                   new ResetCreditProtectionClockSample(
                       pacingNow.AddSeconds(5), 105)) is null
               && ResetCreditProtectionAuthorization.ClockDiscontinuity(
                   consent,
                   new ResetCreditProtectionClockSample(
                       pacingNow.AddSeconds(11), 105))
               == ClockDiscontinuityReason.WallClockOffset,
            "reset-credit consent enforces the five-second clock-continuity boundary");

        var journal = new ResetCreditProtectionAttemptJournal(
            1,
            consent.AccountFingerprint,
            rawCreditFingerprint,
            Guid.NewGuid().ToString(),
            protectionNow.AddHours(1),
            2,
            ResetCreditAttemptPhase.Sending,
            null,
            protectionNow);
        var redeemedSummary = protectionSummary with
        {
            AvailableCount = 1,
            Credits =
            [
                protectionSummary.Credits![0] with
                {
                    Status = "redeemed"
                },
                protectionSummary.Credits[1]
            ]
        };
        Assert(ResetCreditProtectionRecoveryPolicy.Decide(
                   journal,
                   redeemedSummary,
                   protectionNow).Kind
               == ResetCreditRecoveryDecisionKind.ConfirmedUsed,
            "read-only reconciliation confirms a redeemed target");
        Assert(ResetCreditProtectionRecoveryPolicy.Decide(
                   journal,
                   null,
                   journal.ExpiresAt.AddSeconds(1)).Kind
               == ResetCreditRecoveryDecisionKind.Missed,
            "an unresolved journal becomes missed only after expiry");

        Assert(
            QuotaHistoryStore.IsArchiveValid(
                QuotaHistoryTimeline.ArchiveVersion,
                [
                    HistorySample(1, 80),
                    HistorySample(2, 79)
                ])
            && !QuotaHistoryStore.IsArchiveValid(
                QuotaHistoryTimeline.ArchiveVersion
                + 1,
                [])
            && !QuotaHistoryStore.IsArchiveValid(
                QuotaHistoryTimeline.ArchiveVersion,
                [
                    HistorySample(1, 80),
                    HistorySample(1, 79)
                ])
            && !QuotaHistoryStore.IsArchiveValid(
                QuotaHistoryTimeline.ArchiveVersion,
                [
                    HistorySample(2, 80),
                    HistorySample(1, 79)
                ])
            && !QuotaHistoryStore.IsArchiveValid(
                QuotaHistoryTimeline.ArchiveVersion,
                Enumerable.Repeat(
                        HistorySample(1, 80),
                        100_001)
                    .ToArray()),
            "quota archive rejects unknown versions, duplicate or unordered timestamps, and oversized input");

        var historyStorageDirectory = Path.Combine(
            Path.GetTempPath(),
            "codex-radar-history-self-test-"
            + Guid.NewGuid().ToString("N"));
        var historyStoragePath = Path.Combine(
            historyStorageDirectory,
            "history.json");
        var historyLockPath = Path.ChangeExtension(
            historyStoragePath,
            ".lock");
        try
        {
            var firstHistoryStore =
                new QuotaHistoryStore(
                    historyStoragePath);
            var secondHistoryStore =
                new QuotaHistoryStore(
                    historyStoragePath);
            var historyStoreNow =
                DateTimeOffset.UtcNow;
            var firstStored =
                firstHistoryStore.Record(
                    new QuotaHistorySample(
                        historyStoreNow,
                        64,
                        null),
                    historyStoreNow);
            var secondStored =
                secondHistoryStore.Record(
                    new QuotaHistorySample(
                        historyStoreNow
                            .AddMinutes(5),
                        63,
                        null),
                    historyStoreNow.AddMinutes(5));
            var thirdStored =
                firstHistoryStore.Record(
                    new QuotaHistorySample(
                        historyStoreNow
                            .AddMinutes(10),
                        62,
                        null),
                    historyStoreNow.AddMinutes(10));
            Assert(
                firstStored.DidChange
                && secondStored.DidChange
                && thirdStored.DidChange
                && firstHistoryStore.Load(
                        historyStoreNow
                            .AddMinutes(10))
                    is
                    {
                        Status:
                            QuotaHistoryLoadStatus.Loaded,
                        Timeline.Samples.Count: 3
                    },
                "quota history stores reload under the lock instead of overwriting newer samples");
            Assert(
                PrivateStorageSecurity
                    .IsRestrictedToCurrentUser(
                        historyStorageDirectory)
                && PrivateStorageSecurity
                    .IsRestrictedToCurrentUser(
                        historyStoragePath)
                && PrivateStorageSecurity
                    .IsRestrictedToCurrentUser(
                        historyLockPath),
                "quota history directory, data, and lock are restricted to the current Windows user");
            Assert(
                !Directory.EnumerateFiles(
                        historyStorageDirectory,
                        "*.tmp")
                    .Any(),
                "quota history atomic replacement leaves no temporary archive");

            Task<QuotaHistoryRecordResult> pendingRecord;
            using (new FileStream(
                       historyLockPath,
                       FileMode.Open,
                       FileAccess.ReadWrite,
                       FileShare.None))
            {
                pendingRecord = Task.Run(() =>
                    secondHistoryStore.Record(
                        new QuotaHistorySample(
                            historyStoreNow
                                .AddMinutes(15),
                            61,
                            null),
                        historyStoreNow
                            .AddMinutes(15)));
                Thread.Sleep(80);
                Assert(
                    !pendingRecord.IsCompleted,
                    "quota history waits for an active exclusive writer");
            }
            Assert(
                pendingRecord.GetAwaiter()
                    .GetResult().DidChange
                && firstHistoryStore.Load(
                        historyStoreNow
                            .AddMinutes(15))
                    .Timeline.Samples.Count == 4,
                "quota history bounded lock retry preserves a concurrent record");

            const string corruptHistory =
                "not-json";
            File.WriteAllText(
                historyStoragePath,
                corruptHistory);
            Assert(
                firstHistoryStore.Load(
                        historyStoreNow)
                    .Status
                == QuotaHistoryLoadStatus.Corrupt,
                "quota history distinguishes a corrupt archive");
            AssertThrows<InvalidDataException>(
                () => firstHistoryStore.Record(
                    new QuotaHistorySample(
                        historyStoreNow
                            .AddMinutes(20),
                        60,
                        null),
                    historyStoreNow
                        .AddMinutes(20)),
                "quota history refuses to overwrite a corrupt archive");
            Assert(
                File.ReadAllText(
                    historyStoragePath)
                == corruptHistory,
                "quota history leaves corrupt bytes untouched");
        }
        finally
        {
            try
            {
                Directory.Delete(
                    historyStorageDirectory,
                    recursive: true);
            }
            catch
            {
            }
        }

        var storageDirectory = Path.Combine(
            Path.GetTempPath(),
            "codex-radar-self-test-"
            + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(storageDirectory);
        try
        {
            var dispatchConsent = consent with
            {
                GrantedAt = DateTimeOffset.UtcNow,
                ClockAnchor = ResetCreditProtectionClockSample.Now()
            };
            var authorizationPath = Path.Combine(
                storageDirectory, "authorization.json");
            var dispatchLockPath = Path.Combine(
                storageDirectory, "dispatch.lock");
            var ledgerPath = Path.Combine(
                storageDirectory, "ledger.json");
            var authorizationStore =
                new ResetCreditProtectionAuthorizationStore(
                    authorizationPath, dispatchLockPath);
            var ledgerStore =
                new ResetCreditProtectionLedgerStore(ledgerPath);
            authorizationStore.Save(dispatchConsent);
            var authorizationJson =
                File.ReadAllText(authorizationPath);
            Assert(!authorizationJson.Contains(
                       rawCreditId, StringComparison.Ordinal)
                   && authorizationJson.Contains(
                       rawCreditFingerprint, StringComparison.Ordinal),
                "persisted authorization contains only credit fingerprints");
            var dispatches = 0;
            authorizationStore.PerformAuthorizedDispatch(
                dispatchConsent,
                rawCreditFingerprint,
                () => dispatches++);
            Assert(dispatches == 1,
                "matching persisted consent authorizes one dispatch");
            authorizationStore.Clear();
            AssertThrows<ResetCreditAuthorizationException>(
                () => authorizationStore.PerformAuthorizedDispatch(
                    dispatchConsent,
                    rawCreditFingerprint,
                    () => dispatches++),
                "revocation marker wins before a destructive dispatch");
            Assert(dispatches == 1,
                "revoked authorization never invokes the dispatch body");

            ledgerStore.Save(new ResetCreditProtectionLedger
            {
                ActiveAttempt = journal
            });
            var ledgerJson = File.ReadAllText(ledgerPath);
            Assert(!ledgerJson.Contains(
                       rawCreditId, StringComparison.Ordinal)
                   && ledgerJson.Contains(
                       rawCreditFingerprint, StringComparison.Ordinal)
                   && ledgerStore.Load().State
                   == ProtectionStorageState.Loaded,
                "crash-recovery ledger persists no raw reset-credit ID");
        }
        finally
        {
            try
            {
                Directory.Delete(storageDirectory, recursive: true);
            }
            catch
            {
            }
        }
    }
}
