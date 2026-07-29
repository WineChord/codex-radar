using System.Diagnostics;
using System.Drawing.Drawing2D;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexRadar.Windows;

internal sealed class DashboardForm : Form
{
    private static readonly JsonSerializerOptions ContentSignatureJson = new()
    {
        NumberHandling = JsonNumberHandling.AllowNamedFloatingPointLiterals
    };
    private const string RadarUrl = "https://codexradar.com/";
    private const string CodexWebUrl = "https://chatgpt.com/codex";
    private const string RepositoryUrl = "https://github.com/WineChord/codex-radar";
    private const string SafeResetCreditPromptZh =
        "请用本机 Codex 凭证查询 rate-limit reset credits。读取 %USERPROFILE%\\.codex\\auth.json 中的 tokens.access_token，" +
        "请求 https://chatgpt.com/backend-api/wham/rate-limit-reset-credits。若返回 401，请说明凭证失效或 Authorization header 不正确；" +
        "不要打印 access_token、refresh_token、cookie 或完整唯一 ID；只展示每张重置卡的发放时间和过期时间，" +
        "将 UTC 转为本地时间，并用中文回复。";
    private const string SafeResetCreditPromptEn =
        "Use my local Codex credentials to check rate-limit reset credits from %USERPROFILE%\\.codex\\auth.json " +
        "tokens.access_token via https://chatgpt.com/backend-api/wham/rate-limit-reset-credits. If it returns 401, explain that the credential " +
        "is expired or the Authorization header is missing. Do not print access_token, refresh_token, cookies, or full unique IDs. " +
        "Show only each reset credit issue time and expiry time, converted to local time.";

    private readonly Panel _header = new() { Name = "dashboardHeader", Dock = DockStyle.Top, Height = 92, Padding = new Padding(18, 13, 18, 10) };
    private readonly Label _title = new() { AutoSize = true, ForeColor = Color.White };
    private readonly Label _detail = new() { AutoSize = true, ForeColor = Color.White };
    private readonly Label _summary = new() { AutoSize = true, ForeColor = Color.White };
    private readonly Label _updated = new() { AutoSize = true, ForeColor = Color.FromArgb(224, 235, 246) };
    private readonly TableLayoutPanel _headerLayout = new()
    {
        Dock = DockStyle.Fill,
        RowCount = 3,
        ColumnCount = 2,
        BackColor = Color.Transparent,
        Margin = Padding.Empty,
        Padding = Padding.Empty
    };
    private readonly BufferedPanel _contentHost = new()
    {
        Name = "dashboardContentHost",
        Dock = DockStyle.Fill,
        BackColor = Color.FromArgb(244, 246, 248)
    };
    private BufferedFlowLayoutPanel _content = CreateContentPanel();
    private readonly TableLayoutPanel _footer = new()
    {
        Name = "dashboardFooter",
        Dock = DockStyle.Bottom,
        Height = 60,
        ColumnCount = 6,
        RowCount = 1,
        Padding = new Padding(8, 8, 8, 10),
        BackColor = Color.FromArgb(248, 249, 251),
        GrowStyle = TableLayoutPanelGrowStyle.FixedSize
    };

    private AppSettings _settings;
    private DashboardSnapshot _snapshot = new();
    private QuotaHistoryTimeline _quotaHistory = new();
    private DateTimeOffset _quotaHistoryEndingAt =
        DateTimeOffset.Now;
    private bool _quotaHistoryStorageUnavailable;
    private AppUpdateStatus _updateStatus = new(AppUpdatePhase.Idle);
    private bool _resetLoading;
    private bool _allowClose;
    private bool _customizesLayout;
    private DashboardTextSize? _appliedTextSize;
    private StatusBarHorizontalPadding? _appliedPadding;
    private StatusBarFontScale? _appliedFontScale;
    private int _appliedDpi;
    private Size _preferredSize;
    private int _headerLayoutWidth = -1;
    private System.Windows.Forms.Timer? _transientTimer;
    private bool _contentRendered;
    private bool _renderPending = true;
    private bool _renderScheduled;
    private string? _renderedContentSignature;
    private string? _pendingContentSignature;
    internal Exception? LastRenderFailure { get; private set; }

    public event EventHandler? RefreshRequested;
    public event EventHandler? ResetCreditsRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? CheckUpdatesRequested;
    public event EventHandler? DismissSpeedRequested;
    public event EventHandler? SettingsChanged;
    public event EventHandler? ProtectionEnableRequested;
    public event EventHandler? ProtectionDisableRequested;
    public event EventHandler? ProtectionPreviewRequested;
    public event EventHandler? QuitRequested;

    public DashboardForm(AppSettings settings)
    {
        SuspendLayout();
        _settings = settings;
        AutoScaleDimensions = new SizeF(96f, 96f);
        AutoScaleMode = AutoScaleMode.Dpi;
        FormBorderStyle = FormBorderStyle.SizableToolWindow;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        MinimumSize = new Size(390, 560);
        MaximumSize = new Size(620, 980);
        Text = "Codex Radar Sentinel";
        BackColor = Color.White;
        DoubleBuffered = true;
        KeyPreview = true;

        BuildHeader();
        BuildFooter();
        _contentHost.Controls.Add(_content);
        Controls.Add(_contentHost);
        Controls.Add(_header);
        Controls.Add(_footer);

        Resize += (_, _) =>
        {
            LayoutHeader();
            ResizeCards();
        };
        FormClosing += OnFormClosing;
        KeyDown += (_, e) =>
        {
            if (e.KeyCode == Keys.Escape)
            {
                Hide();
                e.Handled = true;
            }
        };
        ApplyTextSize(force: true);
        RenderChrome();
        AddLoadingPlaceholder();
        ResumeLayout(true);
    }

    public DashboardForm(bool chinese) : this(new AppSettings { Chinese = chinese }) { }

    public void SetState(
        DashboardSnapshot snapshot,
        AppSettings settings,
        AppUpdateStatus updateStatus,
        bool resetLoading,
        QuotaHistoryTimeline? quotaHistory = null,
        DateTimeOffset? quotaHistoryEndingAt = null,
        bool? quotaHistoryStorageUnavailable = null)
    {
        if (IsDisposed || Disposing) return;
        if (InvokeRequired)
        {
            if (!IsHandleCreated) return;
            try
            {
                BeginInvoke(() => SetState(
                    snapshot,
                    settings,
                    updateStatus,
                    resetLoading,
                    quotaHistory,
                    quotaHistoryEndingAt,
                    quotaHistoryStorageUnavailable));
            }
            catch (InvalidOperationException)
            {
            }
            return;
        }

        _snapshot = snapshot;
        _settings = settings;
        _updateStatus = updateStatus;
        _resetLoading = resetLoading;
        if (quotaHistory is not null)
            _quotaHistory = quotaHistory;
        if (quotaHistoryEndingAt is { } historyEndingAt)
            _quotaHistoryEndingAt = historyEndingAt;
        if (quotaHistoryStorageUnavailable is { } storageUnavailable)
            _quotaHistoryStorageUnavailable = storageUnavailable;
        ApplyTextSize();
        _pendingContentSignature = BuildContentSignature(
            snapshot,
            settings,
            updateStatus,
            resetLoading,
            quotaHistory: _quotaHistory,
            quotaHistoryEndingAt:
                _quotaHistoryEndingAt,
            quotaHistoryStorageUnavailable:
                _quotaHistoryStorageUnavailable,
            customizesLayout:
                _customizesLayout);
        _renderPending = !_contentRendered
                         || !string.Equals(_renderedContentSignature, _pendingContentSignature, StringComparison.Ordinal);
        RenderChrome();
        if (IsHandleCreated && Visible) ScheduleRender();
    }

    public void SetSnapshot(DashboardSnapshot snapshot, bool chinese)
    {
        _settings.Chinese = chinese;
        SetState(snapshot, _settings, _updateStatus, _resetLoading);
    }

    public void ShowNearTray()
    {
        var cursor = Cursor.Position;
        var screen = Screen.FromPoint(cursor);
        var area = screen.WorkingArea;
        var bounds = screen.Bounds;

        // Ensure DeviceDpi is real, then move the hidden native window onto the
        // target monitor before deriving its preferred physical size.
        _ = Handle;
        var seedWidth = Math.Min(Math.Max(1, Width), area.Width);
        var seedHeight = Math.Min(Math.Max(1, Height), area.Height);
        Location = new Point(
            Math.Clamp(cursor.X - seedWidth / 2, area.Left, Math.Max(area.Left, area.Right - seedWidth)),
            Math.Clamp(cursor.Y - seedHeight / 2, area.Top, Math.Max(area.Top, area.Bottom - seedHeight)));
        // Moving to a monitor with a different DPI invokes OnDpiChanged, which
        // reapplies the logical metrics. On the common same-monitor path this
        // avoids recreating fonts and triggering several full layout passes.
        ApplyTextSize();

        var preferred = _preferredSize.IsEmpty ? Size : _preferredSize;
        var desiredWidth = Math.Min(preferred.Width, area.Width);
        var desiredHeight = Math.Min(preferred.Height, area.Height);
        var minimum = ScaleLogical(new Size(390, 560));
        minimum.Width = Math.Max(minimum.Width, FooterMinimumClientWidth() + Math.Max(0, Width - ClientSize.Width));
        MinimumSize = new Size(Math.Min(minimum.Width, area.Width), Math.Min(minimum.Height, area.Height));
        if (Size != new Size(desiredWidth, desiredHeight)) Size = new Size(desiredWidth, desiredHeight);

        var gaps = new List<(string Edge, int Size, int Distance)>
        {
            ("top", area.Top - bounds.Top, Math.Abs(cursor.Y - bounds.Top)),
            ("bottom", bounds.Bottom - area.Bottom, Math.Abs(bounds.Bottom - cursor.Y)),
            ("left", area.Left - bounds.Left, Math.Abs(cursor.X - bounds.Left)),
            ("right", bounds.Right - area.Right, Math.Abs(bounds.Right - cursor.X))
        };
        var taskbar = gaps.Where(item => item.Size > 0).OrderBy(item => item.Distance).FirstOrDefault();
        var edge = taskbar.Size > 0 ? taskbar.Edge : ClosestEdge(cursor, bounds);

        var x = Math.Clamp(cursor.X - Width / 2, area.Left, Math.Max(area.Left, area.Right - Width));
        var y = Math.Clamp(cursor.Y - Height / 2, area.Top, Math.Max(area.Top, area.Bottom - Height));
        switch (edge)
        {
            case "top":
                y = area.Top;
                break;
            case "left":
                x = area.Left;
                break;
            case "right":
                x = area.Right - Width;
                break;
            default:
                y = area.Bottom - Height;
                break;
        }

        Location = new Point(x, y);
        if (!Visible) Show();
        WindowState = FormWindowState.Normal;
        if (_footer.GetControlFromPosition(0, 0) is { CanSelect: true } firstCommand)
            ActiveControl = firstCommand;
        _content.AutoScrollPosition = Point.Empty;
        Activate();
        BringToFront();
        // Paint the lightweight chrome before building the dynamic card tree.
        // This keeps the tray click responsive even on first use/high DPI.
        Update();
        _header.Refresh();
        _footer.Refresh();
        _content.Refresh();
        ScheduleRender();
        try
        {
            BeginInvoke(() =>
            {
                if (!IsDisposed && !_content.IsDisposed)
                    _content.AutoScrollPosition = Point.Empty;
            });
        }
        catch (InvalidOperationException) { }
    }

    public void AllowClose()
    {
        _allowClose = true;
        Close();
    }

    private void BuildHeader()
    {
        _header.Controls.Add(_headerLayout);
        _header.ClientSizeChanged += (_, _) =>
        {
            if (_header.ClientSize.Width != _headerLayoutWidth) LayoutHeader();
        };
        LayoutHeader();
    }

    private void LayoutHeader()
    {
        _headerLayoutWidth = _header.ClientSize.Width;
        var availableWidth = Math.Max(1, _header.ClientSize.Width - _header.Padding.Horizontal);
        var stackSummary = _title.PreferredSize.Width + _summary.PreferredSize.Width + ScaleLogical(12) > availableWidth;

        _headerLayout.SuspendLayout();
        try
        {
            _headerLayout.Controls.Clear();
            _headerLayout.ColumnStyles.Clear();
            _headerLayout.RowStyles.Clear();
            _headerLayout.ColumnCount = 2;
            _headerLayout.RowCount = stackSummary ? 4 : 3;
            _headerLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            _headerLayout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            for (var row = 0; row < _headerLayout.RowCount; row++)
                _headerLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));

            _summary.Anchor = AnchorStyles.Top | AnchorStyles.Right;
            _headerLayout.Controls.Add(_title, 0, 0);
            if (stackSummary)
            {
                _headerLayout.SetColumnSpan(_title, 2);
                _headerLayout.Controls.Add(_summary, 0, 1);
                _headerLayout.SetColumnSpan(_summary, 2);
                _headerLayout.Controls.Add(_detail, 0, 2);
                _headerLayout.Controls.Add(_updated, 0, 3);
            }
            else
            {
                _headerLayout.SetColumnSpan(_title, 1);
                _headerLayout.Controls.Add(_summary, 1, 0);
                _headerLayout.SetColumnSpan(_summary, 1);
                _headerLayout.Controls.Add(_detail, 0, 1);
                _headerLayout.Controls.Add(_updated, 0, 2);
            }
            _headerLayout.SetColumnSpan(_detail, 2);
            _headerLayout.SetColumnSpan(_updated, 2);
        }
        finally
        {
            _headerLayout.ResumeLayout(true);
        }

        var baseline = ScaleLogical(_settings.TextSize == DashboardTextSize.ExtraLarge ? 106 : 92);
        var preferred = _headerLayout.GetPreferredSize(new Size(availableWidth, 0));
        var desiredHeight = Math.Max(baseline, preferred.Height + _header.Padding.Vertical);
        if (_header.Height != desiredHeight) _header.Height = desiredHeight;
    }

    private void BuildFooter()
    {
        _footer.RowStyles.Add(new RowStyle(SizeType.Percent, 100f));
        for (var i = 0; i < _footer.ColumnCount; i++)
            _footer.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / _footer.ColumnCount));

        _footer.ClientSizeChanged += (_, _) => LayoutFooterButtons();

        AddFooterButton("刷新", "refresh", 0, (_, _) => RefreshRequested?.Invoke(this, EventArgs.Empty));
        AddFooterButton("Radar", "radar", 1, (_, _) => Open(RadarUrl));
        AddFooterButton("Codex", "codex", 2, (_, _) => OpenCodex());
        AddFooterButton("GitHub", "github", 3, (_, _) => Open(RepositoryUrl));
        AddFooterButton(
            "布局",
            "layout",
            4,
            (_, _) => SetLayoutEditorVisible(
                !_customizesLayout));
        AddFooterButton("退出", "quit", 5, (_, _) => QuitRequested?.Invoke(this, EventArgs.Empty));
        LayoutFooterButtons();
    }

    private void AddFooterButton(string text, string name, int column, EventHandler handler)
    {
        var button = new FluentButton
        {
            Text = text,
            Name = name,
            Dock = DockStyle.Fill,
            ForeColor = Color.FromArgb(32, 33, 36),
            Margin = new Padding(3),
            TabStop = true,
            TextAlign = ContentAlignment.MiddleCenter,
            UseMnemonic = false,
            AutoEllipsis = false
        };
        button.Click += handler;
        _footer.Controls.Add(button, column, 0);
    }

    private void LayoutFooterButtons()
    {
        if (_footer.ClientSize.Width <= _footer.Padding.Horizontal) return;
        var buttons = Enumerable.Range(0, _footer.ColumnCount)
            .Select(column => _footer.GetControlFromPosition(column, 0))
            .OfType<FluentButton>()
            .ToArray();
        if (buttons.Length != _footer.ColumnCount) return;

        var flags = TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;
        var minimumWidths = buttons.Select(button =>
            TextRenderer.MeasureText(button.Text, button.Font, new Size(int.MaxValue, int.MaxValue), flags).Width
            + ScaleLogical(18) + button.Margin.Horizontal).ToArray();
        var available = _footer.ClientSize.Width - _footer.Padding.Horizontal;
        var remaining = Math.Max(0, available - minimumWidths.Sum());

        _footer.SuspendLayout();
        try
        {
            _footer.ColumnStyles.Clear();
            for (var index = 0; index < minimumWidths.Length; index++)
            {
                var share = remaining / (minimumWidths.Length - index);
                remaining -= share;
                _footer.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, minimumWidths[index] + share));
            }
        }
        finally { _footer.ResumeLayout(true); }
    }

    private int FooterMinimumClientWidth()
    {
        var flags = TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;
        return _footer.Controls.OfType<FluentButton>().Sum(button =>
                   TextRenderer.MeasureText(button.Text, button.Font, new Size(int.MaxValue, int.MaxValue), flags).Width
                   + ScaleLogical(18) + button.Margin.Horizontal)
               + _footer.Padding.Horizontal;
    }

    private void ApplyTextSize(bool force = false)
    {
        if (!force && _appliedTextSize == _settings.TextSize && _appliedPadding == _settings.HorizontalPadding
            && _appliedFontScale == _settings.FontScale && _appliedDpi == DeviceDpi) return;
        _appliedTextSize = _settings.TextSize;
        _appliedPadding = _settings.HorizontalPadding;
        _appliedFontScale = _settings.FontScale;
        _appliedDpi = DeviceDpi;
        var metrics = _settings.TextSize switch
        {
            DashboardTextSize.Medium => (Width: 430, Height: 690, Body: 8.8f, Header: 13.5f),
            DashboardTextSize.ExtraLarge => (Width: 535, Height: 900, Body: 11f, Header: 16.5f),
            _ => (Width: 480, Height: 800, Body: 9.8f, Header: 15f)
        };
        MaximumSize = ScaleLogical(new Size(620, 980));
        MinimumSize = ScaleLogical(new Size(390, 560));
        ClientSize = ScaleLogical(new Size(metrics.Width, metrics.Height));
        _preferredSize = Size;
        Font = new Font("Segoe UI", metrics.Body);
        _title.Font = new Font("Segoe UI Semibold", metrics.Header, FontStyle.Bold);
        _detail.Font = new Font("Segoe UI", metrics.Body);
        var summarySize = _settings.FontScale switch
        {
            StatusBarFontScale.Compact => metrics.Body,
            StatusBarFontScale.Tiny => Math.Max(7.5f, metrics.Body - .8f),
            _ => metrics.Body + .7f
        };
        _summary.Font = new Font("Consolas", summarySize, FontStyle.Bold);
        var headerSidePadding = _settings.HorizontalPadding switch
        {
            StatusBarHorizontalPadding.Compact => 12,
            StatusBarHorizontalPadding.Tight => 8,
            _ => 18
        };
        _header.Padding = ScaleLogical(new Padding(headerSidePadding, 13, headerSidePadding, 10));
        _updated.Font = new Font("Segoe UI", Math.Max(8f, metrics.Body - 1.2f));
        _header.Height = ScaleLogical(_settings.TextSize == DashboardTextSize.ExtraLarge ? 106 : 92);
        _footer.Height = ScaleLogical(_settings.TextSize == DashboardTextSize.ExtraLarge ? 72 : 64);
        var nonClientWidth = Math.Max(0, Width - ClientSize.Width);
        MinimumSize = new Size(Math.Max(MinimumSize.Width, FooterMinimumClientWidth() + nonClientWidth), MinimumSize.Height);
        LayoutFooterButtons();
        LayoutHeader();
    }

    private static BufferedFlowLayoutPanel CreateContentPanel() => new()
    {
        Dock = DockStyle.Fill,
        AutoScroll = true,
        FlowDirection = FlowDirection.TopDown,
        WrapContents = false,
        Padding = new Padding(12, 12, 12, 8),
        BackColor = Color.FromArgb(244, 246, 248)
    };

    internal static string BuildContentSignature(
        DashboardSnapshot snapshot,
        AppSettings settings,
        AppUpdateStatus updateStatus,
        bool resetLoading,
        DateTimeOffset? now = null,
        QuotaHistoryTimeline? quotaHistory = null,
        DateTimeOffset? quotaHistoryEndingAt = null,
        bool quotaHistoryStorageUnavailable = false,
        bool customizesLayout = false)
    {
        var pacing = snapshot.QuotaPacing;
        var stableSnapshot = snapshot with
        {
            RefreshedAt = DateTimeOffset.UnixEpoch,
            QuotaObservedAt = DateTimeOffset.UnixEpoch,
            // Pacing is calculated continuously. Only its rounded, rendered
            // values should trigger a card-tree replacement.
            QuotaPacing = null
        };
        var current = now ?? DateTimeOffset.Now;
        var rendersQuotaHistory =
            !customizesLayout
            && settings.IsDashboardSectionVisible(
                DashboardSection.Quota)
            && settings.IsDashboardSectionExpanded(
                DashboardSection.Quota)
            && settings.IsDashboardDisclosureVisible(
                DashboardDisclosure.QuotaHistory)
            && settings.IsDashboardDisclosureExpanded(
                DashboardDisclosure.QuotaHistory);
        return JsonSerializer.Serialize(new
        {
            Snapshot = stableSnapshot,
            Pacing = pacing is null ? null : new
            {
                pacing.Strategy,
                pacing.RoundedCurrentUsed,
                pacing.RoundedTargetUsed,
                pacing.RoundedCurrentRemaining,
                pacing.RoundedTargetRemaining,
                pacing.RoundedRemainingDelta,
                pacing.RoundedElapsed,
                pacing.Status
            },
            Settings = new
            {
                settings.Chinese,
                settings.TextSize,
                settings.StatusDisplayMode,
                settings.PreciseIq,
                settings.IqDisplayMode,
                settings.ShowPercentSymbol,
                settings.Separator,
                settings.HorizontalPadding,
                settings.FontScale,
                DashboardSectionOrder = settings.DashboardSectionOrder.ToArray(),
                DashboardSectionExpansion = settings.DashboardSectionExpansion
                    .OrderBy(item => item.Key)
                    .ToArray(),
                DashboardSectionVisibility =
                    settings.DashboardSectionVisibility
                        .OrderBy(item => item.Key)
                        .ToArray(),
                DashboardDisclosureVisibility =
                    settings.DashboardDisclosureVisibility
                        .OrderBy(item => item.Key)
                        .ToArray(),
                settings.QuotaHistoryExpanded,
                settings.QuotaHistoryRange,
                settings.ModelIqDetailsExpanded,
                settings.RadarInsightsDetailsExpanded,
                settings.LayoutDiscoveryTipDismissed,
                settings.PacingStrategy,
                settings.UseChinaHolidays,
                SelectedStatusMetrics = settings.SelectedStatusMetrics.ToArray(),
                settings.PredictionNotifications,
                settings.IqNotifications,
                settings.NotificationSound,
                settings.AutomaticUpdates,
                settings.AutoResetCreditCheck,
                settings.ResetCreditProtectionEnabled,
                settings.Preview,
                settings.DismissedSpeedAlertKey
            },
            Update = new
            {
                updateStatus.Phase,
                updateStatus.Version,
                updateStatus.Message,
                ReleaseUrl = updateStatus.ReleaseUrl?.AbsoluteUri
            },
            ResetLoading = resetLoading,
            CustomizesLayout = customizesLayout,
            QuotaHistory = quotaHistory is null
                           || !rendersQuotaHistory
                ? null
                : new
                {
                    quotaHistory.Samples.Count,
                    First = quotaHistory.Samples
                        .FirstOrDefault()?.Timestamp,
                    Last = quotaHistory.Samples
                        .LastOrDefault()?.Timestamp,
                    quotaHistoryStorageUnavailable,
                    EndingAt = quotaHistoryEndingAt?
                        .ToUnixTimeSeconds()
                        / 60
                },
            ResetCreditTime = snapshot.ResetCredits.Select(credit => ResetCreditTemporalKey(credit, current)).ToArray()
        }, ContentSignatureJson);
    }

    private static string ResetCreditTemporalKey(ResetCredit credit, DateTimeOffset now)
    {
        var normalized = credit.Status?.ToLowerInvariant() ?? "";
        if (credit.RedeemedAt is not null || normalized.Contains("redeem", StringComparison.Ordinal))
            return "used";
        if (credit.ExpiresAt is not { } expiry) return "no-expiry";
        var span = expiry - now;
        if (span <= TimeSpan.Zero) return "expired";
        var soon = span < TimeSpan.FromDays(3) ? "soon" : "normal";
        if (span.TotalDays >= 1) return $"{soon}:d:{(int)span.TotalDays}:{span.Hours}";
        if (span.TotalHours >= 1) return $"{soon}:h:{(int)span.TotalHours}:{span.Minutes}";
        return $"{soon}:m:{Math.Max(1, span.Minutes)}";
    }

    private void Render()
    {
        if (!_renderPending) return;

        var renderedSignature = _pendingContentSignature
                                ?? BuildContentSignature(
                                    _snapshot,
                                    _settings,
                                    _updateStatus,
                                    _resetLoading,
                                    quotaHistory:
                                        _quotaHistory,
                                     quotaHistoryEndingAt:
                                         _quotaHistoryEndingAt,
                                     quotaHistoryStorageUnavailable:
                                         _quotaHistoryStorageUnavailable,
                                     customizesLayout:
                                         _customizesLayout);
        var previousContent = _content;
        var scrollPosition = new Point(
            -previousContent.AutoScrollPosition.X,
            -previousContent.AutoScrollPosition.Y);
        var candidate = CreateContentPanel();
        candidate.Bounds = _contentHost.ClientRectangle;
        candidate.Visible = false;
        candidate.SuspendLayout();
        _content = candidate;
        var swapCompleted = false;

        try
        {
            LastRenderFailure = null;
            RenderChrome();

            if (ShouldEmphasizeSpeed()) AddSpeedBanner();
            AddErrorsCard();
            if (_customizesLayout)
            {
                AddAttentionSectionForLayoutEditor(
                    DashboardSection.ResetCredits);
                AddAttentionSectionForLayoutEditor(
                    DashboardSection.Updates);
                AddLayoutEditor();
            }
            else
            {
                foreach (var section in DashboardLayout.NormalizeOrder(
                             _settings.DashboardSectionOrder))
                    AddDashboardSection(section);
            }
            if (!_customizesLayout
                && !_settings.LayoutDiscoveryTipDismissed)
                AddLayoutDiscoveryTip();

            ResizeCards();
            candidate.ResumeLayout(true);
            candidate.PerformLayout();

            // Keep the live tree intact until the replacement has been fully
            // constructed. The UI thread cannot paint between these synchronous
            // operations, so the user sees either the old complete tree or the
            // new complete tree, never an empty intermediate panel.
            _contentHost.SuspendLayout();
            try
            {
                _contentHost.Controls.Add(candidate);
                candidate.Dock = DockStyle.Fill;
                candidate.Visible = true;
                candidate.BringToFront();
                previousContent.Visible = false;
                _contentHost.Controls.Remove(previousContent);
                swapCompleted = true;
            }
            finally
            {
                _contentHost.ResumeLayout(true);
            }

            candidate.AutoScrollPosition = scrollPosition;
            previousContent.Dispose();
            _contentRendered = true;
            _renderedContentSignature = renderedSignature;
            _renderPending = !string.Equals(
                _renderedContentSignature, _pendingContentSignature, StringComparison.Ordinal);
            _contentHost.Invalidate(true);
        }
        catch (Exception ex)
        {
            LastRenderFailure = ex;
            Trace.WriteLine($"Dashboard render retained the previous content after an error: {ex}");
            if (swapCompleted)
            {
                _content = candidate;
                candidate.Visible = true;
                _contentRendered = true;
                _renderedContentSignature = renderedSignature;
                _renderPending = !string.Equals(
                    _renderedContentSignature, _pendingContentSignature, StringComparison.Ordinal);
                if (!previousContent.IsDisposed) previousContent.Dispose();
                return;
            }
            if (!candidate.IsDisposed)
            {
                try { candidate.ResumeLayout(false); } catch { }
                if (candidate.Parent is not null) candidate.Parent.Controls.Remove(candidate);
                candidate.Dispose();
            }
            _content = previousContent;
            if (!previousContent.IsDisposed)
            {
                if (previousContent.Parent is null)
                {
                    _contentHost.Controls.Add(previousContent);
                    previousContent.Dock = DockStyle.Fill;
                    previousContent.BringToFront();
                }
                previousContent.Visible = true;
            }
            _renderPending = true;
        }
    }

    private void RenderChrome()
    {
        _header.BackColor = HeaderColor();
        _title.Text = ActionText();
        _detail.Text = HeaderDetailText();
        _summary.Text = _snapshot.CompactTitle(_settings);
        _updated.Text = UpdatedText();
        SetFooterText("refresh", T("刷新", "Refresh"));
        SetFooterText(
            "layout",
            _customizesLayout
                ? T("完成", "Done")
                : T("布局", "Layout"));
        SetFooterText("quit", T("退出", "Quit"));
        LayoutFooterButtons();
        LayoutHeader();
    }

    private void AddLoadingPlaceholder()
    {
        _content.Controls.Add(new Label
        {
            AutoSize = true,
            Text = T("正在读取 Codex 额度与雷达数据…", "Reading Codex quota and radar data…"),
            ForeColor = Palette.Secondary,
            Margin = new Padding(10, 10, 10, 4),
            Padding = new Padding(4)
        });
    }

    private void ScheduleRender()
    {
        if (!_renderPending || _renderScheduled || !Visible || !IsHandleCreated || IsDisposed || Disposing) return;
        _renderScheduled = true;
        try
        {
            BeginInvoke(() =>
            {
                _renderScheduled = false;
                if (_renderPending && Visible && !IsDisposed && !Disposing) Render();
            });
        }
        catch (InvalidOperationException)
        {
            _renderScheduled = false;
        }
    }

    private void AddDashboardSection(DashboardSection section)
    {
        if (!DashboardSectionHasContent(section)) return;
        var resolution = DashboardLayout.Resolve(
            section,
            _settings.IsDashboardSectionVisible(section),
            _settings.IsDashboardSectionExpanded(section),
            _snapshot.ResetCreditProtection,
            _updateStatus.Phase == AppUpdatePhase.Failed);
        if (!resolution.IsVisible)
            return;
        if (!resolution.IsExpanded)
        {
            AddCollapsedDashboardSection(section);
            return;
        }

        var firstNewControl = _content.Controls.Count;
        switch (section)
        {
            case DashboardSection.Quota:
                AddQuotaCard();
                break;
            case DashboardSection.ModelIq:
                AddIqCard();
                break;
            case DashboardSection.ResetCredits:
                AddCommunityAndCreditsCard();
                break;
            case DashboardSection.UsagePace:
                AddPacingCard();
                break;
            case DashboardSection.Insights:
                AddRadarInsightsCard();
                break;
            case DashboardSection.RadarDetails:
                AddAnnouncement();
                AddResetJudgementCard();
                AddPublicQuotaRadarCard();
                AddRadarStatusCard();
                AddPredictionCard();
                break;
            case DashboardSection.TaskbarGuide:
                AddStatusLegend();
                break;
            case DashboardSection.DisplayAndAlerts:
                AddSettingsCard();
                break;
            case DashboardSection.Updates:
                AddUpdateCard();
                break;
            case DashboardSection.Preview:
                AddPreviewCard();
                break;
        }
        if (resolution.CanCollapse && _content.Controls.Count > firstNewControl
                            && _content.Controls[_content.Controls.Count - 1] is Control lastCard
                            && lastCard.Tag is TableLayoutPanel lastBody)
        {
            AddButtonRow(lastBody, (T("收起此模块", "Collapse section"), () =>
            {
                _settings.SetDashboardSectionExpanded(section, false);
                SettingsChanged?.Invoke(this, EventArgs.Empty);
            }));
        }
    }

    private void AddAttentionSectionForLayoutEditor(
        DashboardSection section)
    {
        var resolution = DashboardLayout.Resolve(
            section,
            preferredVisible: false,
            preferredExpanded: false,
            _snapshot.ResetCreditProtection,
            _updateStatus.Phase == AppUpdatePhase.Failed);
        if (resolution.IsVisible)
            AddDashboardSection(section);
    }

    private bool DashboardSectionHasContent(DashboardSection section) => section switch
    {
        DashboardSection.ModelIq => _snapshot.IqScore is not null || _snapshot.Comparisons.Count > 0,
        DashboardSection.Insights => _snapshot.RadarInsights?.Recommendations
                                         .Any(group => group.ValidItems.Count > 0) == true
                                     || _snapshot.RadarInsights?.DegradationAlerts.ValidItems.Count > 0,
        DashboardSection.RadarDetails => !string.IsNullOrWhiteSpace(_snapshot.Announcement)
                                         || _snapshot.ResetRadarCards.Count > 0
                                         || !string.IsNullOrWhiteSpace(_snapshot.ResetRadar)
                                         || _snapshot.QuotaRadar.Count > 0
                                         || !string.IsNullOrWhiteSpace(_snapshot.RadarStatus)
                                         || _snapshot.Prediction is not null,
        _ => true
    };

    private void AddCollapsedDashboardSection(DashboardSection section)
    {
        var panel = CreateCard(DashboardSectionLabel(section), Palette.Gray,
            Color.FromArgb(249, 250, 251));
        var body = Body(panel);
        AddKeyValue(body, T("摘要", "Summary"), DashboardSectionSummary(section));
        AddButtonRow(body, (T("展开", "Expand"), () =>
        {
            _settings.SetDashboardSectionExpanded(section, true);
            SettingsChanged?.Invoke(this, EventArgs.Empty);
        }));
        AddPanel(panel);
    }

    private string DashboardSectionLabel(DashboardSection section) => section switch
    {
        DashboardSection.Quota => T("Codex 额度", "Codex Quota"),
        DashboardSection.ModelIq => "Codex IQ",
        DashboardSection.ResetCredits => T("重置卡与自动使用", "Reset credits & auto-use"),
        DashboardSection.UsagePace => T("用量节奏", "Usage Pace"),
        DashboardSection.Insights => T("CodexRadar 智能洞察", "CodexRadar Insights"),
        DashboardSection.RadarDetails => T("更多 CodexRadar 信息", "More from CodexRadar"),
        DashboardSection.TaskbarGuide => T("状态栏说明", "Taskbar guide"),
        DashboardSection.DisplayAndAlerts => T("显示与提醒", "Display & alerts"),
        DashboardSection.Updates => T("版本更新", "Updates"),
        DashboardSection.Preview => T("调试预览", "Preview"),
        _ => section.ToString()
    };

    private string LayoutEditorLabel(
        DashboardSection section) =>
        !_settings.Chinese
            ? section switch
            {
                DashboardSection.ResetCredits =>
                    "Reset credits",
                DashboardSection.Insights =>
                    "Insights",
                DashboardSection.RadarDetails =>
                    "Radar details",
                _ => DashboardSectionLabel(section)
            }
            : DashboardSectionLabel(section);

    private string DisclosureEditorLabel(
        DashboardDisclosure disclosure) => disclosure switch
    {
        DashboardDisclosure.QuotaHistory =>
            T("额度历史", "Quota history"),
        DashboardDisclosure.ModelIqDetails =>
            T("全部模型 IQ", "All model IQ"),
        DashboardDisclosure.RadarInsightsDetails =>
            T("场景推荐与降智预警", "Tips & alerts"),
        _ => disclosure.ToString()
    };

    private string DashboardSectionSummary(DashboardSection section) => section switch
    {
        DashboardSection.Quota =>
            $"{T("周额度", "Weekly")} {Percent(_snapshot.WeeklyRemaining)}"
            + (_snapshot.ShortRemaining is int ? $"  ·  5h {Percent(_snapshot.ShortRemaining)}" : ""),
        DashboardSection.ModelIq =>
            $"IQ {(_snapshot.IqScore is double iq ? iq.ToString("0.0") : "--")}"
            + $"  ·  {RadarJson.QualityLabel(_snapshot.IqScore, _snapshot.IqStatus, _settings.Chinese)}",
        DashboardSection.ResetCredits =>
            $"{T("可用", "Available")} {_snapshot.AvailableResetCredits?.ToString() ?? "--"}",
        DashboardSection.UsagePace => _snapshot.QuotaPacing is { } pace
            ? $"{T("建议剩余", "Target left")} {pace.RoundedTargetRemaining}%"
            : T("等待周额度 reset 时间", "Waiting for weekly reset timing"),
        DashboardSection.Insights =>
            $"{_snapshot.RadarInsights?.Recommendations.Count ?? 0} {T("组推荐", "recommendation groups")}"
            + $"  ·  {_snapshot.RadarInsights?.DegradationAlerts.ValidItems.Count ?? 0} {T("条预警", "alerts")}",
        DashboardSection.RadarDetails => _snapshot.AnnouncementLabel
                                         ?? _snapshot.ResetRadarTitle
                                         ?? T("公开雷达明细", "Public radar details"),
        DashboardSection.TaskbarGuide => _snapshot.CompactTitle(_settings),
        DashboardSection.DisplayAndAlerts => _settings.StatusDisplayMode == StatusDisplayMode.TaskbarText
            ? T("任务栏文字", "Taskbar text")
            : T("通知区域图标", "Notification icon"),
        DashboardSection.Updates => $"{AppUpdateService.CurrentVersion}  ·  {UpdateStatusText()}",
        DashboardSection.Preview => _settings.Preview.ToString(),
        _ => "--"
    };

    private void AddSpeedBanner()
    {
        var panel = CreateCard(T("⚡ 速蹬窗口开启", "⚡ Speed window open"), Palette.Red, Palette.RedPale);
        var body = Body(panel);
        AddText(body, T(
            $"建议尽快使用 · 周额度剩余 {Percent(_snapshot.WeeklyRemaining)}",
            $"Use quota soon · {Percent(_snapshot.WeeklyRemaining)} weekly left"), Color.FromArgb(117, 22, 18), true);
        if (!string.IsNullOrWhiteSpace(_snapshot.WindowSummary))
            AddText(body, _snapshot.WindowSummary!, Palette.Text);
        AddButtonRow(body,
            (T("关闭本次强调", "Dismiss this alert"), () => DismissSpeedRequested?.Invoke(this, EventArgs.Empty)),
            (T("查看来源", "Open source"), () => Open(_snapshot.WindowSourceUrl ?? RadarUrl)));
        AddPanel(panel);
    }

    private void AddStatusLegend()
    {
        var panel = CreateCard(T("状态栏含义", "Taskbar status"), Palette.Blue);
        var body = Body(panel);
        AddText(body, T(
            "默认显示“周额度 / IQ / 质量”；可在设置中打开 5h 和应剩。",
            "Default: Weekly / IQ / Quality. Enable 5h and Pace in Settings."), Palette.Secondary);

        var tiles = new[]
        {
            (T("周", "Weekly"), StatusTitleFormatter.Value(StatusMetric.WeeklyQuota, _snapshot, _settings), QuotaColor(_snapshot.WeeklyRemaining)),
            ("5h", StatusTitleFormatter.Value(StatusMetric.ShortQuota, _snapshot, _settings), QuotaColor(_snapshot.ShortRemaining)),
            (T("应剩", "Pace"), StatusTitleFormatter.Value(StatusMetric.QuotaPace, _snapshot, _settings), PaceColor()),
            ("IQ", StatusTitleFormatter.Value(StatusMetric.CodexIq, _snapshot, _settings), IqColor(_snapshot.IqScore, _snapshot.IqStatus)),
            (T("质量", "Signal"), StatusTitleFormatter.Value(StatusMetric.Signal, _snapshot, _settings), HeaderColor())
        };
        AddTileRow(body, tiles);
        AddPanel(panel);
    }

    private void AddAnnouncement()
    {
        if (string.IsNullOrWhiteSpace(_snapshot.Announcement)) return;
        var heading = _snapshot.AnnouncementLabel ?? T("CodexRadar 公告", "CodexRadar Notice");
        var panel = CreateCard(heading, Palette.Blue, Palette.BluePale);
        var body = Body(panel);
        if (!string.IsNullOrWhiteSpace(_snapshot.AnnouncementUpdatedLabel))
            AddText(body, _snapshot.AnnouncementUpdatedLabel!, Palette.Secondary);
        AddText(body, _snapshot.Announcement!, Palette.Text);
        if (!string.IsNullOrWhiteSpace(_snapshot.AnnouncementUrl))
            AddButtonRow(body, (_snapshot.AnnouncementSourceLabel ?? T("查看来源", "Open source"),
                () => Open(_snapshot.AnnouncementUrl!)));
        AddPanel(panel);
    }

    private void AddQuotaCard()
    {
        var panel = CreateCard(T("Codex 额度", "Codex Quota"), Palette.Blue);
        var body = Body(panel);
        AddProgress(body, T("周额度", "Weekly"), _snapshot.WeeklyRemaining, _snapshot.WeeklyUsedPercent,
            _snapshot.WeeklyResetsAt, _snapshot.WeeklyWindowMinutes);
        AddProgress(body, T("短窗", "Short"), _snapshot.ShortRemaining, _snapshot.ShortUsedPercent,
            _snapshot.ShortResetsAt, _snapshot.ShortWindowMinutes);

        var details = new List<string>();
        if (!string.IsNullOrWhiteSpace(_snapshot.PlanType)) details.Add($"{T("套餐", "Plan")} {_snapshot.PlanType}");
        if (!string.IsNullOrWhiteSpace(_snapshot.CreditsBalance)) details.Add($"{T("余额", "Credits")} {_snapshot.CreditsBalance}");
        if (details.Count > 0) AddText(body, string.Join("  ·  ", details), Palette.Secondary);
        if (_settings.IsDashboardDisclosureVisible(
                DashboardDisclosure.QuotaHistory))
            AddQuotaHistory(body);
        if (_snapshot.LimitReached)
            AddCallout(body, T("本机 Codex 返回限额状态。", "Local Codex reports a rate limit."), Palette.Red, Palette.RedPale);
        AddPanel(panel);
    }

    private void AddQuotaHistory(TableLayoutPanel body)
    {
        AddKeyValue(
            body,
            T("额度历史", "Quota history"),
            QuotaHistoryRangeLabel(
                _settings.QuotaHistoryRange));
        if (!_settings.IsDashboardDisclosureExpanded(
                DashboardDisclosure.QuotaHistory))
        {
            AddButtonRow(
                body,
                (T("展开额度历史", "Show quota history"), () =>
                {
                    _settings.SetDashboardDisclosureExpanded(
                        DashboardDisclosure.QuotaHistory,
                        true);
                    SettingsChanged?.Invoke(
                        this,
                        EventArgs.Empty);
                }));
            return;
        }

        AddButtonRow(
            body,
            (T("24 小时", "24 hours"), () =>
                SetQuotaHistoryRange(
                    QuotaHistoryRange.Hours24)),
            (T("7 天", "7 days"), () =>
                SetQuotaHistoryRange(
                    QuotaHistoryRange.Days7)),
            (T("30 天", "30 days"), () =>
                SetQuotaHistoryRange(
                    QuotaHistoryRange.Days30)),
            (T("收起", "Collapse"), () =>
            {
                _settings.SetDashboardDisclosureExpanded(
                    DashboardDisclosure.QuotaHistory,
                    false);
                SettingsChanged?.Invoke(
                    this,
                    EventArgs.Empty);
            }));

        var timeline = _settings.Preview
                       == DashboardPreview.Live
            ? _quotaHistory
            : QuotaHistoryTimeline.CreatePreview(
                _quotaHistoryEndingAt);
        var chart = new QuotaHistoryChartControl(
            timeline,
            _settings.QuotaHistoryRange,
            _quotaHistoryEndingAt,
            _settings.Chinese,
            _quotaHistoryStorageUnavailable
            && _settings.Preview == DashboardPreview.Live)
        {
            Height = ScaleDynamic(230),
            Font = new Font(
                "Segoe UI",
                Font.Size)
        };
        body.Controls.Add(chart);
    }

    private void SetQuotaHistoryRange(
        QuotaHistoryRange range)
    {
        if (_settings.QuotaHistoryRange == range)
            return;
        _settings.QuotaHistoryRange = range;
        SettingsChanged?.Invoke(
            this,
            EventArgs.Empty);
    }

    private string QuotaHistoryRangeLabel(
        QuotaHistoryRange range) => range switch
    {
        QuotaHistoryRange.Hours24 =>
            T("24 小时", "24 hours"),
        QuotaHistoryRange.Days7 =>
            T("7 天", "7 days"),
        _ => T("30 天", "30 days")
    };

    private void AddPacingCard()
    {
        var panel = CreateCard(T("用量节奏", "Usage Pace"), Palette.Teal);
        var body = Body(panel);
        if (_snapshot.QuotaPacing is not { } pace)
        {
            AddText(body, T(
                "还没有读取到周额度 reset 时间，暂时无法计算建议剩余。",
                "Weekly reset timing is not loaded, so target remaining is unavailable."), Palette.Secondary);
            AddPanel(panel);
            return;
        }

        var delta = pace.RoundedRemainingDelta;
        var deltaTitle = delta >= 3 ? T("可多用", "Can spend") : delta <= -3 ? T("已超用", "Over pace") : T("节奏差", "Delta");
        var deltaText = delta > 0 ? $"+{delta}%" : $"{delta}%";
        AddTileRow(body,
        [
            (T("建议剩余", "Target left"), $"{pace.RoundedTargetRemaining}%", PaceColor()),
            (T("实际剩余", "Actual left"), $"{pace.RoundedCurrentRemaining}%", QuotaColor(_snapshot.WeeklyRemaining)),
            (deltaTitle, deltaText, PaceColor())
        ]);
        AddText(body, PaceExplanation(pace), Palette.Secondary);
        AddPanel(panel);
    }

    private void AddResetJudgementCard()
    {
        if (_snapshot.ResetRadarCards.Count == 0 && string.IsNullOrWhiteSpace(_snapshot.ResetRadar)) return;
        var panel = CreateCard(T("CodexRadar 重置雷达", "CodexRadar Reset Radar"), Palette.Purple);
        var body = Body(panel);
        AddKeyValue(body, _snapshot.ResetRadarTitle ?? T("重置雷达研判", "Reset judgement"),
            _snapshot.ResetRadarUpdatedLabel ?? "");
        if (_snapshot.ResetRadarCards.Count == 0 && _snapshot.ResetRadarReasons.Count == 0
            && !string.IsNullOrWhiteSpace(_snapshot.ResetRadar)) AddText(body, _snapshot.ResetRadar!, Palette.Text);

        foreach (var card in _snapshot.ResetRadarCards)
        {
            var level = card.Level?.ToLowerInvariant() ?? "";
            var color = level.Contains("高", StringComparison.Ordinal) || level.Contains("high", StringComparison.Ordinal)
                ? Palette.Green
                : level.Contains("低", StringComparison.Ordinal) || level.Contains("low", StringComparison.Ordinal)
                    ? Palette.Orange
                    : Palette.Blue;
            var title = string.Join("  ·  ", new[] { card.Label, card.Level }.Where(value => !string.IsNullOrWhiteSpace(value)));
            AddCallout(body, $"{title}{(string.IsNullOrWhiteSpace(card.Summary) ? "" : Environment.NewLine + card.Summary)}", color, ColorBlend(color));
        }
        if (_snapshot.ResetRadarReasons.Count > 0)
        {
            AddText(body, T("研判依据", "Reasons"), Palette.Purple, true);
            foreach (var reason in _snapshot.ResetRadarReasons) AddBullet(body, reason);
        }
        AddPanel(panel);
    }

    private void AddCommunityAndCreditsCard()
    {
        var panel = CreateCard(T("重置卡过期", "Reset Credit Expiry"), Palette.Teal);
        var body = Body(panel);
        AddText(body, _snapshot.CommunityKnowledge ?? T("重置卡过期时间自查", "Reset credit expiry check"), Palette.Text, true);
        AddText(body, T(
            "默认低频自动刷新 reset credits；只读取本机 Codex 登录态，不保存 token，只缓存脱敏结果。",
            "Low-frequency refresh reads local Codex auth, never stores tokens, and caches only sanitized results."), Palette.Secondary);
        AddCallout(
            body,
            ResetCreditProtectionStatusText(
                _snapshot.ResetCreditProtection),
            ResetCreditProtectionStatusColor(
                _snapshot.ResetCreditProtection),
            ColorBlend(ResetCreditProtectionStatusColor(
                _snapshot.ResetCreditProtection)));
        AddText(body, T(
            "“到期前自动使用”默认关闭。启用时只授权当前完整卡集合；目标卡到期前 30 分钟才会尝试，账号、卡集合、系统时钟或授权变化都会安全停用。",
            "Expiry auto-use is off by default. Enabling authorizes only the current complete card set; it acts 30 minutes before expiry and fails closed on account, card-set, clock, or authorization changes."),
            Palette.Secondary);

        if (_resetLoading)
        {
            AddCallout(body, T(
                "正在读取本机 Codex 登录态，并请求 ChatGPT reset credits…",
                "Reading local Codex auth and requesting ChatGPT reset credits…"), Palette.Blue, Palette.BluePale);
        }
        if (_snapshot.ResetCreditFailure is { } failure)
        {
            AddCallout(body,
                $"{ResetFailureHeading(failure)}  ·  {FormatDateTime(failure.OccurredAt)}" +
                $"{Environment.NewLine}{ResetFailureMessage(failure)}" +
                $"{Environment.NewLine}{ResetFailureRecovery(failure)}",
                Palette.Red, Palette.RedPale);
        }

        if (_snapshot.AvailableResetCredits is int available || _snapshot.TotalEarnedResetCredits is int)
        {
            AddKeyValue(body, T("可用 / 累计", "Available / earned"),
                $"{availableOrDash(_snapshot.AvailableResetCredits)} / {availableOrDash(_snapshot.TotalEarnedResetCredits)}");
        }
        if (_snapshot.ResetCreditsCheckedAt is { } checkedAt)
            AddText(body, $"{T("上次查询", "Last checked")} {FormatDateTime(checkedAt)}", Palette.Secondary);

        if (_snapshot.ResetCredits.Count == 0 && !_resetLoading)
        {
            AddText(body, _snapshot.ResetCreditsCheckedAt is not null
                ? T("没有读取到重置卡。当前账号可能没有可展示的 reset credit，或接口结构已变化。",
                    "No reset credits were found. This account may have none to show, or the endpoint shape changed.")
                : T(_settings.AutoResetCreditCheck
                        ? "还没有缓存结果。自动查询会在启动后尝试，也可立即刷新。"
                        : "还没有缓存结果。打开自动查询或立即刷新后会显示全部卡片。",
                    _settings.AutoResetCreditCheck
                        ? "No cached result yet. Auto check will try after launch, or refresh now."
                        : "No cached result yet. Enable auto check or refresh now to show every credit."), Palette.Secondary);
        }
        else
        {
            for (var index = 0; index < _snapshot.ResetCredits.Count; index++)
                AddResetCredit(body, _snapshot.ResetCredits[index], index + 1);
        }

        AddButtonRow(body,
            (_resetLoading ? T("正在刷新…", "Refreshing…") : T("立即刷新", "Refresh now"),
                () => ResetCreditsRequested?.Invoke(this, EventArgs.Empty)),
            (T("复制安全 Prompt", "Copy safe Prompt"), () => CopyPrompt(T(SafeResetCreditPromptZh, SafeResetCreditPromptEn))),
            ("Codex", OpenCodex));
        if (_settings.ResetCreditProtectionEnabled)
        {
            AddButtonRow(
                body,
                (T("关闭自动使用", "Turn off auto-use"),
                    () => ProtectionDisableRequested?.Invoke(
                        this, EventArgs.Empty)),
                (T("重新检查计划", "Recheck plan"),
                    () => ProtectionPreviewRequested?.Invoke(
                        this, EventArgs.Empty)));
        }
        else
        {
            AddButtonRow(
                body,
                (T("启用到期前自动使用", "Enable expiry auto-use"),
                    () => ProtectionEnableRequested?.Invoke(
                        this, EventArgs.Empty)),
                (T("只读检查计划", "Read-only plan"),
                    () => ProtectionPreviewRequested?.Invoke(
                        this, EventArgs.Empty)));
        }
        AddText(body, T(
            $"自动查询：{(_settings.AutoResetCreditCheck ? "已开启" : "已关闭")} · 缓存超过 6 小时后刷新，失败不影响状态栏。",
            $"Auto check: {(_settings.AutoResetCreditCheck ? "on" : "off")} · refreshes after 6 hours; failures do not affect the taskbar."), Palette.Secondary);
        AddPanel(panel);

        static string availableOrDash(int? value) => value?.ToString() ?? "--";
    }

    private void AddResetCredit(TableLayoutPanel body, ResetCredit credit, int index)
    {
        var normalized = credit.Status?.ToLowerInvariant() ?? "";
        var used = credit.RedeemedAt is not null || normalized.Contains("redeem", StringComparison.Ordinal);
        var expired = !used && credit.IsExpired();
        var expiresSoon = !used && !expired && credit.ExpiresAt is { } soonExpiry
                          && soonExpiry - DateTimeOffset.Now < TimeSpan.FromDays(3);
        var color = used ? Palette.Gray : expired ? Palette.Red : expiresSoon ? Palette.Orange
            : credit.IsAvailable ? Palette.Green : Palette.Blue;
        var state = ResetCreditStatus(credit, expired);
        var lines = new List<string>
        {
            $"{T("重置卡", "Credit")} {index}  ·  {state}",
            $"{T("发放", "Issued")} {FormatDateTime(credit.GrantedAt)}  ·  {T("过期", "Expires")} {FormatDateTime(credit.ExpiresAt)}"
        };
        if (credit.ExpiresAt is { } expiry && !used && !expired)
            lines.Add($"{T("剩余", "Time left")} {TimeLeft(expiry)}");
        var details = new[]
        {
            string.IsNullOrWhiteSpace(credit.Title) ? null : credit.Title,
            string.IsNullOrWhiteSpace(credit.ResetType) ? null : credit.ResetType,
            ResetCreditPrivacy.IsValidFingerprint(credit.Fingerprint)
                ? $"{T("指纹", "Fingerprint")} {ResetCreditPrivacy.DisplayFingerprint(credit.Fingerprint)}"
                : null,
            credit.RedeemStartedAt is { } start ? $"{T("兑换开始", "Redeem started")} {FormatDateTime(start)}" : null,
            credit.RedeemedAt is { } redeemed ? $"{T("已兑换", "Redeemed")} {FormatDateTime(redeemed)}" : null
        }.Where(value => !string.IsNullOrWhiteSpace(value));
        var detailText = string.Join("  ·  ", details);
        if (detailText.Length > 0) lines.Add(detailText);
        AddCallout(body, string.Join(Environment.NewLine, lines), color, ColorBlend(color));
    }

    private void AddPublicQuotaRadarCard()
    {
        if (_snapshot.QuotaRadar.Count == 0) return;
        var panel = CreateCard(T("CodexRadar 额度雷达", "CodexRadar Quota Radar"), Palette.Teal);
        var body = Body(panel);
        var header = $"{T("档位", "Tier"),-14}  5h USD     7d USD";
        var rows = _snapshot.QuotaRadar.Select(item =>
            $"{item.Tier,-14}  {Money(item.FiveHourUsd),8}  {Money(item.SevenDayUsd),9}" +
            (string.IsNullOrWhiteSpace(item.Basis) ? "" : $"  {QuotaBasisText(item.Basis)}"));
        AddText(body, header + Environment.NewLine + string.Join(Environment.NewLine, rows), Palette.Text, monospace: true);

        var facts = new List<string>();
        if (!string.IsNullOrWhiteSpace(_snapshot.QuotaRadarDate)) facts.Add(_snapshot.QuotaRadarDate!);
        if (_snapshot.QuotaRadarUpdatedAt is { } updated) facts.Add($"{T("更新", "Updated")} {FormatDateTime(updated)}");
        if (!string.IsNullOrWhiteSpace(_snapshot.QuotaRadarBasisWindowLabel)) facts.Add($"{T("校准", "Basis")} {_snapshot.QuotaRadarBasisWindowLabel}");
        if (_snapshot.QuotaRadarCostUsd is double cost) facts.Add($"{T("成本", "Cost")} ${cost:0.00}");
        if (_snapshot.QuotaRadarTotalTokens is long tokens) facts.Add($"{tokens:N0} tokens");
        if (_snapshot.QuotaRadarSevenDayTrendDelta is double delta) facts.Add($"20x Pro 7d {(delta >= 0 ? "+" : "-")}${Math.Abs(delta):0.00}");
        if (facts.Count > 0) AddText(body, string.Join("  ·  ", facts), Palette.Secondary);
        AddText(body, T(
            "这是 CodexRadar 的公开额度等价值估算；5x/Plus 可能按比例推测，不代表本机剩余额度。",
            "These are public quota-equivalent estimates. 5x/Plus may be scaled estimates, not local remaining quota."), Palette.Secondary);
        AddPanel(panel);
    }

    private void AddRadarStatusCard()
    {
        var hasRadar = !string.IsNullOrWhiteSpace(_snapshot.RadarStatus)
                       || !string.IsNullOrWhiteSpace(_snapshot.WindowTitle)
                       || !string.IsNullOrWhiteSpace(_snapshot.WindowSummary);
        if (!hasRadar) return;
        var panel = CreateCard("CodexRadar", _snapshot.ActiveEntitlementEvent ? Palette.Teal : Palette.Blue);
        var body = Body(panel);
        AddText(body, _snapshot.WindowTitle ?? T("CodexRadar 当前状态", "Current CodexRadar status"), Palette.Text, true);
        AddKeyValue(body, T("当前重点", "Focus"), RadarFocus());
        AddKeyValue(body, T("旧提醒", "Legacy alerts"), IsRadarRetired() ? T("已下架", "retired")
            : (_snapshot.WindowScope ?? T("未知", "unknown")));
        if (!string.IsNullOrWhiteSpace(_snapshot.WindowSummary)) AddText(body, _snapshot.WindowSummary!, Palette.Text);
        if (!string.IsNullOrWhiteSpace(_snapshot.WindowHuman)) AddText(body, _snapshot.WindowHuman!, Palette.Secondary);
        var metadata = new[]
        {
            _snapshot.SchemaVersion is null ? null : $"schema {_snapshot.SchemaVersion}",
            _snapshot.CheckedAt is { } checkedAt ? $"{T("检查", "Checked")} {FormatDateTime(checkedAt)}" : null,
            _snapshot.WindowOpenedAt is { } opened ? $"{T("开启", "Opened")} {FormatDateTime(opened)}" : null,
            _snapshot.WindowClosedAt is { } closed ? $"{T("关闭", "Closed")} {FormatDateTime(closed)}" : null,
            string.IsNullOrWhiteSpace(_snapshot.WindowScope) ? null : $"scope {_snapshot.WindowScope}"
        }.Where(value => value is not null);
        AddText(body, string.Join("  ·  ", metadata), Palette.Secondary);
        if (!string.IsNullOrWhiteSpace(_snapshot.WindowSourceUrl))
            AddButtonRow(body, (T("查看来源", "Open source"), () => Open(_snapshot.WindowSourceUrl!)));
        AddPanel(panel);
    }

    private void AddPredictionCard()
    {
        if (_snapshot.Prediction is not { } prediction || !ShouldShowPrediction(prediction)) return;
        var color = PredictionColor(prediction.Level);
        var panel = CreateCard(T("Prediction 预测", "Prediction"), color);
        var body = Body(panel);
        AddKeyValue(body, T("等级", "Level"), PredictionLevelText(prediction.Level));
        AddKeyValue(body, "24h / 48h", $"{Probability(prediction.Probability24Hours)} / {Probability(prediction.Probability48Hours)}");
        if (prediction.ShouldNotify is bool notify)
            AddKeyValue(body, T("提醒建议", "Notify"), notify ? T("是", "yes") : T("否", "no"));
        if (!string.IsNullOrWhiteSpace(prediction.ExpectedWindow))
            AddKeyValue(body, T("预计窗口", "Expected window"), prediction.ExpectedWindow!);
        if (!string.IsNullOrWhiteSpace(prediction.Summary)) AddText(body, prediction.Summary!, Palette.Text);
        if (prediction.UpdatedAt is { } updated) AddText(body, $"{T("更新", "Updated")} {FormatDateTime(updated)}", Palette.Secondary);
        AddPanel(panel);
    }

    private void AddIqCard()
    {
        if (_snapshot.IqScore is null && _snapshot.Comparisons.Count == 0) return;
        var panel = CreateCard("Model IQ", IqColor(_snapshot.IqScore, _snapshot.IqStatus));
        var body = Body(panel);
        var latest = new ModelComparison(
            _snapshot.ModelLabel ?? "Codex", _snapshot.IqScore, _snapshot.IqStatus, _snapshot.Passed, _snapshot.ValidTasks,
            _snapshot.CommunityRating, _snapshot.CommunityRatingCount, _snapshot.WallTime, _snapshot.CostUsd,
            _snapshot.CacheHitRate, _snapshot.ModelName, _snapshot.ReasoningEffort,
            _snapshot.AverageCostUsd, _snapshot.AverageTaskMinutes, _snapshot.IqDate);
        if (_snapshot.IqScore is not null) AddModelIq(body, latest, true);
        var modelDetailsVisible =
            _settings.IsDashboardDisclosureVisible(
                DashboardDisclosure.ModelIqDetails);
        if (modelDetailsVisible
            && _settings.IsDashboardDisclosureExpanded(
                DashboardDisclosure.ModelIqDetails))
            foreach (var comparison in _snapshot.Comparisons)
                AddModelIq(body, comparison, false);
        if (modelDetailsVisible
            && _snapshot.Comparisons.Count > 0)
            AddButtonRow(body, (_settings.IsDashboardDisclosureExpanded(
                    DashboardDisclosure.ModelIqDetails)
                    ? T("收起全部模型 IQ", "Hide all model IQ")
                    : T($"全部模型 IQ（{_snapshot.Comparisons.Count + 1}）",
                        $"All model IQ ({_snapshot.Comparisons.Count + 1})"),
                () =>
                {
                    _settings.SetDashboardDisclosureExpanded(
                        DashboardDisclosure.ModelIqDetails,
                        !_settings.IsDashboardDisclosureExpanded(
                            DashboardDisclosure.ModelIqDetails));
                    SettingsChanged?.Invoke(this, EventArgs.Empty);
                }));
        var sourceFacts = new List<string>();
        if (!string.IsNullOrWhiteSpace(_snapshot.IqDate)) sourceFacts.Add(_snapshot.IqDate!);
        if (_snapshot.IqValidCells is int validCells)
            sourceFacts.Add($"{validCells:N0} {T("有效任务", "valid tasks")}");
        if (_snapshot.IqSourceUpdatedAt is { } sourceUpdated)
            sourceFacts.Add($"{T("数据更新", "Source updated")} {FormatDateTime(sourceUpdated)}");
        if (sourceFacts.Count > 0) AddText(body, string.Join("  ·  ", sourceFacts), Palette.Secondary);
        if (!string.IsNullOrWhiteSpace(_snapshot.IqDataSourceUrl))
            AddButtonRow(body, (T("打开分布式数据源", "Open distributed source"),
                () => Open(_snapshot.IqDataSourceUrl!)));
        AddPanel(panel);
    }

    private void AddModelIq(TableLayoutPanel body, ModelComparison model, bool primary)
    {
        var color = IqColor(model.Iq, model.Status);
        var title = $"{model.Label}  ·  IQ {(model.Iq is double iq ? iq.ToString("0.0") : "--")}";
        var metrics = new List<string>();
        if (model.Passed is int passed || model.Tasks is int)
            metrics.Add($"{T("探针", "Probes")} {passedOrDash(model.Passed)}/{passedOrDash(model.Tasks)}");
        if (!string.IsNullOrWhiteSpace(model.Status)) metrics.Add($"{T("状态", "Status")} {model.Status}");
        if (model.Rating is double rating)
            metrics.Add($"{T("体感", "Rating")} {rating:0.0}/10{(model.RatingCount is int count ? $" · {count} {T("票", "votes")}" : "")}");
        if (model.AverageMinutes is double averageMinutes)
            metrics.Add($"{T("平均耗时", "Avg time")} {Math.Max(1, (int)Math.Round(averageMinutes))} min");
        else if (!string.IsNullOrWhiteSpace(model.WallTime))
            metrics.Add($"{T("耗时", "Time")} {model.WallTime}");
        if (model.AverageCostUsd is double averageCost)
            metrics.Add($"{T("平均费用", "Avg cost")} ${averageCost:0.00}");
        else if (model.CostUsd is double cost)
            metrics.Add($"{T("费用", "Cost")} ${cost:0.00}");
        if (!string.IsNullOrWhiteSpace(model.CacheHitRate)) metrics.Add($"Cache {model.CacheHitRate}");
        var text = title + (metrics.Count == 0 ? "" : Environment.NewLine + string.Join("  ·  ", metrics));
        AddCallout(body, text, color, primary ? ColorBlend(color) : Color.FromArgb(249, 250, 251));

        static string passedOrDash(int? value) => value?.ToString() ?? "--";
    }

    private void AddRadarInsightsCard()
    {
        var groups = _snapshot.RadarInsights?.Recommendations
            .Where(group => group.ValidItems.Count > 0).ToArray() ?? [];
        var alerts = _snapshot.RadarInsights?.DegradationAlerts.ValidItems ?? [];
        if (groups.Length == 0 && alerts.Count == 0) return;

        var panel = CreateCard(T("CodexRadar 智能洞察", "CodexRadar Insights"),
            alerts.Count > 0 ? Palette.Orange : Palette.Purple);
        var body = Body(panel);
        var preferred = groups.FirstOrDefault(group =>
                            NormalizeInsightKey(group.Key) == "daily-development")
                        ?? groups.FirstOrDefault();
        var pick = preferred?.ValidItems.FirstOrDefault();
        var strongestAlert = alerts.OrderByDescending(alert => alert.LargestDrop).FirstOrDefault();
        AddTileRow(body,
        [
            (T("场景推荐", "Scenario pick"),
                pick is null ? "--" : $"{pick.Model} {pick.Effort}",
                Palette.Purple),
            ("IQ", pick?.Iq is double iq ? iq.ToString("0.0") : "--",
                IqColor(pick?.Iq, null)),
            (T("降智预警", "Degradation"),
                strongestAlert is null ? T("无", "none") : $"-{strongestAlert.LargestDrop:0.0}",
                strongestAlert is null ? Palette.Green : Palette.Orange)
        ]);

        var insightDetailsVisible =
            _settings.IsDashboardDisclosureVisible(
                DashboardDisclosure.RadarInsightsDetails);
        if (insightDetailsVisible
            && _settings.IsDashboardDisclosureExpanded(
                DashboardDisclosure.RadarInsightsDetails))
        {
            foreach (var group in groups)
            {
                var heading = group.Title ?? group.Key ?? T("推荐", "Recommendation");
                var rule = string.IsNullOrWhiteSpace(group.Rule) ? "" : $"  ·  {group.Rule}";
                AddText(body, heading + rule, Palette.Purple, true);
                foreach (var item in group.ValidItems)
                {
                    var facts = new List<string>
                    {
                        $"{item.Model} {item.Effort}",
                        $"IQ {item.Iq:0.0}"
                    };
                    if (item.AverageCostUsd is double cost)
                        facts.Add($"{T("均费", "avg")} ${cost:0.00}");
                    if (item.AverageDurationMinutes is double minutes)
                        facts.Add($"{Math.Max(1, (int)Math.Round(minutes))} min");
                    AddBullet(body, string.Join("  ·  ", facts));
                }
            }

            if (alerts.Count > 0)
            {
                AddText(body, T("降智预警", "Degradation alerts"), Palette.Orange, true);
                foreach (var alert in alerts.OrderByDescending(item => item.LargestDrop))
                {
                    var windows = new List<string>();
                    if (alert.From24HourHighIq is double day) windows.Add($"24h -{day:0.0}");
                    if (alert.From48HourHighIq is double twoDays) windows.Add($"48h -{twoDays:0.0}");
                    AddCallout(body,
                        $"{alert.Model} {alert.Effort}  ·  IQ {alert.Iq:0.0}" +
                        (windows.Count == 0 ? "" : Environment.NewLine + string.Join("  ·  ", windows)),
                        Palette.Orange, Palette.OrangePale);
                }
            }
        }
        if (insightDetailsVisible)
            AddButtonRow(body, (_settings.IsDashboardDisclosureExpanded(
                        DashboardDisclosure.RadarInsightsDetails)
                    ? T("收起场景推荐与预警", "Hide recommendations and alerts")
                    : T($"场景推荐与降智预警（{groups.Length + alerts.Count}）",
                        $"Recommendations and alerts ({groups.Length + alerts.Count})"),
                () =>
                {
                    _settings.SetDashboardDisclosureExpanded(
                        DashboardDisclosure.RadarInsightsDetails,
                        !_settings.IsDashboardDisclosureExpanded(
                            DashboardDisclosure.RadarInsightsDetails));
                    SettingsChanged?.Invoke(this, EventArgs.Empty);
                }));

        var updated = _snapshot.RadarInsights?.SourceUpdatedAt
                      ?? _snapshot.RadarInsights?.GeneratedAt;
        if (RadarJson.Date(updated) is { } date)
            AddText(body, $"{T("数据更新", "Source updated")} {FormatDateTime(date)}", Palette.Secondary);
        AddText(body, T(
            "此接口独立缓存 10 分钟；失败或时间戳倒退时保留上次有效结果，不进入状态栏或通知。",
            "This endpoint is cached independently for 10 minutes. Failures or timestamp regressions keep the last valid result and never enter the taskbar title or notifications."),
            Palette.Secondary);
        AddPanel(panel);
    }

    private static string NormalizeInsightKey(string? value) =>
        System.Text.RegularExpressions.Regex.Replace(
            value?.Trim().ToLowerInvariant() ?? "", "[^a-z0-9]+", "-").Trim('-');

    private void AddErrorsCard()
    {
        if (_snapshot.Errors.Count == 0) return;
        var panel = CreateCard(T("连接", "Connection"), Palette.Orange, Palette.OrangePale);
        var body = Body(panel);
        foreach (var error in _snapshot.Errors) AddBullet(body, error, Palette.Orange);
        AddButtonRow(body, (T("重试", "Retry"), () => RefreshRequested?.Invoke(this, EventArgs.Empty)));
        AddPanel(panel);
    }

    internal void ShowLayoutEditor() =>
        SetLayoutEditorVisible(true);

    private void SetLayoutEditorVisible(bool visible)
    {
        if (_customizesLayout == visible) return;
        _customizesLayout = visible;
        if (visible
            && !_settings.LayoutDiscoveryTipDismissed)
        {
            _settings.LayoutDiscoveryTipDismissed = true;
            SettingsChanged?.Invoke(this, EventArgs.Empty);
        }
        QueueContentRender();
    }

    private void QueueContentRender()
    {
        _pendingContentSignature = BuildContentSignature(
            _snapshot,
            _settings,
            _updateStatus,
            _resetLoading,
            quotaHistory: _quotaHistory,
            quotaHistoryEndingAt: _quotaHistoryEndingAt,
            quotaHistoryStorageUnavailable:
                _quotaHistoryStorageUnavailable,
            customizesLayout: _customizesLayout);
        _renderPending = !_contentRendered
                         || !string.Equals(
                             _renderedContentSignature,
                             _pendingContentSignature,
                             StringComparison.Ordinal);
        RenderChrome();
        ScheduleRender();
    }

    private void CommitLayoutChange()
    {
        SettingsChanged?.Invoke(this, EventArgs.Empty);
        QueueContentRender();
    }

    private void AddLayoutEditor()
    {
        var panel = CreateCard(
            T("自定义面板布局", "Customize dashboard layout"),
            Palette.Blue,
            Color.White);
        panel.Name = "layoutEditor";
        var body = Body(panel);
        AddText(
            body,
            T(
                "拖动模块或使用箭头调整顺序；在同一行选择是否显示、是否默认展开。",
                "Drag sections or use arrows to reorder, then choose what appears and opens by default."),
            Palette.Secondary);

        var order = DashboardLayout.NormalizeOrder(
            _settings.DashboardSectionOrder);
        for (var index = 0; index < order.Count; index++)
        {
            var section = order[index];
            var resolution = DashboardLayout.Resolve(
                section,
                _settings.IsDashboardSectionVisible(section),
                _settings.IsDashboardSectionExpanded(section),
                _snapshot.ResetCreditProtection,
                _updateStatus.Phase == AppUpdatePhase.Failed);
            var row = CreateLayoutEditorRow(
                $"layout-section-{section}",
                LayoutEditorLabel(section),
                resolution.IsVisible,
                resolution.IsExpanded,
                resolution.CanHide,
                resolution.CanCollapse,
                canMoveUp: index > 0,
                canMoveDown: index < order.Count - 1,
                nested: false);
            WireSectionLayoutRow(
                row,
                section,
                index);
            body.Controls.Add(row);

            foreach (var disclosure in
                     DashboardLayout.Children(section))
            {
                var child = CreateLayoutEditorRow(
                    $"layout-disclosure-{disclosure}",
                    DisclosureEditorLabel(disclosure),
                    _settings.IsDashboardDisclosureVisible(
                        disclosure),
                    _settings.IsDashboardDisclosureExpanded(
                        disclosure),
                    canHide: true,
                    canCollapse: true,
                    canMoveUp: false,
                    canMoveDown: false,
                    nested: true);
                WireDisclosureLayoutRow(
                    child,
                    disclosure);
                body.Controls.Add(child);
            }
        }

        AddButtonRow(
            body,
            (T("恢复默认布局", "Restore default layout"), () =>
            {
                _settings.ResetDashboardLayout();
                CommitLayoutChange();
            }));
        AddText(
            body,
            T(
                "隐藏只影响展示；额度历史记录、提醒和重置卡自动使用会继续。当前结论、紧急提示和连接错误始终显示，需要处理的重置卡或更新会临时置顶。",
                "Hiding changes only presentation. Quota-history recording, alerts, and reset-credit auto-use continue. Current results, urgent alerts, and connection errors remain visible; reset-credit or update states needing attention temporarily appear first."),
            Palette.Secondary);
        AddPanel(panel);
    }

    private TableLayoutPanel CreateLayoutEditorRow(
        string name,
        string label,
        bool visible,
        bool expanded,
        bool canHide,
        bool canCollapse,
        bool canMoveUp,
        bool canMoveDown,
        bool nested)
    {
        var row = new TableLayoutPanel
        {
            Name = name,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            ColumnCount = 5,
            RowCount = 1,
            AllowDrop = !nested,
            BackColor = nested
                ? Color.FromArgb(248, 249, 251)
                : Color.FromArgb(244, 247, 251),
            Margin = ScaleDynamic(
                new Padding(0, nested ? 1 : 4, 0, 1)),
            Padding = ScaleDynamic(
                new Padding(nested ? 17 : 7, 4, 5, 4)),
            AccessibleName = nested
                ? T(
                    $"布局子项：{label}",
                    $"Layout item: {label}")
                : T(
                    $"布局模块：{label}",
                    $"Layout section: {label}")
        };
        row.ColumnStyles.Add(
            new ColumnStyle(SizeType.Percent, 100));
        for (var index = 1; index < 5; index++)
            row.ColumnStyles.Add(
                new ColumnStyle(SizeType.AutoSize));

        var title = new Label
        {
            Name = "label",
            Text = nested ? $"↳ {label}" : $"⋮⋮  {label}",
            AutoEllipsis = true,
            Dock = DockStyle.Fill,
            MinimumSize = new Size(
                ScaleDynamic(80),
                ScaleDynamic(27)),
            TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font(
                "Segoe UI Semibold",
                Font.Size,
                nested
                    ? FontStyle.Regular
                    : FontStyle.Bold),
            ForeColor = Palette.Text,
            UseMnemonic = false
        };
        var show = new CheckBox
        {
            Name = "show",
            Text = T("显示", "Show"),
            Checked = visible,
            Enabled = canHide,
            AutoSize = true,
            Anchor = AnchorStyles.None,
            AccessibleName = T(
                $"显示 {label}",
                $"Show {label}")
        };
        var startOpen = new CheckBox
        {
            Name = "startOpen",
            Text = T("默认展开", "Start open"),
            Checked = expanded,
            Enabled = visible && canCollapse,
            AutoSize = true,
            Anchor = AnchorStyles.None,
            AccessibleName = T(
                $"{label} 默认展开",
                $"Open {label} by default")
        };
        var moveUp = LayoutMoveButton(
            "moveUp",
            "↑",
            canMoveUp,
            T(
                $"上移 {label}",
                $"Move {label} up"));
        var moveDown = LayoutMoveButton(
            "moveDown",
            "↓",
            canMoveDown,
            T(
                $"下移 {label}",
                $"Move {label} down"));
        if (nested)
        {
            moveUp.Visible = false;
            moveDown.Visible = false;
        }

        row.Controls.Add(title, 0, 0);
        row.Controls.Add(show, 1, 0);
        row.Controls.Add(startOpen, 2, 0);
        row.Controls.Add(moveUp, 3, 0);
        row.Controls.Add(moveDown, 4, 0);
        return row;
    }

    private Button LayoutMoveButton(
        string name,
        string text,
        bool enabled,
        string accessibleName) => new()
    {
        Name = name,
        Text = text,
        Enabled = enabled,
        Width = ScaleDynamic(28),
        Height = ScaleDynamic(27),
        Margin = ScaleDynamic(new Padding(2, 0, 0, 0)),
        FlatStyle = FlatStyle.Flat,
        BackColor = Color.White,
        ForeColor = Palette.Blue,
        UseMnemonic = false,
        AccessibleName = accessibleName
    };

    private void WireSectionLayoutRow(
        TableLayoutPanel row,
        DashboardSection section,
        int targetIndex)
    {
        var show = (CheckBox)row.Controls["show"]!;
        var startOpen =
            (CheckBox)row.Controls["startOpen"]!;
        show.CheckedChanged += (_, _) =>
        {
            if (!show.Enabled) return;
            _settings.SetDashboardSectionVisible(
                section,
                show.Checked);
            startOpen.Enabled = show.Checked;
            CommitLayoutChange();
        };
        startOpen.CheckedChanged += (_, _) =>
        {
            if (!startOpen.Enabled) return;
            _settings.SetDashboardSectionExpanded(
                section,
                startOpen.Checked);
            CommitLayoutChange();
        };
        ((Button)row.Controls["moveUp"]!).Click +=
            (_, _) =>
            {
                _settings.MoveDashboardSection(section, -1);
                CommitLayoutChange();
            };
        ((Button)row.Controls["moveDown"]!).Click +=
            (_, _) =>
            {
                _settings.MoveDashboardSection(section, 1);
                CommitLayoutChange();
            };

        void BeginDrag(object? sender, MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
                row.DoDragDrop(
                    section,
                    DragDropEffects.Move);
        }
        row.MouseDown += BeginDrag;
        row.Controls["label"]!.MouseDown += BeginDrag;
        row.DragEnter += (_, e) =>
        {
            if (e.Data?.GetDataPresent(
                    typeof(DashboardSection)) == true)
                e.Effect = DragDropEffects.Move;
        };
        row.DragDrop += (_, e) =>
        {
            if (e.Data?.GetData(
                    typeof(DashboardSection))
                is not DashboardSection dragged)
                return;
            _settings.MoveDashboardSectionTo(
                dragged,
                targetIndex);
            CommitLayoutChange();
        };
    }

    private void WireDisclosureLayoutRow(
        TableLayoutPanel row,
        DashboardDisclosure disclosure)
    {
        var show = (CheckBox)row.Controls["show"]!;
        var startOpen =
            (CheckBox)row.Controls["startOpen"]!;
        show.CheckedChanged += (_, _) =>
        {
            _settings.SetDashboardDisclosureVisible(
                disclosure,
                show.Checked);
            startOpen.Enabled = show.Checked;
            CommitLayoutChange();
        };
        startOpen.CheckedChanged += (_, _) =>
        {
            if (!startOpen.Enabled) return;
            _settings.SetDashboardDisclosureExpanded(
                disclosure,
                startOpen.Checked);
            CommitLayoutChange();
        };
    }

    private void AddLayoutDiscoveryTip()
    {
        var panel = CreateCard(
            T("面板可以按你的习惯排列", "Arrange the dashboard your way"),
            Palette.Blue,
            Palette.BluePale);
        var body = Body(panel);
        AddText(
            body,
            T(
                "在“布局”中调整模块顺序、显示状态和默认展开；隐藏不会停止额度历史记录、提醒或重置卡自动使用。",
                "Layout controls section order, visibility, and default expansion. Hiding never stops quota-history recording, alerts, or reset-credit auto-use."),
            Palette.Secondary);
        AddButtonRow(
            body,
              (T("试试布局", "Try Layout"), () =>
              {
                  SetLayoutEditorVisible(true);
              }),
            (T("关闭", "Dismiss"), () =>
            {
                _settings.LayoutDiscoveryTipDismissed = true;
                SettingsChanged?.Invoke(
                    this,
                    EventArgs.Empty);
            }));
        AddPanel(panel);
    }

    private void AddSettingsCard()
    {
        var panel = CreateCard(T("显示与提醒", "Display & Alerts"), Palette.Blue);
        var body = Body(panel);
        var metrics = _settings.SelectedStatusMetrics.Count == 0
            ? T("周额度", "Weekly")
            : string.Join(" / ", _settings.SelectedStatusMetrics.Select(MetricLabel));
        AddKeyValue(body, T("显示位置", "Location"),
            _settings.StatusDisplayMode == StatusDisplayMode.TaskbarText
                ? T("任务栏文字", "Taskbar text")
                : T("通知区域图标", "Notification icon"));
        AddKeyValue(body, T("状态摘要", "Status summary"), metrics);
        AddKeyValue(body, T("节奏", "Pacing"), PacingStrategyLabel(_settings.PacingStrategy));
        AddKeyValue(body, T("提醒", "Alerts"), string.Join(" · ", new[]
        {
            _settings.PredictionNotifications ? "Prediction" : null,
            _settings.IqNotifications ? "IQ" : null,
            _settings.NotificationSound ? T("声音", "sound") : null
        }.Where(value => value is not null).DefaultIfEmpty(T("仅必要提醒", "essential only"))));
        if (_settings.Preview != DashboardPreview.Live)
            AddCallout(body, $"{T("预览模式", "Preview mode")} · {_settings.Preview}", Palette.Purple, Palette.PurplePale);
        AddButtonRow(body, (T("打开设置", "Open Settings"), () => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        AddPanel(panel);
    }

    private void AddUpdateCard()
    {
        var color = _updateStatus.Phase == AppUpdatePhase.Failed ? Palette.Red
            : _updateStatus.Phase is AppUpdatePhase.Available or AppUpdatePhase.Downloading or AppUpdatePhase.Installing ? Palette.Blue
            : Palette.Teal;
        var panel = CreateCard(T("应用更新", "App Updates"), color);
        var body = Body(panel);
        AddKeyValue(body, T("当前版本", "Current version"), AppUpdateService.CurrentVersion);
        AddKeyValue(body, T("状态", "Status"), UpdateStatusText());
        if (!string.IsNullOrWhiteSpace(_updateStatus.Version))
            AddKeyValue(body, T("最新版本", "Latest version"), _updateStatus.Version!);
        if (!string.IsNullOrWhiteSpace(_updateStatus.Message)) AddText(body, _updateStatus.Message!, Palette.Secondary);
        AddText(body, T(
            $"自动更新：{(_settings.AutomaticUpdates ? "已开启" : "已关闭")} · 仅接受匹配当前架构并通过 SHA256/manifest 校验的 Windows 包。",
            $"Automatic updates: {(_settings.AutomaticUpdates ? "on" : "off")} · only matching Windows architecture packages with verified SHA256/manifest are accepted."), Palette.Secondary);
        var releaseUrl = _updateStatus.ReleaseUrl?.ToString() ?? AppUpdateService.ReleasesUrl;
        AddButtonRow(body,
            (T("检查更新", "Check now"), () => CheckUpdatesRequested?.Invoke(this, EventArgs.Empty)),
            (T("发行说明", "Releases"), () => Open(releaseUrl)),
            ("Prompts", () => Open(AppUpdateService.PromptsUrl)));
        AddPanel(panel);
    }

    private void AddPreviewCard()
    {
        var panel = CreateCard(T("调试预览", "Preview"), Palette.Purple);
        var body = Body(panel);
        AddKeyValue(body, T("当前状态", "Current state"), _settings.Preview.ToString());
        AddText(body, T(
            "预览只改变显示，不发送通知、不执行自动使用，也不覆盖实时数据。",
            "Preview changes display only. It sends no notifications, performs no auto-use, and does not replace live data."),
            Palette.Secondary);
        AddButtonRow(body, (T("打开预览设置", "Open preview settings"),
            () => SettingsRequested?.Invoke(this, EventArgs.Empty)));
        AddPanel(panel);
    }

    private RoundedPanel CreateCard(string heading, Color accent, Color? background = null)
    {
        var panel = new RoundedPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            BackColor = background ?? Color.White,
            BorderColor = Color.FromArgb(218, 222, 228),
            Padding = ScaleDynamic(new Padding(15, 12, 15, 13)),
            Margin = ScaleDynamic(new Padding(2, 0, 2, 11)),
            CornerDiameter = 11
        };
        var body = new TableLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            RowCount = 0,
            BackColor = Color.Transparent,
            Margin = Padding.Empty,
            Padding = Padding.Empty
        };
        var title = new Label
        {
            Text = heading,
            AutoSize = true,
            Font = new Font("Segoe UI Semibold", Font.Size + .8f, FontStyle.Bold),
            ForeColor = accent,
            Margin = ScaleDynamic(new Padding(0, 0, 0, 7))
        };
        body.Controls.Add(title);
        panel.Controls.Add(body);
        panel.Tag = body;
        return panel;
    }

    private static TableLayoutPanel Body(Control panel) => (TableLayoutPanel)panel.Tag!;

    private void AddPanel(Control panel) => _content.Controls.Add(panel);

    private void AddText(TableLayoutPanel body, string text, Color color, bool bold = false, bool monospace = false)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        body.Controls.Add(new Label
        {
            Text = text,
            AutoSize = true,
            MaximumSize = new Size(Math.Max(ScaleDynamic(320), _content.ClientSize.Width - ScaleDynamic(62)), 0),
            ForeColor = color,
            Font = new Font(monospace ? "Consolas" : "Segoe UI", Font.Size, bold ? FontStyle.Bold : FontStyle.Regular),
            Margin = ScaleDynamic(new Padding(0, 2, 0, 3)),
            UseMnemonic = false
        });
    }

    private void AddBullet(TableLayoutPanel body, string text, Color? color = null) =>
        AddText(body, $"• {text}", color ?? Palette.Secondary);

    private void AddKeyValue(TableLayoutPanel body, string key, string value)
    {
        var row = new TableLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Margin = ScaleDynamic(new Padding(0, 2, 0, 3)),
            BackColor = Color.Transparent
        };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 44));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 56));
        row.Controls.Add(new Label { Text = key, AutoSize = true, ForeColor = Palette.Secondary, UseMnemonic = false }, 0, 0);
        row.Controls.Add(new Label
        {
            Text = string.IsNullOrWhiteSpace(value) ? "--" : value,
            AutoSize = true,
            ForeColor = Palette.Text,
            Font = new Font("Segoe UI Semibold", Font.Size),
            TextAlign = ContentAlignment.TopRight,
            Anchor = AnchorStyles.Top | AnchorStyles.Right,
            UseMnemonic = false
        }, 1, 0);
        body.Controls.Add(row);
    }

    private void AddProgress(TableLayoutPanel body, string label, int? remaining, double? used,
        DateTimeOffset? reset, double? durationMinutes)
    {
        var row = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Margin = ScaleDynamic(new Padding(0, 3, 0, 2)),
            BackColor = Color.Transparent
        };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        var resetText = reset is null ? "" : $"  ·  {T("重置", "reset")} {FormatDateTime(reset)}";
        if (durationMinutes is double duration && duration > 0)
            resetText += $"  ·  {Duration(duration)}";
        row.Controls.Add(new Label { Text = label + resetText, AutoSize = true, ForeColor = Palette.Text, UseMnemonic = false }, 0, 0);
        row.Controls.Add(new Label
        {
            Text = Percent(remaining),
            AutoSize = true,
            ForeColor = QuotaColor(remaining),
            Font = new Font("Segoe UI Semibold", Font.Size, FontStyle.Bold),
            Anchor = AnchorStyles.Right
        }, 1, 0);
        body.Controls.Add(row);
        var progress = new ProgressBar
        {
            Minimum = 0,
            Maximum = 100,
            Value = Math.Clamp(remaining ?? 0, 0, 100),
            Height = ScaleDynamic(8),
            Dock = DockStyle.Top,
            Margin = ScaleDynamic(new Padding(0, 2, 0, 2))
        };
        body.Controls.Add(progress);
        if (used is double usedPercent)
            AddText(body, $"{T("已用", "Used")} {Math.Clamp(usedPercent, 0, 100):0.#}%", Palette.Secondary);
    }

    private void AddTileRow(TableLayoutPanel body, IReadOnlyList<(string Title, string Value, Color Color)> tiles)
    {
        if (tiles.Count == 0) return;
        var row = new TableLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            ColumnCount = tiles.Count,
            Margin = ScaleDynamic(new Padding(0, 5, 0, 4)),
            BackColor = Color.Transparent
        };
        for (var index = 0; index < tiles.Count; index++)
        {
            row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / tiles.Count));
            var tile = tiles[index];
            var tilePanel = new Panel
            {
                AutoSize = true,
                Dock = DockStyle.Fill,
                BackColor = ColorBlend(tile.Color),
                Padding = ScaleDynamic(new Padding(7, 6, 7, 6)),
                Margin = ScaleDynamic(new Padding(index == 0 ? 0 : 3, 0, index == tiles.Count - 1 ? 0 : 3, 0))
            };
            var stack = new TableLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, ColumnCount = 1, BackColor = Color.Transparent };
            stack.Controls.Add(new Label
            {
                Text = tile.Title,
                AutoSize = true,
                ForeColor = Palette.Secondary,
                Font = new Font("Segoe UI", Math.Max(8f, Font.Size - .7f)),
                UseMnemonic = false
            });
            stack.Controls.Add(new Label
            {
                Text = tile.Value,
                AutoSize = true,
                ForeColor = tile.Color,
                Font = new Font("Segoe UI Semibold", Font.Size + .5f, FontStyle.Bold),
                UseMnemonic = false
            });
            tilePanel.Controls.Add(stack);
            row.Controls.Add(tilePanel, index, 0);
        }
        body.Controls.Add(row);
    }

    private void AddCallout(TableLayoutPanel body, string text, Color accent, Color background)
    {
        var callout = new Panel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            BackColor = background,
            Padding = ScaleDynamic(new Padding(10, 8, 10, 8)),
            Margin = ScaleDynamic(new Padding(0, 4, 0, 4))
        };
        callout.Controls.Add(new Label
        {
            Text = text,
            AutoSize = true,
            MaximumSize = new Size(Math.Max(ScaleDynamic(300), _content.ClientSize.Width - ScaleDynamic(90)), 0),
            ForeColor = accent,
            Font = new Font("Segoe UI", Font.Size),
            UseMnemonic = false
        });
        body.Controls.Add(callout);
    }

    private void AddButtonRow(TableLayoutPanel body, params (string Text, Action Handler)[] actions)
    {
        var row = new FlowLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Dock = DockStyle.Top,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            Margin = ScaleDynamic(new Padding(0, 7, 0, 1)),
            BackColor = Color.Transparent
        };
        foreach (var action in actions)
        {
            var button = new Button
            {
                Text = action.Text,
                AutoSize = true,
                FlatStyle = FlatStyle.Flat,
                BackColor = Color.White,
                ForeColor = Palette.Blue,
                Margin = ScaleDynamic(new Padding(0, 0, 7, 3)),
                Padding = ScaleDynamic(new Padding(4, 1, 4, 1)),
                UseMnemonic = false
            };
            button.FlatAppearance.BorderColor = Color.FromArgb(197, 205, 215);
            button.FlatAppearance.MouseOverBackColor = Palette.BluePale;
            button.Click += (_, _) => action.Handler();
            row.Controls.Add(button);
        }
        body.Controls.Add(row);
    }

    private void ResizeCards()
    {
        var width = Math.Max(ScaleLogical(340),
            _content.ClientSize.Width - _content.Padding.Horizontal - (SystemInformation.VerticalScrollBarWidth + ScaleLogical(8)));
        foreach (Control control in _content.Controls)
        {
            // AutoSize/GrowAndShrink otherwise discards Width after ResumeLayout,
            // which collapses every card to a thin strip at high DPI.
            // Clear the previous lock first so growing a window is not clamped by
            // the old MaximumSize while the new MinimumSize is assigned.
            control.MinimumSize = Size.Empty;
            control.MaximumSize = Size.Empty;
            control.MinimumSize = new Size(width, 0);
            control.MaximumSize = new Size(width, 0);
            control.Width = width;
            foreach (var label in FindLabels(control))
            {
                if (label.MaximumSize.Width > 0)
                    label.MaximumSize = new Size(Math.Max(ScaleLogical(290), width - ScaleLogical(42)), 0);
            }
        }
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        // Programmatic controls have no designer AutoScaleDimensions pass. Reapply
        // logical sizes once DeviceDpi reflects the monitor that owns the handle.
        ApplyTextSize(force: true);
        LayoutHeader();
        ResizeCards();
    }

    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e);
        ApplyTextSize(force: true);
        LayoutHeader();
        ResizeCards();
        var area = Screen.FromRectangle(e.SuggestedRectangle).WorkingArea;
        var minimum = ScaleLogical(new Size(390, 560));
        MinimumSize = new Size(Math.Min(minimum.Width, area.Width), Math.Min(minimum.Height, area.Height));
        var width = Math.Min(Width, area.Width);
        var height = Math.Min(Height, area.Height);
        Bounds = new Rectangle(
            Math.Clamp(Left, area.Left, Math.Max(area.Left, area.Right - width)),
            Math.Clamp(Top, area.Top, Math.Max(area.Top, area.Bottom - height)),
            width,
            height);
    }

    private int ScaleLogical(int value) => value == 0 ? 0 : Math.Max(1,
        (int)Math.Round(value * DeviceDpi / 96d, MidpointRounding.AwayFromZero));

    private Size ScaleLogical(Size value) => new(ScaleLogical(value.Width), ScaleLogical(value.Height));

    private Padding ScaleLogical(Padding value) => new(
        ScaleLogical(value.Left), ScaleLogical(value.Top), ScaleLogical(value.Right), ScaleLogical(value.Bottom));

    // Controls built before the native handle are scaled once by WinForms from
    // the 96-DPI baseline. Controls rebuilt later need physical metrics now.
    private int ScaleDynamic(int value) => IsHandleCreated ? ScaleLogical(value) : value;

    private Padding ScaleDynamic(Padding value) => IsHandleCreated ? ScaleLogical(value) : value;

    private string ActionText()
    {
        if (_snapshot.ActiveSpeedWindow) return T("速蹬窗口开启", "Speed window open");
        if (_snapshot.ActiveEntitlementEvent) return T("官方权益事件", "Official entitlement");
        if (_snapshot.LimitReached) return T("本机限额中", "Local limit reached");
        if (IsRadarRetired()) return T("重置、额度与模型雷达", "Reset, quota and model radar");
        if (_snapshot.ResetCloseKey is not null)
            return T($"上次 reset：{FormatDateTime(_snapshot.WindowClosedAt ?? _snapshot.CheckedAt)}",
                $"Last reset: {FormatDateTime(_snapshot.WindowClosedAt ?? _snapshot.CheckedAt)}");
        return T("等待", "Waiting");
    }

    private string HeaderDetailText()
    {
        if (_snapshot.ActiveSpeedWindow)
            return T($"建议尽快使用 · 周额度 {Percent(_snapshot.WeeklyRemaining)}", $"Use soon · weekly {Percent(_snapshot.WeeklyRemaining)}");
        if (_snapshot.ActiveEntitlementEvent)
            return _snapshot.WindowTitle ?? T("CodexRadar 记录到官方权益事件", "CodexRadar recorded an official entitlement event");
        if (_snapshot.LimitReached) return T("本机 Codex 返回限额状态", "Local Codex reports a limit");
        if (IsRadarRetired())
            return T("CodexRadar 当前公开重置雷达 + 额度雷达 + Model IQ", "CodexRadar publishes reset radar + quota radar + Model IQ");
        return T("本机额度与 CodexRadar 公共数据", "Local quota and public CodexRadar data");
    }

    private bool ShouldEmphasizeSpeed() => _snapshot.ActiveSpeedWindow
        && (_snapshot.SpeedAlertKey is null || !string.Equals(_snapshot.SpeedAlertKey, _settings.DismissedSpeedAlertKey, StringComparison.Ordinal));

    private bool IsRadarRetired() => string.Equals(_snapshot.RadarStatus, "retired", StringComparison.OrdinalIgnoreCase)
                                    || string.Equals(_snapshot.WindowStatus, "retired", StringComparison.OrdinalIgnoreCase);

    private bool ShouldShowPrediction(PredictionInfo prediction)
    {
        if (IsRadarRetired()) return false;
        if (_snapshot.ActiveSpeedWindow || prediction.ShouldNotify == true) return true;
        return !string.Equals(prediction.Level, "low", StringComparison.OrdinalIgnoreCase);
    }

    private string RadarFocus()
    {
        if (IsRadarRetired()) return T("重置 + 额度 + Model IQ", "Reset + Quota + Model IQ");
        return _snapshot.WindowHuman ?? T("未知", "unknown");
    }

    private string PredictionLevelText(string? level) => level?.ToLowerInvariant() switch
    {
        "high" => T("高", "high"),
        "medium_high" or "medium-high" => T("中高", "medium-high"),
        "medium" => T("中", "medium"),
        "medium_low" or "medium-low" => T("中低", "medium-low"),
        "low" => T("低", "low"),
        _ => T("未知", "unknown")
    };

    private string QuotaBasisText(string? basis)
    {
        if (string.IsNullOrWhiteSpace(basis)) return T("未知", "unknown");
        var normalized = basis.ToLowerInvariant();
        if (normalized.Contains("measured"))
        {
            if (normalized.Contains("7d")) return T("7d 实测", "7d measured");
            if (normalized.Contains("5h")) return T("5h 实测", "5h measured");
            return T("实测", "measured");
        }
        if (normalized.Contains("model") || normalized.Contains('/')) return T("推测", "estimate");
        return basis;
    }

    private string PaceExplanation(QuotaPacingSnapshot pace)
    {
        var prefix = T($"窗口已过 {pace.RoundedElapsed}%", $"{pace.RoundedElapsed}% of the window has elapsed");
        var delta = Math.Abs(pace.RoundedRemainingDelta);
        var action = pace.RoundedRemainingDelta >= 3
            ? T($"实际比建议多 {delta}%，可以多用一点。", $"Actual is {delta}% above target, so you can spend more.")
            : pace.RoundedRemainingDelta <= -3
                ? T($"实际比建议少 {delta}%，建议放慢一点。", $"Actual is {delta}% below target, so slow down a bit.")
                : T("实际剩余基本贴近节奏。", "Actual remaining is close to pace.");
        return $"{prefix} · {PacingStrategyLabel(pace.Strategy)} · {action}";
    }

    private string PacingStrategyLabel(QuotaPacingStrategy strategy) => strategy switch
    {
        QuotaPacingStrategy.SevenDay => T("每日预算", "Daily"),
        QuotaPacingStrategy.ReserveTwenty => T("留余 20%", "Reserve 20%"),
        QuotaPacingStrategy.WorkdayWeighted => T("工作日权重", "Workday weighted"),
        QuotaPacingStrategy.FrontLoaded => T("先用策略", "Front-loaded"),
        _ => T("按 reset 时间", "Reset-window time")
    };

    private string MetricLabel(StatusMetric metric) => metric switch
    {
        StatusMetric.ShortQuota => "5h",
        StatusMetric.QuotaPace => T("应剩", "Pace"),
        StatusMetric.CodexIq => "IQ",
        StatusMetric.Signal => T("质量", "Signal"),
        _ => T("周额度", "Weekly")
    };

    private string UpdateStatusText() => _updateStatus.Phase switch
    {
        AppUpdatePhase.Checking => T("正在检查", "Checking"),
        AppUpdatePhase.UpToDate => T("已是最新版", "Up to date"),
        AppUpdatePhase.Available => T("发现新版", "Update available"),
        AppUpdatePhase.Downloading => T("正在下载并校验", "Downloading and verifying"),
        AppUpdatePhase.Installing => T("正在安装", "Installing"),
        AppUpdatePhase.Failed => T("更新失败", "Update failed"),
        _ => T("等待自动检查", "Waiting for auto-check")
    };

    private string ResetFailureHeading(ResetCreditFailureInfo failure)
    {
        if (failure.Automatic && _snapshot.ResetCreditsCheckedAt is not null)
            return T("自动刷新失败，已保留上次结果", "Auto refresh failed; keeping last result");
        return failure.Automatic ? T("自动查询暂时失败", "Auto check failed for now") : T("查询失败", "Check failed");
    }

    private string ResetFailureMessage(ResetCreditFailureInfo failure) => (failure.Kind ?? "").ToLowerInvariant() switch
    {
        "authfilemissing" or "missing_auth" or "auth" => T("没有找到本机 Codex 登录文件，可能还没有在 Codex 里登录。",
            "Local Codex auth was not found. You may not be signed in to Codex yet."),
        "invalidauthfile" => T("本机 Codex 登录文件不是可读取的 JSON。", "The local Codex auth file is not readable JSON."),
        "accesstokenmissing" => T("本机 Codex 登录文件里没有 access token。", "The local Codex auth file does not contain an access token."),
        "unauthorized" => T("ChatGPT 拒绝了请求，通常是登录态过期或账号态变化。",
            "ChatGPT rejected the request, usually because the sign-in expired or the account state changed."),
        "network" => T("网络请求没有完成，可能是当前网络、代理或 ChatGPT 临时不可达。",
            "The request did not finish. The network, proxy, or ChatGPT may be temporarily unavailable."),
        "service" or "http" => T("ChatGPT reset credits 接口返回了服务错误。", "The ChatGPT reset credits endpoint returned a service error."),
        "shape" or "parse" or "responsechanged" => T("接口返回内容和预期不一致，可能是 ChatGPT 调整了 reset credits 数据格式。",
            "The response did not match the expected shape. ChatGPT may have changed the reset credits format."),
        _ => T($"遇到未知错误：{failure.Detail}", $"Unexpected error: {failure.Detail}")
    };

    private string ResetFailureRecovery(ResetCreditFailureInfo failure) => (failure.Kind ?? "").ToLowerInvariant() switch
    {
        "authfilemissing" or "missing_auth" or "auth" or "invalidauthfile" or "accesstokenmissing" =>
            T("打开 Codex 并确认已登录，然后点“立即刷新”。", "Open Codex, confirm you are signed in, then click Refresh now."),
        "unauthorized" => T("重新登录 Codex 后再刷新；旧缓存不会被清掉。", "Sign in to Codex again, then refresh. The old cache is kept."),
        "network" or "service" or "http" => T("稍后会自动重试，也可以现在手动刷新；这不会影响状态栏额度。",
            "It will retry later, or you can refresh now. This does not affect taskbar quota."),
        "shape" or "parse" or "responsechanged" => T("可以先用“复制安全 Prompt”兜底；如果持续失败，应用需要适配新接口。",
            "Use Copy safe Prompt as a fallback. If it persists, the app needs an endpoint update."),
        _ => T("可以稍后重试；旧缓存仍会保留。", "Try again later; the old cache is kept.")
    };

    private string ResetCreditStatus(ResetCredit credit, bool expired)
    {
        var normalized = credit.Status?.ToLowerInvariant() ?? "";
        if (credit.RedeemedAt is not null || normalized.Contains("redeem", StringComparison.Ordinal))
            return T("已使用", "used");
        if (expired) return T("已过期", "expired");
        return normalized switch
        {
            "available" => T("可用", "available"),
            "redeemed" => T("已兑换", "redeemed"),
            "redeeming" or "in_progress" => T("兑换中", "redeeming"),
            _ => string.IsNullOrWhiteSpace(credit.Status) ? T("未知", "unknown") : credit.Status
        };
    }

    private string ResetCreditProtectionStatusText(
        ResetCreditProtectionStatus status)
    {
        var expiry = status.ExpiresAt is { } expiresAt
            ? $" · {T("过期", "expires")} {FormatDateTime(expiresAt)}"
            : "";
        return status.Kind switch
        {
            ResetCreditProtectionStatusKind.Enabling =>
                T("正在核对账号、完整卡集合与本机授权…",
                    "Verifying account, complete card set, and local authorization…"),
            ResetCreditProtectionStatusKind.Checking =>
                T("正在安全检查自动使用计划…",
                    "Checking the auto-use plan safely…"),
            ResetCreditProtectionStatusKind.NoCredits =>
                T("自动使用已开启；当前没有可用重置卡。",
                    "Auto-use is on; there are no available reset credits."),
            ResetCreditProtectionStatusKind.PreviewNoCredits =>
                T("只读检查完成：当前没有可用重置卡。",
                    "Read-only check complete: no reset credits are available."),
            ResetCreditProtectionStatusKind.Preview =>
                $"{T("只读计划", "Read-only plan")} · "
                + (status.ReadyNow
                    ? T("现在已进入安全使用窗口", "safe-use window is open now")
                    : $"{T("计划", "planned")} {FormatDateTime(status.ActionAt)}")
                + expiry,
            ResetCreditProtectionStatusKind.Scheduled =>
                $"{T("自动使用已开启", "Auto-use is on")} · "
                + $"{T("计划", "planned")} {FormatDateTime(status.ActionAt)}"
                + expiry,
            ResetCreditProtectionStatusKind.WaitingForUsage =>
                T("上次尝试确认未消耗，将在安全窗口内重试。",
                    "The last attempt was confirmed not consumed; retrying inside the safe window.")
                + expiry,
            ResetCreditProtectionStatusKind.Using =>
                T("正在发送一次受本机授权保护的使用请求…",
                    "Sending one locally authorized consume request…")
                + expiry,
            ResetCreditProtectionStatusKind.Reconciling =>
                T("存在未决尝试；当前只读核对 Codex 状态，不会切换到其他卡。",
                    "An attempt is unresolved; Codex is being reconciled read-only without switching cards.")
                + expiry,
            ResetCreditProtectionStatusKind.Succeeded =>
                T("Codex 已确认该重置卡处于已使用状态。",
                    "Codex confirmed that the reset credit is used.")
                + expiry,
            ResetCreditProtectionStatusKind.Missed =>
                T("卡已过期，但无法确认自动使用是否完成，请检查。",
                    "The credit expired before auto-use could be confirmed; review it.")
                + expiry,
            ResetCreditProtectionStatusKind.Blocked =>
                ResetCreditProtectionBlockedText(status),
            _ => T(
                "到期前自动使用已关闭；“只读检查计划”不会使用任何卡。",
                "Expiry auto-use is off; Read-only plan never consumes a credit.")
        };
    }

    private string ResetCreditProtectionBlockedText(
        ResetCreditProtectionStatus status) =>
        status.BlockReason switch
        {
            ResetCreditProtectionBlockReason.AccountIdentityUnavailable =>
                T("无法取得可绑定的 Codex 账号身份，未启用。",
                    "A bindable Codex account identity is unavailable; auto-use was not enabled."),
            ResetCreditProtectionBlockReason.AccountChanged =>
                T("Codex 账号已变化，自动使用已关闭。",
                    "The Codex account changed; auto-use was turned off."),
            ResetCreditProtectionBlockReason.DetailsUnavailable =>
                T("Codex 未返回完整重置卡明细；为安全起见不会自动使用。",
                    "Codex did not return complete reset-credit details; auto-use is blocked."),
            ResetCreditProtectionBlockReason.DetailsIncomplete =>
                T($"卡明细不完整（{status.AvailableDetails}/{status.AvailableCount}）；不会自动使用。",
                    $"Credit details are incomplete ({status.AvailableDetails}/{status.AvailableCount}); auto-use is blocked."),
            ResetCreditProtectionBlockReason.NoSupportedExpiringCredits =>
                T("没有可安全自动使用的 Codex 到期卡。",
                    "No supported expiring Codex credit can be auto-used safely."),
            ResetCreditProtectionBlockReason.CodexUnavailable =>
                T("找不到可用的 Codex app-server。",
                    "A usable Codex app-server was not found."),
            ResetCreditProtectionBlockReason.SignedOut =>
                T("Codex 登录态不可验证，自动使用已关闭。",
                    "The Codex sign-in cannot be verified; auto-use was turned off."),
            ResetCreditProtectionBlockReason.UnsupportedCodex =>
                T("当前 Codex 版本不支持重置卡使用接口。",
                    "This Codex version does not support the reset-credit consume API."),
            ResetCreditProtectionBlockReason.AnotherProcess =>
                T("另一个 Codex Radar 进程正在处理该功能，请稍后重试。",
                    "Another Codex Radar process is handling this feature; retry shortly."),
            ResetCreditProtectionBlockReason.JournalUnavailable =>
                T("本机授权或对账记录不可验证，已安全关闭自动使用。",
                    "The local authorization or reconciliation record cannot be verified; auto-use was disabled."),
            ResetCreditProtectionBlockReason.CreditNotAuthorized =>
                T("当前卡集合已不再等于确认时的集合，授权已撤销。",
                    "The current card set no longer matches the confirmed set; authorization was revoked."),
            ResetCreditProtectionBlockReason.ClockChanged =>
                T("系统时间连续性变化超过 5 秒安全阈值，授权已撤销。",
                    "Clock continuity changed beyond the 5-second safety threshold; authorization was revoked."),
            ResetCreditProtectionBlockReason.PreviewMode =>
                T("调试预览模式禁止破坏性操作。",
                    "Destructive actions are disabled in preview mode."),
            _ => T("安全检查失败；没有发送自动使用请求。",
                "A safety check failed; no auto-use request was sent.")
        };

    private static Color ResetCreditProtectionStatusColor(
        ResetCreditProtectionStatus status) => status.Kind switch
    {
        ResetCreditProtectionStatusKind.Succeeded
            or ResetCreditProtectionStatusKind.NoCredits
            or ResetCreditProtectionStatusKind.Scheduled => Palette.Green,
        ResetCreditProtectionStatusKind.Missed
            or ResetCreditProtectionStatusKind.Blocked => Palette.Red,
        ResetCreditProtectionStatusKind.Using
            or ResetCreditProtectionStatusKind.Reconciling
            or ResetCreditProtectionStatusKind.WaitingForUsage => Palette.Orange,
        _ => Palette.Blue
    };

    private Color HeaderColor()
    {
        if (_snapshot.ActiveSpeedWindow) return Palette.Red;
        if (_snapshot.ActiveEntitlementEvent) return Palette.Teal;
        if (_snapshot.LimitReached) return Palette.Orange;
        return _snapshot.Health switch
        {
            HealthLevel.Critical => Palette.Red,
            HealthLevel.Warning => Palette.Orange,
            HealthLevel.Good => Palette.Blue,
            _ => Palette.Gray
        };
    }

    private Color QuotaColor(int? remaining)
    {
        if (_snapshot.LimitReached || remaining <= 15) return Palette.Red;
        if (remaining <= 30) return Palette.Orange;
        return remaining is null ? Palette.Gray : Palette.Green;
    }

    private Color PaceColor() => _snapshot.QuotaPacing?.Status switch
    {
        QuotaPacingStatus.UnderTarget => Palette.Green,
        QuotaPacingStatus.OnPace => Palette.Teal,
        QuotaPacingStatus.OverTarget => Palette.Orange,
        _ => Palette.Gray
    };

    private static Color IqColor(double? score, string? status)
    {
        if (score is null) return Palette.Gray;
        if (score < 60) return Palette.Red;
        if (string.Equals(status, "red", StringComparison.OrdinalIgnoreCase) || score < 90) return Palette.Orange;
        return Palette.Green;
    }

    private static Color PredictionColor(string? level) => level?.ToLowerInvariant() switch
    {
        "high" => Palette.Red,
        "medium_high" or "medium-high" or "medium" => Palette.Orange,
        _ => Palette.Teal
    };

    private string T(string zh, string en) => _settings.Chinese ? zh : en;
    private static string Percent(int? value) => value is int number ? $"{number}%" : "--";
    private static string Money(double? value) => value is double number ? $"${number:0.00}" : "--";
    private static string FormatDateTime(DateTimeOffset? value) => value?.ToLocalTime().ToString("yyyy-MM-dd HH:mm") ?? "--";
    private static string Duration(double minutes) => minutes >= 1440 ? $"{minutes / 1440:0.#}d" : minutes >= 60 ? $"{minutes / 60:0.#}h" : $"{minutes:0}m";

    private static string Probability(double? value)
    {
        if (value is not double number || !double.IsFinite(number)) return "--";
        if (number <= 1) number *= 100;
        return $"{Math.Round(Math.Clamp(number, 0, 100), MidpointRounding.AwayFromZero):0}%";
    }

    private string TimeLeft(DateTimeOffset expiry)
    {
        var span = expiry - DateTimeOffset.Now;
        if (span <= TimeSpan.Zero) return T("已到期", "expired");
        if (span.TotalDays >= 1) return T($"{(int)span.TotalDays} 天 {span.Hours} 小时", $"{(int)span.TotalDays}d {span.Hours}h");
        if (span.TotalHours >= 1) return T($"{(int)span.TotalHours} 小时 {span.Minutes} 分", $"{(int)span.TotalHours}h {span.Minutes}m");
        return T($"{Math.Max(1, span.Minutes)} 分钟", $"{Math.Max(1, span.Minutes)}m");
    }

    private static Color ColorBlend(Color color) => Color.FromArgb(
        255,
        245 + (color.R * 10 / 255),
        245 + (color.G * 10 / 255),
        245 + (color.B * 10 / 255));

    private static IEnumerable<Label> FindLabels(Control root) => root.Controls.Cast<Control>()
        .SelectMany(control => control is Label label ? new[] { label } : FindLabels(control));

    private void SetFooterText(string name, string text)
    {
        if (_footer.Controls.Find(name, false).FirstOrDefault() is Button button) button.Text = text;
    }

    private void CopyPrompt(string prompt)
    {
        try
        {
            Clipboard.SetText(prompt);
            ShowTransientTitle(T("Prompt 已复制", "Prompt copied"));
        }
        catch
        {
            MessageBox.Show(this, T("无法访问剪贴板，请稍后重试。", "Clipboard is unavailable; try again."), Text,
                MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    private void ShowTransientTitle(string message)
    {
        _transientTimer?.Stop();
        _transientTimer?.Dispose();
        _updated.Text = message;
        _transientTimer = new System.Windows.Forms.Timer { Interval = 1800 };
        _transientTimer.Tick += (_, _) =>
        {
            _transientTimer?.Stop();
            _transientTimer?.Dispose();
            _transientTimer = null;
            if (!IsDisposed) _updated.Text = UpdatedText();
        };
        _transientTimer.Start();
    }

    private string UpdatedText() => $"{T("数据获取", "Fetched")} {FormatDateTime(_snapshot.RefreshedAt)}  ·  " +
                                    T("本机与 CodexRadar", "Local + CodexRadar");

    private static void OpenCodex()
    {
        try
        {
            Process.Start(new ProcessStartInfo("codex://") { UseShellExecute = true });
            return;
        }
        catch { }
        Open(CodexWebUrl);
    }

    private static void Open(string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps) return;
        try { Process.Start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true }); } catch { }
    }

    private static string ClosestEdge(Point point, Rectangle bounds)
    {
        var distances = new Dictionary<string, int>
        {
            ["top"] = Math.Abs(point.Y - bounds.Top),
            ["bottom"] = Math.Abs(bounds.Bottom - point.Y),
            ["left"] = Math.Abs(point.X - bounds.Left),
            ["right"] = Math.Abs(bounds.Right - point.X)
        };
        return distances.MinBy(pair => pair.Value).Key;
    }

    private void OnFormClosing(object? sender, FormClosingEventArgs e)
    {
        if (_allowClose) return;
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _transientTimer?.Stop();
            _transientTimer?.Dispose();
            _transientTimer = null;
        }
        base.Dispose(disposing);
    }

    private static class Palette
    {
        public static readonly Color Text = Color.FromArgb(38, 40, 43);
        public static readonly Color Secondary = Color.FromArgb(96, 101, 109);
        public static readonly Color Blue = Color.FromArgb(0, 95, 184);
        public static readonly Color BluePale = Color.FromArgb(238, 246, 253);
        public static readonly Color Teal = Color.FromArgb(0, 119, 110);
        public static readonly Color Green = Color.FromArgb(16, 124, 65);
        public static readonly Color Orange = Color.FromArgb(157, 93, 0);
        public static readonly Color OrangePale = Color.FromArgb(255, 247, 232);
        public static readonly Color Red = Color.FromArgb(196, 43, 28);
        public static readonly Color RedPale = Color.FromArgb(255, 241, 239);
        public static readonly Color Purple = Color.FromArgb(91, 65, 153);
        public static readonly Color PurplePale = Color.FromArgb(246, 242, 253);
        public static readonly Color Gray = Color.FromArgb(92, 96, 102);
    }

    private sealed class BufferedPanel : Panel
    {
        public BufferedPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                     | ControlStyles.ResizeRedraw, true);
            DoubleBuffered = true;
        }
    }

    private sealed class BufferedFlowLayoutPanel : FlowLayoutPanel
    {
        public BufferedFlowLayoutPanel()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                     | ControlStyles.ResizeRedraw, true);
            DoubleBuffered = true;
        }
    }

    private sealed class FluentButton : Button
    {
        private bool _hovered;
        private bool _pressed;

        public int CornerRadius { get; init; } = 8;

        public FluentButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint
                     | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            FlatStyle = FlatStyle.Flat;
            FlatAppearance.BorderSize = 0;
            UseVisualStyleBackColor = false;
            BackColor = Color.White;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var canvas = Parent?.BackColor ?? Color.FromArgb(248, 249, 251);
            e.Graphics.Clear(canvas);
            if (ClientSize.Width < 2 || ClientSize.Height < 2) return;

            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
            var fill = !Enabled ? Color.FromArgb(245, 246, 248)
                : _pressed ? Color.FromArgb(222, 235, 248)
                : _hovered ? Color.FromArgb(235, 244, 252)
                : Color.White;
            var border = Focused ? Color.FromArgb(0, 95, 184) : Color.FromArgb(203, 208, 215);

            using var path = RoundedPath(bounds);
            using var brush = new SolidBrush(fill);
            using var pen = new Pen(border, Focused ? Math.Max(1.5f, DeviceDpi / 96f) : 1f);
            e.Graphics.FillPath(brush, path);
            e.Graphics.DrawPath(pen, path);

            var textBounds = Rectangle.Inflate(bounds, -ScaleCorner(6), -ScaleCorner(2));
            TextRenderer.DrawText(e.Graphics, Text, Font, textBounds,
                Enabled ? ForeColor : SystemColors.GrayText,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
                | TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding);
        }

        private GraphicsPath RoundedPath(Rectangle bounds)
        {
            var path = new GraphicsPath();
            var diameter = Math.Min(ScaleCorner(CornerRadius * 2), Math.Min(bounds.Width, bounds.Height));
            if (diameter < 2)
            {
                path.AddRectangle(bounds);
                return path;
            }
            path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
            path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
            path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            return path;
        }

        private int ScaleCorner(int value) => Math.Max(1,
            (int)Math.Round(value * DeviceDpi / 96d, MidpointRounding.AwayFromZero));

        protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hovered = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hovered = false; _pressed = false; Invalidate(); }
        protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); if (e.Button == MouseButtons.Left) { _pressed = true; Invalidate(); } }
        protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); if (_pressed) { _pressed = false; Invalidate(); } }
        protected override void OnKeyDown(KeyEventArgs e) { base.OnKeyDown(e); if (e.KeyCode is Keys.Space or Keys.Enter) { _pressed = true; Invalidate(); } }
        protected override void OnKeyUp(KeyEventArgs e) { base.OnKeyUp(e); if (_pressed) { _pressed = false; Invalidate(); } }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); _pressed = false; Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
    }

    private sealed class RoundedPanel : Panel
    {
        public Color BorderColor { get; init; } = Color.FromArgb(221, 224, 229);
        public int CornerDiameter { get; init; } = 11;

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Width < 2 || Height < 2) return;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var pen = new Pen(BorderColor);
            var rect = new Rectangle(0, 0, Width - 1, Height - 1);
            using var path = new GraphicsPath();
            var scaledDiameter = Math.Max(1,
                (int)Math.Round(CornerDiameter * DeviceDpi / 96d, MidpointRounding.AwayFromZero));
            var diameter = Math.Min(scaledDiameter, Math.Min(rect.Width, rect.Height));
            if (diameter < 1) return;
            path.AddArc(rect.Left, rect.Top, diameter, diameter, 180, 90);
            path.AddArc(rect.Right - diameter, rect.Top, diameter, diameter, 270, 90);
            path.AddArc(rect.Right - diameter, rect.Bottom - diameter, diameter, diameter, 0, 90);
            path.AddArc(rect.Left, rect.Bottom - diameter, diameter, diameter, 90, 90);
            path.CloseFigure();
            e.Graphics.DrawPath(pen, path);
        }

        protected override void OnResize(EventArgs eventArgs)
        {
            base.OnResize(eventArgs);
            Invalidate();
        }
    }
}
