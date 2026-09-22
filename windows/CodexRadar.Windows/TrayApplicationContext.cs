using System.Runtime.InteropServices;
using System.Media;

namespace CodexRadar.Windows;

internal sealed class TrayApplicationContext : ApplicationContext
{
    private static readonly TimeSpan ResetCreditInterval = TimeSpan.FromHours(6);
    private static readonly TimeSpan UpdateInterval = TimeSpan.FromHours(6);
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly RadarService _service = new();
    private readonly QuotaHistoryStore _quotaHistoryStore =
        new();
    private readonly AppUpdateService _updater = new();
    private readonly ResetCreditProtectionService _protection;
    private readonly NotifyIcon _tray = new();
    private readonly TaskbarStatusForm _taskbarStatus = new();
    private readonly Queue<QueuedBalloon> _balloonQueue = [];
    private readonly System.Windows.Forms.Timer _balloonTimer = new() { Interval = 6_500 };
    private readonly DashboardForm _dashboard;
    private readonly Control _activationDispatcher = new();
    private readonly System.Windows.Forms.Timer _refreshTimer = new() { Interval = 60_000 };
    private readonly CancellationTokenSource _lifetime = new();
    private readonly List<Task> _retiredLoops = [];
    private CancellationTokenSource? _resetAutoCancellation;
    private CancellationTokenSource? _updateAutoCancellation;
    private SettingsForm? _settingsForm;
    private bool _settingsFormChinese;
    private DashboardSnapshot _liveSnapshot = new();
    private DashboardSnapshot _displaySnapshot = new();
    private QuotaHistoryTimeline _quotaHistory = new();
    private DateTimeOffset _quotaHistoryEndingAt =
        DateTimeOffset.Now;
    private bool _quotaHistoryStorageUnavailable;
    private AppUpdateStatus _updateStatus = new(AppUpdatePhase.Idle);
    private Task _refreshTask = Task.CompletedTask;
    private Task _resetTask = Task.CompletedTask;
    private Task _updateTask = Task.CompletedTask;
    private Task _resetLoop = Task.CompletedTask;
    private Task _updateLoop = Task.CompletedTask;
    private Task _protectionTask = Task.CompletedTask;
    private Icon? _dynamicIcon;
    private HealthLevel? _dynamicIconHealth;
    private bool _refreshing;
    private bool _resetLoading;
    private bool _updating;
    private bool _exiting;
    private bool _serviceDisposed;
    private bool _hasLiveSnapshot;

    public TrayApplicationContext()
    {
        var historyLoad = _quotaHistoryStore.Load(
            _quotaHistoryEndingAt);
        _quotaHistory = historyLoad.Timeline;
        _quotaHistoryStorageUnavailable =
            historyLoad.Status is
                QuotaHistoryLoadStatus.Corrupt
                or QuotaHistoryLoadStatus.Unavailable;

        _protection = new ResetCreditProtectionService(_settings);
        _dashboard = new DashboardForm(_settings);
        _ = _dashboard.Handle;
        _ = _activationDispatcher.Handle;
        _dashboard.RefreshRequested += (_, _) => StartRefresh(true);
        _dashboard.ResetCreditsRequested += (_, _) => StartResetCreditRefresh(true);
        _dashboard.SettingsRequested += (_, _) => ShowSettings();
        _dashboard.CheckUpdatesRequested += (_, _) => StartUpdateCheck(true);
        _dashboard.DismissSpeedRequested += (_, _) => DismissSpeedAlert();
        _dashboard.SettingsChanged += (_, _) => SettingsChanged();
        _dashboard.ProtectionEnableRequested +=
            (_, _) => StartProtectionEnable();
        _dashboard.ProtectionDisableRequested +=
            (_, _) => DisableProtection();
        _dashboard.ProtectionPreviewRequested +=
            (_, _) => StartProtectionPlanCheck();
        _dashboard.QuitRequested += (_, _) => Exit();
        _protection.StatusChanged += OnProtectionStatusChanged;
        _protection.CreditsChanged += OnProtectionCreditsChanged;
        _protection.NoticeRaised += OnProtectionNoticeRaised;
        _liveSnapshot = _liveSnapshot with
        {
            ResetCreditProtection = _protection.Status
        };

        _tray.MouseClick += OnTrayMouseClick;
        _taskbarStatus.LeftClick += (_, _) => ToggleDashboard();
        _taskbarStatus.PlacementAvailabilityChanged += (_, _) => UpdateStatusSurfaceVisibility();
        _balloonTimer.Tick += (_, _) =>
        {
            _balloonTimer.Stop();
            if (_balloonQueue.Count > 0) PumpBalloonQueue();
            else UpdateStatusSurfaceVisibility();
        };
        _refreshTimer.Tick += (_, _) => StartRefresh(false);
        _refreshTimer.Start();
        UpdateTrayIcon(HealthLevel.Unknown);
        _tray.Text = T("Codex Radar Sentinel · 正在加载…", "Codex Radar Sentinel · Loading…");
        _taskbarStatus.SetStatus("--/--/-", HealthLevel.Unknown, _settings);
        RebuildContextMenu();
        ApplyStatusDisplayMode();

        StartRefresh(false);
        ApplyAutomaticSettings(runImmediately: false);
        StartProtectionEvaluation();
    }

    private void StartRefresh(bool showPanel)
    {
        if (_exiting) return;
        if (_refreshing)
        {
            if (showPanel) ShowDashboard();
            return;
        }
        if (showPanel) ShowDashboard();
        _refreshTask = RefreshAsync(showPanel, _lifetime.Token);
    }

    private async Task RefreshAsync(bool showPanel, CancellationToken cancellationToken)
    {
        _refreshing = true;
        try
        {
            var previous = _hasLiveSnapshot ? _liveSnapshot : null;
            var next = await _service.RefreshAsync(_settings, previous, cancellationToken);
            await UpdateQuotaHistoryAsync(
                next,
                previous?.QuotaObservedAt,
                cancellationToken);
            var events = NotificationPolicy.Evaluate(previous, next, _settings);
            _liveSnapshot = next;
            _hasLiveSnapshot = true;
            _settings.Save();
            Render();
            foreach (var notification in events)
            {
                if (notification.Identifier.StartsWith("prediction-", StringComparison.Ordinal) && !_settings.PredictionNotifications) continue;
                if (notification.Identifier.StartsWith("model-iq-", StringComparison.Ordinal) && !_settings.IqNotifications) continue;
                Deliver(notification);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (Exception ex)
        {
            _liveSnapshot = _liveSnapshot with
            {
                RefreshedAt = DateTimeOffset.Now,
                Errors = _liveSnapshot.Errors.Concat([T($"刷新失败：{ex.Message}", $"Refresh failed: {ex.Message}")]).TakeLast(4).ToArray()
            };
            Render();
        }
        finally
        {
            _refreshing = false;
            StartProtectionEvaluation();
        }
    }

    private async Task UpdateQuotaHistoryAsync(
        DashboardSnapshot snapshot,
        DateTimeOffset? previousObservation,
        CancellationToken cancellationToken)
    {
        _quotaHistoryEndingAt = DateTimeOffset.Now;
        var sample = QuotaHistoryObservationPolicy.CreateSample(
            snapshot,
            previousObservation,
            _settings.Preview);
        if (sample is null)
            return;

        try
        {
            var result = await Task.Run(
                () => _quotaHistoryStore.Record(
                    sample,
                    _quotaHistoryEndingAt),
                cancellationToken);
            _quotaHistory = result.Timeline;
            _quotaHistoryStorageUnavailable = false;
        }
        catch (OperationCanceledException)
            when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch
        {
            // History is supplemental. Never replace a corrupt archive and
            // never fail quota refresh or notifications because local history
            // cannot be read or committed.
            _quotaHistoryStorageUnavailable = true;
        }
    }

    private void StartProtectionEvaluation()
    {
        if (_exiting || !_protectionTask.IsCompleted) return;
        _protectionTask = RunProtectionActionAsync(
            token => _protection.EvaluateAsync(token));
    }

    private void StartProtectionEnable()
    {
        if (_exiting || !_protectionTask.IsCompleted) return;
        if (_settings.Preview != DashboardPreview.Live)
        {
            ShowBalloon(
                T("预览模式禁止自动使用",
                    "Auto-use is disabled in preview mode"),
                T("退出调试预览模式后再启用。当前不会使用任何重置卡。",
                    "Leave debug preview before enabling. No reset credit will be consumed."),
                ToolTipIcon.Warning);
            return;
        }
        var result = MessageBox.Show(
            T(
                "启用后，Codex Radar 只会授权当前账号的完整可用卡集合，并在最早到期卡的到期前 30 分钟尝试使用一次。\n\n"
                + "使用重置卡不可撤销。账号、卡集合、系统时钟、授权或本机对账记录发生变化时会自动安全停用；关闭开关会在发送前撤销授权。\n\n"
                + "是否确认启用？",
                "When enabled, Codex Radar authorizes only the complete current credit set for this account and attempts one consume request 30 minutes before the earliest expiry.\n\n"
                + "Consuming a reset credit is irreversible. Account, card-set, clock, authorization, or local reconciliation changes fail closed; turning it off revokes authorization before dispatch.\n\n"
                + "Enable expiry auto-use?"),
            T("确认到期前自动使用", "Confirm expiry auto-use"),
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning,
            MessageBoxDefaultButton.Button2);
        if (result != DialogResult.Yes) return;
        ShowDashboard();
        _protectionTask = RunProtectionActionAsync(
            token => _protection.EnableAsync(token));
    }

    private void StartProtectionPlanCheck()
    {
        if (_exiting || !_protectionTask.IsCompleted) return;
        ShowDashboard();
        _protectionTask = RunProtectionActionAsync(
            token => _settings.ResetCreditProtectionEnabled
                ? _protection.EvaluateAsync(token)
                : _protection.PreviewAsync(token));
    }

    private void DisableProtection()
    {
        if (_exiting) return;
        _protection.Disable();
        RebuildContextMenu();
        Render();
    }

    private async Task RunProtectionActionAsync(
        Func<CancellationToken, Task> operation)
    {
        try
        {
            await operation(_lifetime.Token);
        }
        catch (OperationCanceledException)
            when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            ShowBalloon(
                T("重置卡自动使用检查失败",
                    "Reset-credit auto-use check failed"),
                ex.GetType().Name,
                ToolTipIcon.Warning);
        }
        finally
        {
            BeginInvokeOnUi(() =>
            {
                if (_exiting) return;
                _liveSnapshot = _liveSnapshot with
                {
                    ResetCreditProtection = _protection.Status
                };
                RebuildContextMenu();
                Render();
            });
        }
    }

    private void OnProtectionStatusChanged(
        object? sender,
        EventArgs eventArgs) =>
        BeginInvokeOnUi(() =>
        {
            if (_exiting) return;
            _liveSnapshot = _liveSnapshot with
            {
                ResetCreditProtection = _protection.Status
            };
            Render();
        });

    private void OnProtectionCreditsChanged(
        object? sender,
        ResetCreditProtectionCacheUpdate update) =>
        BeginInvokeOnUi(() =>
        {
            if (_exiting) return;
            _settings.CachedResetCredits = update.Credits.ToList();
            _settings.CachedAvailableResetCredits = update.Available;
            _settings.LastResetCreditCheck = update.CheckedAt;
            _settings.LastResetCreditFailure = null;
            _settings.Save();
            _liveSnapshot = _liveSnapshot with
            {
                ResetCredits = update.Credits,
                AvailableResetCredits = update.Available,
                ResetCreditsCheckedAt = update.CheckedAt,
                ResetCreditFailure = null,
                ResetCreditProtection = _protection.Status
            };
            Render();
        });

    private void OnProtectionNoticeRaised(
        object? sender,
        ResetCreditProtectionNotice notice) =>
        BeginInvokeOnUi(() =>
        {
            if (_exiting) return;
            if (notice.Success)
            {
                ShowBalloon(
                    T("已确认重置卡处于已使用状态",
                        "Reset credit confirmed as used"),
                    T("Codex 已确认该卡处于已使用状态，并已读取最新额度。",
                        "Codex confirmed the used state and the latest limits were read."),
                    ToolTipIcon.Info,
                    _settings.NotificationSound,
                    NotificationSeverity.Active);
            }
            else
            {
                ShowBalloon(
                    T("重置卡自动使用需要检查",
                        "Reset-credit auto-use needs attention"),
                    ProtectionNoticeBody(notice.Identifier),
                    ToolTipIcon.Warning,
                    _settings.NotificationSound,
                    NotificationSeverity.Urgent);
            }
        });

    private string ProtectionNoticeBody(string identifier)
    {
        if (identifier.Contains("account-changed",
                StringComparison.Ordinal))
            return T(
                "Codex 账号已变化。自动使用已关闭；未决尝试只会绑定原账号进行对账。",
                "The Codex account changed. Auto-use is off; an unresolved attempt remains bound to the original account.");
        if (identifier.Contains("signed-out",
                StringComparison.Ordinal))
            return T(
                "Codex 登录态不可验证，自动使用已关闭。",
                "The Codex sign-in cannot be verified; auto-use was turned off.");
        if (identifier.Contains("clock-changed",
                StringComparison.Ordinal))
            return T(
                "系统时钟连续性超过 5 秒安全阈值，授权已撤销；请核对时间并重新确认。",
                "Clock continuity exceeded the 5-second safety threshold; authorization was revoked. Verify the clock and opt in again.");
        if (identifier.Contains("missed",
                StringComparison.Ordinal))
            return T(
                "重置卡已过期，未能确认自动使用是否完成。",
                "The reset credit expired before automatic use could be confirmed.");
        return T(
            "本机授权或对账记录无法验证，自动使用已安全关闭。",
            "The local authorization or reconciliation record cannot be verified; auto-use was disabled safely.");
    }

    private async Task ResetCreditLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(8), cancellationToken);
            while (!cancellationToken.IsCancellationRequested)
            {
                var stale = _settings.LastResetCreditCheck is null
                            || DateTimeOffset.Now - _settings.LastResetCreditCheck >= ResetCreditInterval;
                if (stale)
                {
                    StartResetCreditRefresh(false, cancellationToken);
                    await _resetTask;
                }
                await Task.Delay(ResetCreditInterval, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
    }

    private void StartResetCreditRefresh(bool manual, CancellationToken? operationToken = null)
    {
        if (_exiting) return;
        if (_resetLoading)
        {
            if (manual) ShowDashboard();
            return;
        }
        if (manual) ShowDashboard();
        _resetTask = RefreshResetCreditsAsync(manual, operationToken ?? _lifetime.Token);
    }

    private async Task RefreshResetCreditsAsync(bool manual, CancellationToken cancellationToken)
    {
        _resetLoading = true;
        Render();
        try
        {
            var result = await _service.RefreshResetCreditsAsync(cancellationToken);
            _settings.CachedResetCredits = result.Credits.ToList();
            _settings.CachedAvailableResetCredits = result.Available;
            _settings.CachedTotalEarnedResetCredits = result.TotalEarned;
            _settings.LastResetCreditCheck = result.CheckedAt;
            _settings.LastResetCreditFailure = null;
            _settings.Save();
            _liveSnapshot = _liveSnapshot with
            {
                ResetCredits = result.Credits,
                AvailableResetCredits = result.Available,
                TotalEarnedResetCredits = result.TotalEarned,
                ResetCreditsCheckedAt = result.CheckedAt,
                ResetCreditFailure = null
            };
            if (manual)
                ShowBalloon(T("重置卡已刷新", "Reset credits refreshed"),
                    T($"已读取 {result.Credits.Count} 张脱敏卡片。", $"Loaded {result.Credits.Count} sanitized cards."), ToolTipIcon.Info);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (Exception ex)
        {
            var kind = ex is ResetCreditException reset ? reset.Kind
                : ex is HttpRequestException ? "network" : "unknown";
            var safeDetail = ex is ResetCreditException ? ex.Message
                : ex is HttpRequestException ? "" : ex.GetType().Name;
            var failure = new ResetCreditFailureInfo(kind, safeDetail, DateTimeOffset.Now, !manual);
            _settings.LastResetCreditFailure = failure;
            _settings.Save();
            _liveSnapshot = _liveSnapshot with { ResetCreditFailure = failure };
            if (manual)
            {
                ShowBalloon(T("重置卡刷新失败", "Reset credit refresh failed"),
                    T("请在雷达面板查看原因和恢复建议。", "Open the dashboard for the cause and recovery steps."),
                    ToolTipIcon.Warning);
            }
        }
        finally
        {
            _resetLoading = false;
            Render();
        }
    }

    private async Task UpdateLoopAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(5), cancellationToken);
            while (!cancellationToken.IsCancellationRequested)
            {
                StartUpdateCheck(false, cancellationToken);
                await _updateTask;
                await Task.Delay(UpdateInterval, cancellationToken);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
    }

    private void StartUpdateCheck(bool manual, CancellationToken? operationToken = null)
    {
        if (_exiting) return;
        if (_updating)
        {
            if (manual) ShowDashboard();
            return;
        }
        if (manual) ShowDashboard();
        _updateTask = CheckAndInstallUpdateAsync(manual, operationToken ?? _lifetime.Token);
    }

    private async Task CheckAndInstallUpdateAsync(bool manual, CancellationToken cancellationToken)
    {
        _updating = true;
        SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Checking));
        try
        {
            var update = await _updater.FindUpdateAsync(cancellationToken);
            if (update is null)
            {
                SetUpdateStatus(new AppUpdateStatus(manual ? AppUpdatePhase.UpToDate : AppUpdatePhase.Idle));
                return;
            }

            SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Available, update.Version, update.Changelog, update.ReleaseUrl));
            var retryPaused = !manual && _settings.LastInstallerFailureVersion == update.Version
                              && _settings.LastInstallerFailureAt is { } failedAt
                              && DateTimeOffset.Now - failedAt < UpdateInterval;
            if (retryPaused)
            {
                SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Failed, update.Version,
                    T("上次安装失败，自动重试将在 6 小时后恢复。", "The previous install failed; automatic retry resumes after 6 hours."),
                    update.ReleaseUrl));
                return;
            }

            SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Downloading, update.Version, null, update.ReleaseUrl));
            await _updater.LaunchInstallAsync(update, cancellationToken);
            SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Installing, update.Version, null, update.ReleaseUrl));
            BeginInvokeOnUi(Exit);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            if (!_exiting) SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Idle));
        }
        catch (Exception ex)
        {
            var version = _updateStatus.Version;
            _settings.LastInstallerFailureVersion = version;
            _settings.LastInstallerFailureAt = DateTimeOffset.Now;
            _settings.Save();
            SetUpdateStatus(new AppUpdateStatus(AppUpdatePhase.Failed, version, ex.Message, _updateStatus.ReleaseUrl));
            if (manual)
            {
                ShowBalloon(T("更新失败", "Update failed"), ex.Message, ToolTipIcon.Warning);
            }
        }
        finally { _updating = false; }
    }

    private void SetUpdateStatus(AppUpdateStatus status)
    {
        _updateStatus = status;
        _settingsForm?.SetUpdateStatus(status);
        Render();
    }

    private void Render()
    {
        _liveSnapshot = _liveSnapshot with
        {
            ResetCreditProtection = _protection.Status
        };
        _displaySnapshot = DashboardPreviewFactory.Apply(_liveSnapshot, _settings.Preview);
        _displaySnapshot = _displaySnapshot with { QuotaPacing = QuotaPacingCalculator.Calculate(_displaySnapshot, _settings) };
        _dashboard.SetState(
            _displaySnapshot,
            _settings,
            _updateStatus,
            _resetLoading,
            _quotaHistory,
            _quotaHistoryEndingAt,
            _quotaHistoryStorageUnavailable);
        UpdateTrayIcon(_displaySnapshot.Health);
        var statusText = _displaySnapshot.CompactTitle(_settings);
        _tray.Text = Truncate($"Codex Radar Sentinel · {statusText}", 127);
        _taskbarStatus.SetStatus(statusText, _displaySnapshot.Health, _settings);
        UpdateStatusSurfaceVisibility();
    }

    private void OnTrayMouseClick(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left) return;
        ToggleDashboard();
    }

    private void ToggleDashboard()
    {
        if (_dashboard.Visible) _dashboard.Hide(); else ShowDashboard();
    }

    internal Task<bool> HandleDashboardRequestAsync(bool show)
    {
        // Search may request activation before the message loop starts. Queue
        // onto the existing UI handle instead of building another dashboard.
        if (_activationDispatcher.IsDisposed || !_activationDispatcher.IsHandleCreated) return Task.FromResult(false);
        var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            // Showing a tool window can recreate its native handle. Keep launch
            // messages on a separate, stable handle so none are lost mid-show.
            _activationDispatcher.BeginInvoke(() =>
            {
                if (!_exiting && show) ShowDashboard();
                completion.TrySetResult(!_exiting && _dashboard.Visible);
            });
        }
        catch (InvalidOperationException) when (_exiting || _activationDispatcher.IsDisposed)
        {
            completion.TrySetResult(false);
        }
        return completion.Task;
    }

    private void ShowDashboard()
    {
        if (_dashboard.Visible)
        {
            _dashboard.Activate();
            return;
        }
        _dashboard.ShowNearTray();
    }

    private void ShowSettings()
    {
        _dashboard.Hide();
        if (_settingsForm is null || _settingsForm.IsDisposed)
        {
            _settingsForm = new SettingsForm(_settings);
            _settingsFormChinese = _settings.Chinese;
            _settingsForm.SettingsChanged += (_, _) => SettingsChanged();
            _settingsForm.CheckUpdatesRequested += (_, _) => StartUpdateCheck(true);
            _settingsForm.FormClosed += (_, _) => _settingsForm = null;
            _settingsForm.SetUpdateStatus(_updateStatus);
        }
        _settingsForm.Show();
        _settingsForm.Activate();
    }

    private void SettingsChanged()
    {
        if (_settings.Preview != DashboardPreview.Live
            && _settings.ResetCreditProtectionEnabled)
            _protection.Disable();
        _settings.Save();
        ApplyAutomaticSettings();
        ApplyStatusDisplayMode();
        RebuildContextMenu();
        Render();
        if (_settingsForm is { IsDisposed: false } form && _settingsFormChinese != _settings.Chinese)
        {
            _settingsFormChinese = _settings.Chinese;
            form.BeginInvoke(new Action(form.ReloadLanguage));
        }
    }

    private void ApplyAutomaticSettings(bool runImmediately = true)
    {
        if (_settings.AutoResetCreditCheck && _resetAutoCancellation is null)
        {
            _resetAutoCancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            _resetLoop = ResetCreditLoopAsync(_resetAutoCancellation.Token);
            if (runImmediately) StartResetCreditRefresh(false, _resetAutoCancellation.Token);
        }
        else if (!_settings.AutoResetCreditCheck && _resetAutoCancellation is not null)
        {
            RetireLoop(_resetLoop, _resetAutoCancellation);
            _resetAutoCancellation = null;
            _resetLoop = Task.CompletedTask;
        }

        if (_settings.AutomaticUpdates && _updateAutoCancellation is null)
        {
            _updateAutoCancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            _updateLoop = UpdateLoopAsync(_updateAutoCancellation.Token);
            if (runImmediately) StartUpdateCheck(false, _updateAutoCancellation.Token);
        }
        else if (!_settings.AutomaticUpdates && _updateAutoCancellation is not null)
        {
            RetireLoop(_updateLoop, _updateAutoCancellation);
            _updateAutoCancellation = null;
            _updateLoop = Task.CompletedTask;
        }
    }

    private void RetireLoop(Task loop, CancellationTokenSource cancellation)
    {
        cancellation.Cancel();
        _retiredLoops.Add(loop);
        _ = loop.ContinueWith(_ => cancellation.Dispose(), CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }

    private void DismissSpeedAlert()
    {
        _settings.DismissedSpeedAlertKey = _displaySnapshot.SpeedAlertKey;
        _settings.Save();
        Render();
    }

    private void RebuildContextMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(T("打开 Codex Radar", "Open Codex Radar"), null, (_, _) => ShowDashboard());
        menu.Items.Add(T("立即刷新", "Refresh now"), null, (_, _) => StartRefresh(true));
        menu.Items.Add(T("设置…", "Settings…"), null, (_, _) => ShowSettings());
        menu.Items.Add(T("检查更新…", "Check for updates…"), null, (_, _) => StartUpdateCheck(true));
        menu.Items.Add(new ToolStripSeparator());

        var location = new ToolStripMenuItem(T("状态显示位置", "Status location"));
        location.DropDownItems.Add(StatusLocationItem(
            T("通知区域图标（当前位置）", "Notification-area icon"),
            StatusDisplayMode.NotificationArea));
        location.DropDownItems.Add(StatusLocationItem(
            T("任务栏文字（输入法左侧）", "Taskbar text (left of input)"),
            StatusDisplayMode.TaskbarText));
        menu.Items.Add(location);

        var autoCredits = new ToolStripMenuItem(T("自动查询重置卡", "Auto-check reset credits"))
            { Checked = _settings.AutoResetCreditCheck, CheckOnClick = true };
        autoCredits.CheckedChanged += (_, _) =>
        {
            _settings.AutoResetCreditCheck = autoCredits.Checked;
            _settings.Save();
            ApplyAutomaticSettings();
        };
        menu.Items.Add(autoCredits);

        var autoUse = new ToolStripMenuItem(
            T("到期前自动使用重置卡", "Auto-use reset credit before expiry"))
        {
            Checked = _settings.ResetCreditProtectionEnabled
        };
        autoUse.Click += (_, _) =>
        {
            if (_settings.ResetCreditProtectionEnabled)
                DisableProtection();
            else
                StartProtectionEnable();
        };
        menu.Items.Add(autoUse);

        var autoUpdates = new ToolStripMenuItem(T("自动更新", "Automatic updates"))
            { Checked = _settings.AutomaticUpdates, CheckOnClick = true };
        autoUpdates.CheckedChanged += (_, _) =>
        {
            _settings.AutomaticUpdates = autoUpdates.Checked;
            _settings.Save();
            ApplyAutomaticSettings();
        };
        menu.Items.Add(autoUpdates);

        var startup = new ToolStripMenuItem(T("登录 Windows 时启动", "Start with Windows"))
            { Checked = SafeStartsWithWindows(), CheckOnClick = true };
        startup.CheckedChanged += (_, _) =>
        {
            try { AppSettings.StartsWithWindows = startup.Checked; }
            catch (Exception ex) { ShowBalloon(T("无法修改开机启动", "Could not change startup setting"), ex.Message, ToolTipIcon.Warning); }
        };
        menu.Items.Add(startup);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(T("退出", "Exit"), null, (_, _) => Exit());

        var previous = _tray.ContextMenuStrip;
        _tray.ContextMenuStrip = menu;
        _taskbarStatus.SetStatusContextMenu(menu);
        previous?.Dispose();
    }

    private ToolStripMenuItem StatusLocationItem(string label, StatusDisplayMode mode)
    {
        var item = new ToolStripMenuItem(label)
        {
            Checked = _settings.StatusDisplayMode == mode,
            Tag = mode
        };
        item.Click += (_, _) =>
        {
            if (_settings.StatusDisplayMode == mode) return;
            _settings.StatusDisplayMode = mode;
            _settings.Save();
            if (item.Owner is { } owner)
            {
                foreach (var sibling in owner.Items.OfType<ToolStripMenuItem>())
                    sibling.Checked = sibling.Tag is StatusDisplayMode siblingMode && siblingMode == mode;
            }
            ApplyStatusDisplayMode();
            Render();
        };
        return item;
    }

    private void ApplyStatusDisplayMode()
    {
        var taskbarText = _settings.StatusDisplayMode == StatusDisplayMode.TaskbarText;
        _taskbarStatus.SetDisplayEnabled(taskbarText);
        UpdateStatusSurfaceVisibility();
    }

    private void UpdateStatusSurfaceVisibility()
    {
        if (_exiting) return;
        var taskbarText = _settings.StatusDisplayMode == StatusDisplayMode.TaskbarText;
        var balloonActive = _balloonTimer.Enabled || _balloonQueue.Count > 0;
        _tray.Visible = !taskbarText || !_taskbarStatus.PlacementAvailable || balloonActive;
    }

    private bool SafeStartsWithWindows()
    {
        try { return AppSettings.StartsWithWindows; }
        catch { return false; }
    }

    private void Deliver(NotificationEvent notification)
    {
        var icon = notification.Severity switch
        {
            NotificationSeverity.Urgent => ToolTipIcon.Error,
            NotificationSeverity.Active => ToolTipIcon.Warning,
            _ => ToolTipIcon.Info
        };
        ShowBalloon(notification.Title, notification.Body, icon, _settings.NotificationSound, notification.Severity);
    }

    private void UpdateTrayIcon(HealthLevel health)
    {
        if (_dynamicIcon is not null && _dynamicIconHealth == health) return;
        var color = health switch
        {
            HealthLevel.Good => Color.FromArgb(16, 124, 65),
            HealthLevel.Warning => Color.FromArgb(232, 140, 0),
            HealthLevel.Critical => Color.FromArgb(196, 43, 28),
            _ => Color.FromArgb(92, 92, 92)
        };
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);
            using var white = new Pen(Color.FromArgb(225, 255, 255, 255), 1.7f);
            using var fill = new SolidBrush(color);
            graphics.FillEllipse(fill, 1, 1, 30, 30);
            graphics.DrawEllipse(white, 7, 7, 18, 18);
            graphics.DrawEllipse(white, 12, 12, 8, 8);
            graphics.DrawLine(white, 16, 16, 26, 7);
            graphics.FillEllipse(Brushes.White, 13, 13, 6, 6);
        }
        var handle = bitmap.GetHicon();
        var icon = (Icon)Icon.FromHandle(handle).Clone();
        DestroyIcon(handle);
        var previous = _dynamicIcon;
        _dynamicIcon = icon;
        _dynamicIconHealth = health;
        _tray.Icon = icon;
        previous?.Dispose();
    }

    private void ShowBalloon(string title, string text, ToolTipIcon icon, bool playSound = false,
        NotificationSeverity severity = NotificationSeverity.Passive)
    {
        if (_exiting) return;
        _balloonQueue.Enqueue(new QueuedBalloon(title, text, icon, playSound, severity));
        if (!_balloonTimer.Enabled) PumpBalloonQueue();
    }

    private void PumpBalloonQueue()
    {
        if (_exiting) return;
        if (_balloonQueue.Count == 0)
        {
            UpdateStatusSurfaceVisibility();
            return;
        }
        var next = _balloonQueue.Dequeue();
        // NotifyIcon balloons require a registered icon. In taskbar-text mode it
        // is exposed only for the lifetime of the queued Windows notification.
        _tray.Visible = true;
        _tray.BalloonTipTitle = next.Title;
        _tray.BalloonTipText = Truncate(next.Text, 240);
        _tray.BalloonTipIcon = next.Icon;
        _tray.ShowBalloonTip(6_000);
        if (next.PlaySound)
        {
            if (next.Severity == NotificationSeverity.Urgent) SystemSounds.Exclamation.Play();
            else SystemSounds.Asterisk.Play();
        }
        _balloonTimer.Start();
    }

    private void BeginInvokeOnUi(Action action)
    {
        if (_dashboard.IsHandleCreated) _dashboard.BeginInvoke(action);
        else action();
    }

    private string T(string zh, string en) => _settings.Chinese ? zh : en;
    private static string Truncate(string value, int length) => value.Length <= length ? value : value[..(length - 1)] + "…";

    private async void Exit()
    {
        if (_exiting) return;
        _exiting = true;
        _refreshTimer.Stop();
        _balloonTimer.Stop();
        _balloonQueue.Clear();
        _lifetime.Cancel();
        _resetAutoCancellation?.Cancel();
        _updateAutoCancellation?.Cancel();
        _tray.Visible = false;
        _taskbarStatus.SetDisplayEnabled(false);
        _settingsForm?.Close();
        _dashboard.Hide();
        var backgroundTasks = Task.WhenAll(
            new[]
            {
                _refreshTask, _resetTask, _updateTask, _resetLoop,
                _updateLoop, _protectionTask
            }.Concat(_retiredLoops));
        try
        {
            // Cancellation normally completes immediately. The bound also
            // guarantees right-click Exit cannot be held hostage by an OS file
            // probe or third-party process that ignores cancellation.
            await backgroundTasks.WaitAsync(TimeSpan.FromSeconds(2));
        }
        catch { }
        var serviceDisposal = _service.DisposeAsync().AsTask();
        var serviceDisposed = false;
        try
        {
            await serviceDisposal.WaitAsync(TimeSpan.FromSeconds(1));
            serviceDisposed = serviceDisposal.IsCompletedSuccessfully;
        }
        catch { }
        if (!serviceDisposed) _service.Abort();
        _serviceDisposed = true;
        _dashboard.AllowClose();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _refreshTimer.Dispose();
            _balloonTimer.Dispose();
            _lifetime.Cancel();
            _resetAutoCancellation?.Cancel();
            _updateAutoCancellation?.Cancel();
            _resetAutoCancellation?.Dispose();
            _updateAutoCancellation?.Dispose();
            _lifetime.Dispose();
            _tray.ContextMenuStrip?.Dispose();
            _taskbarStatus.SetStatusContextMenu(null);
            _tray.Dispose();
            _taskbarStatus.Dispose();
            _dynamicIcon?.Dispose();
            _settingsForm?.Dispose();
            _dashboard.Dispose();
            _activationDispatcher.Dispose();
            _updater.Dispose();
            _protection.StatusChanged -= OnProtectionStatusChanged;
            _protection.CreditsChanged -= OnProtectionCreditsChanged;
            _protection.NoticeRaised -= OnProtectionNoticeRaised;
            _protection.Dispose();
            if (!_serviceDisposed)
            {
                // The normal Exit path awaits disposal above. During an unusual
                // synchronous teardown, initiate cleanup without blocking the
                // UI thread on an async gate.
                try { _ = _service.DisposeAsync(); } catch { }
                _serviceDisposed = true;
            }
        }
        base.Dispose(disposing);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr handle);

    private sealed record QueuedBalloon(string Title, string Text, ToolTipIcon Icon, bool PlaySound,
        NotificationSeverity Severity);
}
