using System.Diagnostics;

namespace CodexRadar.Windows;

internal sealed class SettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly TabControl _tabs = new() { Dock = DockStyle.Fill };
    private readonly Label _updateStatus = new() { AutoSize = true, MaximumSize = new Size(430, 0), ForeColor = Color.DimGray };
    private AppUpdateStatus _lastUpdateStatus = new(AppUpdatePhase.Idle);
    private bool _loading;
    public event EventHandler? SettingsChanged;
    public event EventHandler? CheckUpdatesRequested;

    public SettingsForm(AppSettings settings)
    {
        SuspendLayout();
        _settings = settings;
        Text = T("Codex Radar Sentinel · 设置", "Codex Radar Sentinel · Settings");
        AutoScaleDimensions = new SizeF(96f, 96f);
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(510, 590);
        MinimumSize = new Size(480, 540);
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = false;
        Font = new Font(
            "Segoe UI",
            settings.TextSize switch
            {
                DashboardTextSize.Medium => 9f,
                DashboardTextSize.Large => 10f,
                _ => 11f
            });
        FormBorderStyle = FormBorderStyle.SizableToolWindow;
        Build();
        ResumeLayout(true);
    }

    public void SetUpdateStatus(AppUpdateStatus status)
    {
        _lastUpdateStatus = status;
        _updateStatus.Text = status.Phase switch
        {
            AppUpdatePhase.Checking => T("正在检查更新…", "Checking for updates…"),
            AppUpdatePhase.UpToDate => T("已是最新版本", "Up to date"),
            AppUpdatePhase.Available => T($"发现新版本 {status.Version}", $"Update {status.Version} is available"),
            AppUpdatePhase.Downloading => T($"正在下载 {status.Version}…", $"Downloading {status.Version}…"),
            AppUpdatePhase.Installing => T($"正在安装 {status.Version}；应用将自动重启", $"Installing {status.Version}; the app will restart"),
            AppUpdatePhase.Failed => T($"更新失败：{status.Message}", $"Update failed: {status.Message}"),
            _ => T("默认每 6 小时检查经过 SHA256 验证的 Windows 更新。", "Checks verified Windows updates every 6 hours by default.")
        };
        _updateStatus.ForeColor = status.Phase == AppUpdatePhase.Failed ? Color.Firebrick : Color.DimGray;
    }

    private void Build()
    {
        _loading = true;
        _tabs.SuspendLayout();
        try
        {
            _updateStatus.Parent?.Controls.Remove(_updateStatus);
            foreach (var page in _tabs.TabPages.Cast<TabPage>().ToArray())
            {
                _tabs.TabPages.Remove(page);
                page.Dispose();
            }
            if (!Controls.Contains(_tabs)) Controls.Add(_tabs);
            _tabs.TabPages.Add(BuildGeneral());
            _tabs.TabPages.Add(BuildTray());
            _tabs.TabPages.Add(BuildPace());
            _tabs.TabPages.Add(BuildPreview());
            _tabs.TabPages.Add(BuildUpdates());
        }
        finally
        {
            _tabs.ResumeLayout(true);
            _loading = false;
        }
        SetUpdateStatus(_lastUpdateStatus);
    }

    public void ReloadLanguage()
    {
        if (IsDisposed) return;
        var selectedIndex = _tabs.SelectedIndex;
        Text = T("Codex Radar Sentinel · 设置", "Codex Radar Sentinel · Settings");
        Build();
        if (_tabs.TabCount > 0)
            _tabs.SelectedIndex = Math.Clamp(
                selectedIndex,
                0,
                _tabs.TabCount - 1);
    }

    private TabPage BuildGeneral()
    {
        var page = Page(T("常规", "General"));
        var body = Stack(page);
        body.Controls.Add(Heading(T("显示与提醒", "Display & alerts")));
        body.Controls.Add(ComboRow(T("语言", "Language"), new[] { "中文", "English" }, _settings.Chinese ? 0 : 1, index =>
        {
            _settings.Chinese = index == 0; Changed();
        }));
        body.Controls.Add(ComboRow(T("面板字号", "Panel text size"), new[] { "M", "L", "XL" }, (int)_settings.TextSize, index =>
        {
            _settings.TextSize = (DashboardTextSize)index; Changed();
        }));
        body.Controls.Add(Check(T("Prediction 提醒", "Prediction alerts"), _settings.PredictionNotifications, value => { _settings.PredictionNotifications = value; Changed(); }));
        body.Controls.Add(Check(T("IQ 提醒", "IQ alerts"), _settings.IqNotifications, value => { _settings.IqNotifications = value; Changed(); }));
        body.Controls.Add(Check(T("额外提示音", "Additional app sound"), _settings.NotificationSound, value => { _settings.NotificationSound = value; Changed(); }));
        body.Controls.Add(Check(T("自动查询重置卡", "Auto-check reset credits"), _settings.AutoResetCreditCheck, value => { _settings.AutoResetCreditCheck = value; Changed(); }));
        body.Controls.Add(Check(T("自动更新", "Automatic updates"), _settings.AutomaticUpdates, value => { _settings.AutomaticUpdates = value; Changed(); }));
        body.Controls.Add(Check(T("登录 Windows 时启动", "Start with Windows"), AppSettings.StartsWithWindows, value =>
        {
            try { AppSettings.StartsWithWindows = value; } catch (Exception ex) { MessageBox.Show(ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Warning); }
            Changed();
        }));
        return page;
    }

    private TabPage BuildTray()
    {
        var page = Page(T("状态栏", "Status"));
        var body = Stack(page);
        body.Controls.Add(Heading(T("Windows 状态显示", "Windows status display")));
        body.Controls.Add(ComboRow(T("显示位置", "Location"), new[]
        {
            T("通知区域图标（当前位置）", "Notification-area icon"),
            T("任务栏文字（输入法左侧）", "Taskbar text (left of input)")
        }, (int)_settings.StatusDisplayMode, index =>
        {
            _settings.StatusDisplayMode = (StatusDisplayMode)index; Changed();
        }));
        body.Controls.Add(Heading(T("摘要内容", "Summary segments")));
        var metrics = new CheckedListBox
        {
            Height = ScaleDynamic(105), Width = ScaleDynamic(440), CheckOnClick = true,
            BorderStyle = BorderStyle.FixedSingle
        };
        var labels = new[] { T("周额度", "Weekly"), "5h", T("应剩", "Pace"), "IQ", T("质量", "Quality") };
        var values = Enum.GetValues<StatusMetric>();
        for (var i = 0; i < values.Length; i++) metrics.Items.Add(labels[i], _settings.SelectedStatusMetrics.Contains(values[i]));
        metrics.ItemCheck += (_, e) => BeginInvoke(() =>
        {
            var next = values.Where((_, i) => metrics.GetItemChecked(i)).ToList();
            if (next.Count == 0)
            {
                metrics.SetItemChecked(e.Index, true);
                return;
            }
            _settings.SelectedStatusMetrics = next; Changed();
        });
        body.Controls.Add(metrics);
        body.Controls.Add(Check(T("原始 IQ 显示小数", "Decimal raw IQ"), _settings.PreciseIq, value => { _settings.PreciseIq = value; Changed(); }));
        body.Controls.Add(Check(T("显示百分号 %", "Show percent symbol"), _settings.ShowPercentSymbol, value => { _settings.ShowPercentSymbol = value; Changed(); }));
        body.Controls.Add(ComboRow(T("IQ 显示", "IQ display"), new[] { "Raw", "÷10 int", "÷10 decimal" }, (int)_settings.IqDisplayMode,
            index => { _settings.IqDisplayMode = (StatusBarIqDisplayMode)index; Changed(); }));
        body.Controls.Add(ComboRow(T("分隔符", "Separator"), new[] { "/", "⁄", T("细空格", "Thin space"), "·", T("无", "None") }, (int)_settings.Separator,
            index => { _settings.Separator = (StatusBarSeparator)index; Changed(); }));
        body.Controls.Add(ComboRow(T("摘要留白", "Summary padding"), new[] { T("系统", "System"), T("紧凑", "Compact"), T("极窄", "Tight") }, (int)_settings.HorizontalPadding,
            index => { _settings.HorizontalPadding = (StatusBarHorizontalPadding)index; Changed(); }));
        body.Controls.Add(ComboRow(T("摘要字体", "Summary font"), new[] { T("正常", "Normal"), T("紧凑", "Compact"), T("更小", "Tiny") }, (int)_settings.FontScale,
            index => { _settings.FontScale = (StatusBarFontScale)index; Changed(); }));
        body.Controls.Add(Caption(T(
            "“任务栏文字”会把同一组摘要常驻显示在输入法/通知区域左侧；左键打开面板，右键可退出。它使用安全的无激活窗口，不修改 Explorer。选择“通知区域图标”时，图标是否收进折叠菜单由 Windows 决定。",
            "Taskbar text keeps the same summary visible immediately left of the input/notification area; left-click opens the dashboard and right-click includes Exit. It uses a safe no-activate window and does not modify Explorer. Windows decides whether the notification-area icon is placed in overflow.")));
        return page;
    }

    private TabPage BuildPace()
    {
        var page = Page(T("节奏", "Pace"));
        var body = Stack(page);
        body.Controls.Add(Heading(T("应剩计算策略", "Target remaining rule")));
        body.Controls.Add(ComboRow(T("策略", "Rule"), new[]
        {
            T("按时间", "Time"), T("每日", "Daily"), T("留余 20%", "Reserve 20%"), T("工作日", "Workdays"), T("先用", "Front-load")
        }, (int)_settings.PacingStrategy, index => { _settings.PacingStrategy = (QuotaPacingStrategy)index; Changed(); }));
        body.Controls.Add(Check(T("使用 2026 中国节假日/调休", "Use 2026 China holidays"), _settings.UseChinaHolidays,
            value => { _settings.UseChinaHolidays = value; Changed(); }));
        body.Controls.Add(Caption(T(
            "按时间：连续比例；每日：按天分配；留余：最后阶段释放 20%；工作日：工作日权重 1、周末/假日 0.35；先用：前半程使用 70%。策略同时影响面板“建议剩余”和可选状态摘要段。",
            "Time is continuous; Daily budgets by day; Reserve releases 20% near the end; Workdays weight weekdays as 1 and weekends/holidays as 0.35; Front-load spends 70% in the first half. The rule affects both Target left and the optional status segment.")));
        return page;
    }

    private TabPage BuildPreview()
    {
        var page = Page(T("预览", "Preview"));
        var body = Stack(page);
        body.Controls.Add(Heading(T("本地界面预览", "Local UI preview")));
        body.Controls.Add(ComboRow(T("状态", "State"), new[] { "Live", T("正常", "Normal"), T("低 IQ", "Low IQ"), T("速蹬", "Speed"), "Reset", T("限额", "Limit") },
            (int)_settings.Preview, index => { _settings.Preview = (DashboardPreview)index; SettingsChanged?.Invoke(this, EventArgs.Empty); }));
        body.Controls.Add(Caption(T("预览只改变显示，不会触发通知，也不会覆盖实时数据。", "Preview affects display only; it does not send notifications or replace live data.")));
        return page;
    }

    private TabPage BuildLayout()
    {
        var page = Page(T("布局", "Layout"));
        var body = Stack(page);
        body.Controls.Add(Heading(T("自定义面板布局", "Customize dashboard layout")));
        body.Controls.Add(Caption(T(
            "调整模块顺序，并在同一行选择是否显示、是否默认展开。子项跟随所属模块缩进显示。",
            "Reorder sections, then choose on the same row what appears and opens by default. Nested items stay indented beneath their section.")));

        var editor = new FlowLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Width = ScaleDynamic(450),
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Margin = ScaleDynamic(new Padding(0, 2, 0, 2)),
            BackColor = Color.Transparent
        };
        body.Controls.Add(editor);

        var actions = new FlowLayoutPanel
        {
            AutoSize = true,
            Width = ScaleDynamic(450),
            Margin = ScaleDynamic(new Padding(0, 8, 0, 0))
        };
        body.Controls.Add(actions);

        void ReloadRows()
        {
            var previousLoading = _loading;
            _loading = true;
            editor.SuspendLayout();
            try
            {
                foreach (var control in editor.Controls
                             .Cast<Control>()
                             .ToArray())
                    control.Dispose();
                editor.Controls.Clear();

                var order = _settings.DashboardSectionOrder;
                for (var index = 0; index < order.Count; index++)
                {
                    var section = order[index];
                    var row = LayoutEditorRow(
                        LayoutEditorLabel(section),
                        _settings.IsDashboardSectionVisible(section),
                        _settings.IsDashboardSectionExpanded(section),
                        canMoveUp: index > 0,
                        canMoveDown: index < order.Count - 1,
                        nested: false);
                    var show = (CheckBox)row.Controls["show"]!;
                    var startOpen =
                        (CheckBox)row.Controls["startOpen"]!;
                    var moveUp =
                        (Button)row.Controls["moveUp"]!;
                    var moveDown =
                        (Button)row.Controls["moveDown"]!;

                    show.CheckedChanged += (_, _) =>
                    {
                        if (_loading) return;
                        _settings.SetDashboardSectionVisible(
                            section,
                            show.Checked);
                        startOpen.Enabled = show.Checked;
                        Changed();
                    };
                    startOpen.CheckedChanged += (_, _) =>
                    {
                        if (_loading) return;
                        _settings.SetDashboardSectionExpanded(
                            section,
                            startOpen.Checked);
                        Changed();
                    };
                    moveUp.Click += (_, _) =>
                    {
                        _settings.MoveDashboardSection(section, -1);
                        ReloadRows();
                        Changed();
                    };
                    moveDown.Click += (_, _) =>
                    {
                        _settings.MoveDashboardSection(section, 1);
                        ReloadRows();
                        Changed();
                    };
                    editor.Controls.Add(row);

                    foreach (var disclosure in
                             DashboardLayout.Children(section))
                    {
                        var child = LayoutEditorRow(
                            DisclosureEditorLabel(disclosure),
                            _settings.IsDashboardDisclosureVisible(
                                disclosure),
                            _settings.IsDashboardDisclosureExpanded(
                                disclosure),
                            canMoveUp: false,
                            canMoveDown: false,
                            nested: true);
                        var childShow =
                            (CheckBox)child.Controls["show"]!;
                        var childStartOpen =
                            (CheckBox)child.Controls["startOpen"]!;
                        childShow.CheckedChanged += (_, _) =>
                        {
                            if (_loading) return;
                            _settings.SetDashboardDisclosureVisible(
                                disclosure,
                                childShow.Checked);
                            childStartOpen.Enabled =
                                childShow.Checked;
                            Changed();
                        };
                        childStartOpen.CheckedChanged += (_, _) =>
                        {
                            if (_loading) return;
                            _settings.SetDashboardDisclosureExpanded(
                                disclosure,
                                childStartOpen.Checked);
                            Changed();
                        };
                        editor.Controls.Add(child);
                    }
                }
            }
            finally
            {
                editor.ResumeLayout(true);
                _loading = previousLoading;
            }
        }

        actions.Controls.Add(Button(T("恢复默认", "Restore defaults"), (_, _) =>
        {
            _settings.ResetDashboardLayout();
            ReloadRows();
            Changed();
        }));
        body.Controls.Add(Caption(T(
            "隐藏只影响面板展示，不会停止额度历史记录、提醒或重置卡自动使用。当前结论、紧急提示和连接错误始终显示；需要处理的重置卡或更新状态会临时显示并展开。",
            "Hiding changes only the dashboard. Quota-history recording, alerts, and reset-credit auto-use continue. Current results, urgent alerts, and connection errors always remain visible; reset-credit or update states that need attention temporarily appear expanded.")));
        ReloadRows();
        return page;
    }

    private TableLayoutPanel LayoutEditorRow(
        string label,
        bool visible,
        bool expanded,
        bool canMoveUp,
        bool canMoveDown,
        bool nested)
    {
        var row = new TableLayoutPanel
        {
            Width = ScaleDynamic(nested ? 420 : 440),
            Height = ScaleDynamic(36),
            ColumnCount = 5,
            Margin = ScaleDynamic(new Padding(
                nested ? 20 : 0,
                2,
                0,
                2)),
            Padding = ScaleDynamic(new Padding(
                nested ? 5 : 8,
                3,
                5,
                3)),
            BackColor = nested
                ? Color.FromArgb(247, 248, 250)
                : Color.FromArgb(240, 242, 245),
            AccessibleName = label
        };
        row.ColumnStyles.Add(new ColumnStyle(
            SizeType.Percent,
            100));
        for (var column = 1; column < 5; column++)
            row.ColumnStyles.Add(new ColumnStyle(
                SizeType.AutoSize));

        var title = new Label
        {
            Text = nested ? $"↳ {label}" : label,
            AutoEllipsis = true,
            Dock = DockStyle.Fill,
            TextAlign = ContentAlignment.MiddleLeft,
            Font = new Font(
                "Segoe UI Semibold",
                Font.Size,
                FontStyle.Bold),
            UseMnemonic = false,
            AccessibleName = label
        };
        var show = new CheckBox
        {
            Name = "show",
            Text = T("显示", "Show"),
            Checked = visible,
            AutoSize = true,
            Anchor = AnchorStyles.Right,
            AccessibleName = T(
                $"显示 {label}",
                $"Show {label}")
        };
        var startOpen = new CheckBox
        {
            Name = "startOpen",
            Text = T("默认展开", "Start open"),
            Checked = expanded,
            Enabled = visible,
            AutoSize = true,
            Anchor = AnchorStyles.Right,
            AccessibleName = T(
                $"{label} 默认展开",
                $"Open {label} by default")
        };
        var moveUp = LayoutMoveButton(
            "moveUp",
            "↑",
            canMoveUp,
            T($"上移 {label}", $"Move {label} up"));
        var moveDown = LayoutMoveButton(
            "moveDown",
            "↓",
            canMoveDown,
            T($"下移 {label}", $"Move {label} down"));
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
        string accessibleName)
    {
        var button = new Button
        {
            Name = name,
            Text = text,
            Enabled = enabled,
            Width = ScaleDynamic(29),
            Height = ScaleDynamic(26),
            Margin = ScaleDynamic(new Padding(3, 0, 0, 0)),
            FlatStyle = FlatStyle.Flat,
            TextAlign = ContentAlignment.MiddleCenter,
            UseMnemonic = false,
            AccessibleName = accessibleName
        };
        button.FlatAppearance.BorderColor =
            Color.FromArgb(195, 201, 210);
        return button;
    }

    private TabPage BuildUpdates()
    {
        var page = Page(T("更新", "Updates"));
        var body = Stack(page);
        body.Controls.Add(Heading(T("Windows 更新", "Windows updates")));
        body.Controls.Add(_updateStatus);
        var actions = new FlowLayoutPanel
        {
            AutoSize = true, Width = ScaleDynamic(450), Margin = ScaleDynamic(new Padding(0, 12, 0, 0))
        };
        actions.Controls.Add(Button(T("检查更新", "Check"), (_, _) => CheckUpdatesRequested?.Invoke(this, EventArgs.Empty)));
        actions.Controls.Add(Button("Changelog", (_, _) => Open(AppUpdateService.ReleasesUrl)));
        actions.Controls.Add(Button("Prompts", (_, _) => Open(AppUpdateService.PromptsUrl)));
        actions.Controls.Add(Button("GitHub", (_, _) => Open(AppUpdateService.RepositoryUrl)));
        body.Controls.Add(actions);
        body.Controls.Add(Caption(T("更新器只接受当前架构的 Windows ZIP、同名 SHA256 和 platform=windows 的包内 manifest；macOS 资产会被拒绝。",
            "The updater accepts only the current-architecture Windows ZIP, its exact checksum, and a platform=windows package manifest; macOS assets are rejected.")));
        return page;
    }

    private TabPage Page(string title) => new(title) { Padding = ScaleDynamic(new Padding(14)), BackColor = Color.White };
    private FlowLayoutPanel Stack(Control page)
    {
        var body = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill, FlowDirection = FlowDirection.TopDown, WrapContents = false,
            AutoScroll = true, Padding = ScaleDynamic(new Padding(8))
        };
        page.Controls.Add(body); return body;
    }
    private Label Heading(string text) => new()
    {
        Text = text, AutoSize = true, Font = new Font("Segoe UI Semibold", 12f),
        Margin = ScaleDynamic(new Padding(0, 0, 0, 12))
    };
    private Label Caption(string text) => new()
    {
        Text = text, AutoSize = true, MaximumSize = new Size(ScaleDynamic(440), 0),
        ForeColor = Color.DimGray, Margin = ScaleDynamic(new Padding(0, 10, 0, 5))
    };
    private CheckBox Check(string text, bool value, Action<bool> changed)
    {
        var control = new CheckBox
        {
            Text = text, Checked = value, AutoSize = true,
            Margin = ScaleDynamic(new Padding(0, 6, 0, 2))
        };
        control.CheckedChanged += (_, _) => changed(control.Checked); return control;
    }
    private Control ComboRow(string label, string[] choices, int selected, Action<int> changed)
    {
        var row = new TableLayoutPanel
        {
            Width = ScaleDynamic(440), Height = ScaleDynamic(38), ColumnCount = 2,
            Margin = ScaleDynamic(new Padding(0, 3, 0, 3))
        };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 42)); row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 58));
        row.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        var combo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        combo.Items.AddRange(choices); combo.SelectedIndex = Math.Clamp(selected, 0, choices.Length - 1);
        combo.SelectedIndexChanged += (_, _) => changed(combo.SelectedIndex); row.Controls.Add(combo, 1, 0); return row;
    }
    private Button Button(string text, EventHandler handler)
    {
        var button = new Button
        {
            Text = text, AutoSize = true, FlatStyle = FlatStyle.System,
            Margin = ScaleDynamic(new Padding(0, 0, 8, 0))
        };
        button.Click += handler; return button;
    }
    private void Changed()
    {
        if (_loading) return;
        _settings.Save(); SettingsChanged?.Invoke(this, EventArgs.Empty);
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        var area = Screen.FromPoint(Cursor.Position).WorkingArea;
        Location = new Point(
            area.Left + Math.Max(0, (area.Width - Width) / 2),
            area.Top + Math.Max(0, (area.Height - Height) / 2));
        FitToWorkingArea(area, center: true);
    }

    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e);
        FitToWorkingArea(Screen.FromRectangle(e.SuggestedRectangle).WorkingArea, center: false);
    }

    private void FitToWorkingArea(Rectangle area, bool center)
    {
        var minimum = ScaleLogical(new Size(480, 540));
        MinimumSize = new Size(Math.Min(minimum.Width, area.Width), Math.Min(minimum.Height, area.Height));
        var width = Math.Min(Width, area.Width);
        var height = Math.Min(Height, area.Height);
        var x = center ? area.Left + Math.Max(0, (area.Width - width) / 2) : Left;
        var y = center ? area.Top + Math.Max(0, (area.Height - height) / 2) : Top;
        Bounds = new Rectangle(
            Math.Clamp(x, area.Left, Math.Max(area.Left, area.Right - width)),
            Math.Clamp(y, area.Top, Math.Max(area.Top, area.Bottom - height)),
            width,
            height);
    }

    private int ScaleLogical(int value) => value == 0 ? 0 : Math.Max(1,
        (int)Math.Round(value * DeviceDpi / 96d, MidpointRounding.AwayFromZero));

    private Size ScaleLogical(Size value) => new(ScaleLogical(value.Width), ScaleLogical(value.Height));

    private int ScaleDynamic(int value) => IsHandleCreated ? ScaleLogical(value) : value;

    private Padding ScaleDynamic(Padding value) => IsHandleCreated
        ? new Padding(ScaleLogical(value.Left), ScaleLogical(value.Top), ScaleLogical(value.Right), ScaleLogical(value.Bottom))
        : value;

    private string T(string zh, string en) => _settings.Chinese ? zh : en;
    private string SectionLabel(DashboardSection section) => section switch
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
                _ => SectionLabel(section)
            }
            : SectionLabel(section);

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
    private static void Open(string url)
    {
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }
}
