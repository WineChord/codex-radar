namespace CodexRadar.Windows;

internal static class DashboardVisualSmoke
{
    public static void Run(string? outputPath = null, bool interactive = false)
    {
        ApplicationConfiguration.Initialize();
        var now = DateTimeOffset.Now;
        var snapshot = new DashboardSnapshot
        {
            RefreshedAt = now,
            RadarStatus = "retired",
            WeeklyRemaining = 74,
            ShortRemaining = 88,
            WeeklyUsedPercent = 26,
            ShortUsedPercent = 12,
            WeeklyWindowMinutes = 10_080,
            ShortWindowMinutes = 300,
            WeeklyResetsAt = now.AddDays(4),
            ShortResetsAt = now.AddHours(3),
            PlanType = "pro",
            IqScore = 112.5,
            IqStatus = "green",
            ModelLabel = "GPT-5.6 Sol max",
            ModelName = "gpt-5.6-sol",
            ReasoningEffort = "max",
            Passed = 19,
            ValidTasks = 20,
            AverageCostUsd = 1.25,
            AverageTaskMinutes = 2.5,
            IqDataSourceUrl = "https://deng.codexradar.com",
            IqValidCells = 380,
            Comparisons =
            [
                new ModelComparison(
                    "GPT-5.5 high", 104.2, "green", 18, 20,
                    Model: "gpt-5.5", Effort: "high",
                    AverageCostUsd: 1.02, AverageMinutes: 2.1)
            ],
            RadarInsights = new RadarInsightsEnvelope(
                now.ToString("O"),
                now.ToString("O"),
                [
                    new RadarRecommendationGroup(
                        "best_value",
                        "性价比",
                        "在质量与成本之间平衡",
                        [
                            new RadarRecommendationItem(
                                "gpt-5.6-sol",
                                "max",
                                112.5,
                                1.25,
                                2.5)
                        ])
                ],
                new RadarDegradationCollection(
                    "24 小时高点变化",
                    [
                        new RadarDegradationAlert(
                            "gpt-5.5", "high", 96, 5.5, null)
                    ])),
            ResetRadarTitle = "官方源快车",
            ResetRadarUpdatedLabel = "事件更新 7月29日 13:42",
            ResetRadarCards =
            [
                new ResetJudgementCard(
                    "发重置卡", "未宣布",
                    "本轮是直接重置 — 当前没有新增可储存卡片。"),
                new ResetJudgementCard(
                    "硬重置", "已落地",
                    "官方重置完成 — 当前没有开启的速蹬窗口。")
            ],
            CommunityKnowledges =
            [
                new CommunityKnowledgeInfo(
                    "重置卡过期时间自查",
                    "reset credit expiry check"),
                new CommunityKnowledgeInfo(
                    "如何开启 Max 推理强度",
                    "Open Codex settings and enable Max reasoning.")
            ],
            QuotaRadar =
            [
                new QuotaEstimate(
                    "20x Pro", 276.44, 1658.63,
                    "measured 7d")
            ],
            FastRadar = new FastRadarInfo(
                "Fast 雷达",
                "7月12日16:32更新",
                "从 Standard 改成 Fast 的公开实测。",
                [
                    new FastRadarSummaryItem(
                        "体感加速", "⚡️1.381 倍"),
                    new FastRadarSummaryItem(
                        "首字减少", "0.08 秒"),
                    new FastRadarSummaryItem(
                        "TPS 加速", "⚡️1.504 倍")
                ],
                [
                    new FastRadarRow(
                        "Sol",
                        new FastRadarMetric(
                            "E2E", "47.26s → 33.79s", "⚡️1.399×"),
                        new FastRadarMetric(
                            "TTFT", "9.98s → 9.08s", "快 9.0%"),
                        new FastRadarMetric(
                            "TPS", "55.75 → 84.23", "⚡️1.511×"))
                ],
                "Standard 与 Fast 各独立运行 3 次并取平均。"),
            ResetCredits =
            [
                new ResetCredit(
                    "Codex reset credit",
                    "available",
                    now.AddDays(-1),
                    now.AddHours(2),
                    ResetCreditPrivacy.Fingerprint(
                        "visual-smoke-credit"),
                    "codexRateLimits")
            ],
            AvailableResetCredits = 1,
            ResetCreditsCheckedAt = now,
            ResetCreditProtection =
                new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Scheduled,
                    ActionAt: now.AddMinutes(90),
                    ExpiresAt: now.AddHours(2),
                    AvailableCount: 1)
        };
        var history = new QuotaHistoryTimeline(
            [
                new QuotaHistorySample(
                    now.AddHours(-23),
                    96,
                    now.AddDays(4)),
                new QuotaHistorySample(
                    now.AddHours(-23)
                        .AddMinutes(10),
                    94,
                    now.AddDays(4)),
                new QuotaHistorySample(
                    now.AddHours(-18),
                    83.5,
                    now.AddDays(4)),
                new QuotaHistorySample(
                    now.AddHours(-18)
                        .AddMinutes(10),
                    80,
                    now.AddDays(4)),
                new QuotaHistorySample(
                    now.AddHours(-12),
                    62,
                    now.AddDays(4)),
                new QuotaHistorySample(
                    now.AddHours(-5),
                    31,
                    now.AddDays(4)),
                new QuotaHistorySample(
                    now.AddHours(-5)
                        .AddMinutes(10),
                    98,
                    now.AddDays(11)),
                new QuotaHistorySample(
                    now.AddMinutes(-2),
                    74,
                    now.AddDays(11))
            ]);

        foreach (var chinese in new[] { true, false })
        foreach (var textSize in Enum.GetValues<DashboardTextSize>())
        {
            if (interactive && (!chinese || textSize != DashboardTextSize.Large)) continue;
            var settings = CreateSettings(chinese, textSize);
            var currentSnapshot = snapshot with
            {
                QuotaPacing = QuotaPacingCalculator.Calculate(
                    snapshot, settings, now)
            };
            var caseOutput = chinese && textSize == DashboardTextSize.Large
                ? outputPath
                : null;
            var caseHistory =
                chinese
                && textSize == DashboardTextSize.Medium
                    ? new QuotaHistoryTimeline()
                    : history;
            RenderCase(
                settings,
                currentSnapshot,
                caseHistory,
                storageUnavailable:
                    chinese
                    && textSize
                    == DashboardTextSize.Medium,
                caseOutput, interactive);
        }
    }

    private static AppSettings CreateSettings(
        bool chinese,
        DashboardTextSize textSize)
    {
        var settings = new AppSettings
        {
            Chinese = chinese,
            TextSize = textSize,
            StatusDisplayMode = StatusDisplayMode.TaskbarText,
            SelectedStatusMetrics =
            [
                StatusMetric.WeeklyQuota,
                StatusMetric.ShortQuota,
                StatusMetric.CodexIq
            ],
            ResetCreditProtectionEnabled = true
        };
        settings.DashboardSectionExpansion =
            DashboardLayout.NormalizeExpansion(
                Enum.GetValues<DashboardSection>().ToDictionary(
                    section => section,
                    _ => true));
        settings.DashboardSectionVisibility =
            DashboardLayout.NormalizeVisibility(null);
        settings.DashboardDisclosureVisibility =
            DashboardLayout
                .NormalizeDisclosureVisibility(null);
        settings.QuotaHistoryExpanded = true;
        settings.ModelIqDetailsExpanded = true;
        settings.RadarInsightsDetailsExpanded = true;
        settings.LayoutDiscoveryTipDismissed = true;
        return settings;
    }

    private static void RenderCase(
        AppSettings settings,
        DashboardSnapshot snapshot,
        QuotaHistoryTimeline history,
        bool storageUnavailable,
        string? outputPath, bool interactive = false)
    {
        var elapsed = System.Diagnostics.Stopwatch.StartNew();
        Console.WriteLine($"Dashboard {(settings.Chinese ? "zh" : "en")}/{settings.TextSize}: starting.");
        using var form = new DashboardForm(settings, () => snapshot.RefreshedAt)
        {
            StartPosition = FormStartPosition.CenterScreen,
            ShowInTaskbar = interactive
        };
        Exception? failure = null;
        form.Shown += (_, _) =>
        {
            try
            {
                form.SetState(
                    snapshot,
                    settings,
                    new AppUpdateStatus(AppUpdatePhase.UpToDate),
                    resetLoading: false,
                    quotaHistory: history,
                    quotaHistoryEndingAt:
                        snapshot.RefreshedAt,
                    quotaHistoryStorageUnavailable:
                        storageUnavailable);
                if (interactive) return;
                form.BeginInvoke(new Action(() =>
                {
                    try
                    {
                        WaitFor(
                            () =>
                            {
                                if (form.LastRenderFailure
                                    is { } renderFailure)
                                    throw new InvalidOperationException(
                                        "Dashboard render failed.",
                                        renderFailure);
                                return Descendants(form)
                                    .OfType<
                                        QuotaHistoryChartControl>()
                                    .Any();
                            },
                            "quota-history chart");
                        Console.WriteLine($"Initial content render: {form.LastRenderDuration.TotalMilliseconds:0} ms.");
                        form.Update();
                        form.PerformLayout();
                        form.Refresh();
                        Application.DoEvents();
                        ValidateChrome(form);
                        ValidateFooter(form, settings);
                        ValidateTextBounds(form);
                        ValidateQuotaHistory(
                            form,
                            history,
                            storageUnavailable);
                        using var bitmap = new Bitmap(
                            form.Width, form.Height);
                        form.DrawToBitmap(
                            bitmap,
                            new Rectangle(Point.Empty, form.Size));
                        ValidateBitmap(bitmap);
                        if (outputPath is not null)
                        {
                            var directory =
                                Path.GetDirectoryName(outputPath);
                            if (!string.IsNullOrWhiteSpace(directory))
                                Directory.CreateDirectory(directory);
                            bitmap.Save(
                                outputPath,
                                System.Drawing.Imaging.ImageFormat.Png);
                        }
                        ValidateRefreshAndCollapsedWarnings(form, settings, snapshot);
                        form.ShowLayoutEditor();
                        form.BeginInvoke(new Action(() =>
                        {
                            try
                            {
                                WaitFor(
                                    () =>
                                    {
                                        if (form.LastRenderFailure
                                            is { } renderFailure)
                                            throw new InvalidOperationException(
                                                "Layout render failed.",
                                                renderFailure);
                                        return Descendants(form)
                                            .Any(control =>
                                                control.Name
                                                == "layoutEditor");
                                    },
                                    "in-dashboard Layout editor");
                                form.Update();
                                form.PerformLayout();
                                form.Refresh();
                                Application.DoEvents();
                                Thread.Sleep(50);
                                Application.DoEvents();
                                ValidateChrome(form);
                                ValidateFooter(
                                    form,
                                    settings,
                                    layoutEditor: true);
                                ValidateTextBounds(form);
                                ValidateLayoutEditor(
                                    form,
                                    settings);
                                using var layoutBitmap =
                                    new Bitmap(
                                        form.Width,
                                        form.Height);
                                form.DrawToBitmap(
                                    layoutBitmap,
                                    new Rectangle(
                                        Point.Empty,
                                        form.Size));
                                ValidateBitmap(
                                    layoutBitmap);
                                if (outputPath is not null)
                                {
                                    layoutBitmap.Save(
                                        LayoutOutputPath(
                                            outputPath),
                                        System.Drawing.Imaging
                                            .ImageFormat.Png);
                                }
                            }
                            catch (Exception ex)
                            {
                                failure = ex;
                            }
                            finally
                            {
                                form.AllowClose();
                                form.Close();
                            }
                        }));
                    }
                    catch (Exception ex)
                    {
                        failure = ex;
                        form.AllowClose();
                        form.Close();
                    }
                }));
            }
            catch (Exception ex)
            {
                failure = ex;
                form.AllowClose();
                form.Close();
            }
        };
        if (interactive)
        {
            form.QuitRequested += (_, _) => form.AllowClose();
        }
        Application.Run(form);
        if (failure is not null)
            throw new InvalidOperationException(
                $"Dashboard visual smoke test failed ({(settings.Chinese ? "zh" : "en")}/{settings.TextSize}).", failure);
        Console.WriteLine($"Dashboard completed in {elapsed.Elapsed.TotalSeconds:0.0}s.");
    }

    private static void ValidateFooter(
        Control root,
        AppSettings settings,
        bool layoutEditor = false)
    {
        var expected = new HashSet<string>(
            ["refresh", "radar", "codex", "github", "layout", "quit"],
            StringComparer.Ordinal);
        var buttons = Descendants(root).OfType<Button>()
            .Where(button => expected.Contains(button.Name))
            .ToArray();
        if (buttons.Length != expected.Count)
            throw new InvalidOperationException(
                "Dashboard footer buttons are missing.");

        var flags = TextFormatFlags.SingleLine
                    | TextFormatFlags.NoPrefix
                    | TextFormatFlags.NoPadding;
        foreach (var button in buttons)
        {
            var textWidth = TextRenderer.MeasureText(
                button.Text,
                button.Font,
                new Size(int.MaxValue, int.MaxValue),
                flags).Width;
            var footer = button.Parent as TableLayoutPanel;
            if (button.ClientSize.Width < textWidth + 10
                || button.TextAlign != ContentAlignment.MiddleCenter
                || button.ClientRectangle.Width <= 0
                || button.ClientRectangle.Height <= 0
                || footer is null
                || button.Top < footer.Padding.Top
                || button.Bottom > footer.ClientSize.Height - footer.Padding.Bottom)
                throw new InvalidOperationException(
                    $"Footer button '{button.Name}' clips or misaligns its label "
                    + $"({(settings.Chinese ? "zh" : "en")}/{settings.TextSize}; "
                    + $"button={button.Bounds}; text={textWidth}px; "
                    + $"footer={footer?.ClientSize}; padding={footer?.Padding}).");
        }
        var layout = buttons.Single(
            button => button.Name == "layout");
        var expectedLayoutText = layoutEditor
            ? settings.Chinese ? "完成" : "Done"
            : settings.Chinese ? "布局" : "Layout";
        if (layout.Text != expectedLayoutText)
            throw new InvalidOperationException(
                "Dashboard Layout/Done command is out of sync.");
    }

    private static void ValidateChrome(Form form)
    {
        var titleBar = form.Controls["dashboardTitleBar"];
        var header = form.Controls[
            "dashboardHeader"];
        var content = form.Controls[
            "dashboardContentHost"];
        var footer = form.Controls[
            "dashboardFooter"];
        if (titleBar is null || !titleBar.Visible || titleBar.Top != form.Padding.Top
            || header is null
            || content is null
            || footer is null
            || !header.Visible
            || !content.Visible
            || !footer.Visible
            || header.Top != titleBar.Bottom
            || footer.Bottom
            != form.ClientSize.Height - form.Padding.Bottom
            || header.Bottom > content.Top
            || content.Bottom > footer.Top
            || header.Height < 70
            || footer.Height < 48)
            throw new InvalidOperationException(
                "Dashboard chrome overlaps or collapses "
                + $"(client={form.ClientSize}, "
                + $"header={header?.Bounds}, "
                + $"content={content?.Bounds}, "
                + $"footer={footer?.Bounds}).");
    }

    private static void ValidateTextBounds(Control root)
    {
        foreach (var control in Descendants(root).Where(item => item.Visible && item.Parent is not null))
        {
            if (control is not (Label or Button)) continue;
            if (control.Right > control.Parent!.ClientSize.Width - control.Parent.Padding.Right + 2
                || control.Left < control.Parent.Padding.Left - 2)
                throw new InvalidOperationException($"Text control exceeds its container: {control.GetType().Name}/{control.Name} "
                    + $"'{control.Text}' {control.Bounds}; parent={control.Parent.GetType().Name}/{control.Parent.ClientSize}.");
            if (control is Button button && button.Parent is FlowLayoutPanel)
            {
                var padding = (int)Math.Ceiling(12 * button.DeviceDpi / 96d);
                var measured = TextRenderer.MeasureText(button.Text, button.Font,
                    new Size(Math.Max(1, button.Width - padding), int.MaxValue),
                    TextFormatFlags.WordBreak | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
                if (measured.Height > button.Height - 4)
                    throw new InvalidOperationException("An action button clips its wrapped label.");
            }
        }
    }

    private static void ValidateRefreshAndCollapsedWarnings(DashboardForm form, AppSettings settings,
        DashboardSnapshot snapshot)
    {
        var host = form.Controls["dashboardContentHost"]!;
        var previous = host.Controls[0];
        form.SetState(snapshot with { RefreshedAt = snapshot.RefreshedAt.AddSeconds(1) }, settings,
            new AppUpdateStatus(AppUpdatePhase.UpToDate), resetLoading: false);
        Application.DoEvents();
        if (!ReferenceEquals(previous, host.Controls[0]))
            throw new InvalidOperationException("A timestamp-only refresh rebuilt the dashboard.");

        foreach (var section in Enum.GetValues<DashboardSection>())
            settings.SetDashboardSectionExpanded(section, false);
        settings.SetDashboardSectionVisible(DashboardSection.ResetCredits, false);
        settings.SetDashboardSectionVisible(DashboardSection.Updates, false);
        const string connectionWarning = "Connection unavailable — reconnect Codex and refresh.";
        form.SetState(snapshot with
        {
            LimitReached = true,
            CanConfirmWeeklyRecovery = false,
            Errors = [connectionWarning],
            ResetCreditProtection = new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Blocked,
                BlockReason: ResetCreditProtectionBlockReason.AccountChanged)
        }, settings, new AppUpdateStatus(AppUpdatePhase.Failed, Message: "Update verification failed."), false);
        WaitFor(() =>
        {
            if (form.LastRenderFailure is { } failure) throw failure;
            return !ReferenceEquals(previous, host.Controls[0]);
        }, "collapsed dashboard and forced safety warnings");
        form.PerformLayout();
        form.Refresh();
        ValidateChrome(form);
        ValidateFooter(form, settings);
        ValidateTextBounds(form);
        var labels = Descendants(form).OfType<Label>().Select(label => label.Text).ToArray();
        if (Descendants(form).OfType<QuotaHistoryChartControl>().Any()
            || !labels.Any(text => text.Contains(connectionWarning, StringComparison.Ordinal))
            || !labels.Contains(settings.Chinese ? "重置卡过期" : "Reset Credit Expiry")
            || !labels.Contains(settings.Chinese ? "应用更新" : "App Updates"))
            throw new InvalidOperationException("Collapsed layout hides a safety warning or leaves history expanded.");
    }

    private static void ValidateQuotaHistory(
        Control root,
        QuotaHistoryTimeline timeline,
        bool storageUnavailable)
    {
        var chart = Descendants(root)
            .OfType<QuotaHistoryChartControl>()
            .SingleOrDefault();
        if (chart is null
            || !chart.Visible
            || chart.ClientSize.Width < 260
            || chart.ClientSize.Height < 180)
            throw new InvalidOperationException(
                "Expanded quota history chart is missing or clipped "
                + $"(found={chart is not null}, "
                + $"visible={chart?.Visible}, "
                + $"client={chart?.ClientSize}, "
                + $"samples={timeline.Samples.Count}, "
                + $"storageUnavailable={storageUnavailable}).");
        if (timeline.Samples.Count == 0
            && !storageUnavailable)
            throw new InvalidOperationException(
                "The empty history case must retain its storage state.");
    }

    private static void ValidateLayoutEditor(
        Control root,
        AppSettings settings)
    {
        var editor = Descendants(root)
            .SingleOrDefault(control =>
                control.Name == "layoutEditor");
        if (editor is null || !editor.Visible)
            throw new InvalidOperationException(
                "In-dashboard Layout editor is missing.");
        var rows = Descendants(editor)
            .OfType<TableLayoutPanel>()
            .Where(row =>
                row.Name.StartsWith(
                    "layout-section-",
                    StringComparison.Ordinal)
                || row.Name.StartsWith(
                    "layout-disclosure-",
                    StringComparison.Ordinal))
            .ToArray();
        var expectedRows =
            Enum.GetValues<DashboardSection>().Length
            + Enum.GetValues<DashboardDisclosure>().Length;
        if (rows.Length != expectedRows)
            throw new InvalidOperationException(
                "Layout editor does not expose every section and nested item.");

        foreach (var row in rows)
        {
            if (row.ClientSize.Width <= 0
                || row.Right
                > row.Parent!.ClientSize.Width + 1)
                throw new InvalidOperationException(
                    $"Layout row '{row.Name}' is horizontally clipped "
                    + $"({(settings.Chinese ? "zh" : "en")}/{settings.TextSize}).");
            foreach (Control control in row.Controls)
            {
                if (!control.Visible) continue;
                if (control.Left < row.Padding.Left - 1
                    || control.Right
                    > row.ClientSize.Width
                    - row.Padding.Right + 1
                    || control.Top < row.Padding.Top - 1
                    || control.Bottom
                    > row.ClientSize.Height
                    - row.Padding.Bottom + 1)
                    throw new InvalidOperationException(
                        $"Layout control '{control.Name}' overflows "
                        + $"'{row.Name}' ({control.Bounds} in {row.ClientSize}; "
                        + $"{(settings.Chinese ? "zh" : "en")}/{settings.TextSize}).");
                if (control is CheckBox checkBox)
                {
                    var preferred =
                        checkBox.GetPreferredSize(
                            Size.Empty);
                    if (checkBox.ClientSize.Width
                        < preferred.Width)
                        throw new InvalidOperationException(
                            $"Layout checkbox '{checkBox.Text}' clips.");
                }
                if (string.IsNullOrWhiteSpace(
                        control.AccessibleName)
                    && control.Name is
                        "show" or "startOpen"
                        or "moveUp" or "moveDown")
                    throw new InvalidOperationException(
                        $"Layout control '{control.Name}' lacks an accessible label.");
            }
        }
    }

    private static string LayoutOutputPath(
        string dashboardOutputPath)
    {
        var extension = Path.GetExtension(
            dashboardOutputPath);
        var withoutExtension =
            dashboardOutputPath[..^extension.Length];
        return withoutExtension
               + "-layout"
               + extension;
    }

    private static void WaitFor(
        Func<bool> predicate,
        string description)
    {
        var deadline = Environment.TickCount64
                       + 5_000;
        while (!predicate())
        {
            if (Environment.TickCount64
                >= deadline)
                throw new TimeoutException(
                    $"Timed out waiting for {description}.");
            Application.DoEvents();
            Thread.Sleep(10);
        }
    }

    private static void ValidateBitmap(Bitmap bitmap)
    {
        var colors = new HashSet<int>();
        for (var y = 0; y < bitmap.Height; y += 20)
        for (var x = 0; x < bitmap.Width; x += 20)
            colors.Add(bitmap.GetPixel(x, y).ToArgb());
        if (colors.Count < 8)
            throw new InvalidOperationException(
                "Rendered dashboard is unexpectedly blank.");
    }

    private static IEnumerable<Control> Descendants(Control root)
    {
        foreach (Control child in root.Controls)
        {
            yield return child;
            foreach (var descendant in Descendants(child))
                yield return descendant;
        }
    }
}
