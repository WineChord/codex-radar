namespace CodexRadar.Windows;

/// <summary>
/// Coordinates the opt-in reset-credit expiry protection workflow.
///
/// Raw account and credit identifiers only exist in the lifetime of a fresh
/// Codex app-server session. Persistence and UI events contain SHA-256
/// fingerprints only. Every destructive dispatch is re-authorized while the
/// cross-process dispatch lock is held.
/// </summary>
internal sealed class ResetCreditProtectionService : IDisposable
{
    private static readonly TimeSpan RetryDelay = TimeSpan.FromMinutes(2);

    private readonly AppSettings _settings;
    private readonly ResetCreditProtectionAuthorizationStore _authorizationStore;
    private readonly ResetCreditProtectionLedgerStore _ledgerStore;
    private readonly SemaphoreSlim _operationGate = new(1, 1);
    private readonly object _stateGate = new();
    private CancellationTokenSource? _activeOperation;
    private ResetCreditProtectionConsent? _consent;
    private ResetCreditProtectionLedger _ledger = new();
    private ResetCreditProtectionStatus _status =
        ResetCreditProtectionStatus.Disabled;
    private DateTimeOffset? _nextRetryAt;
    private bool _ledgerCorrupt;
    private bool _disposed;
    private long _generation;

    public ResetCreditProtectionService(
        AppSettings settings,
        ResetCreditProtectionAuthorizationStore? authorizationStore = null,
        ResetCreditProtectionLedgerStore? ledgerStore = null)
    {
        _settings = settings;
        _authorizationStore = authorizationStore
                              ?? new ResetCreditProtectionAuthorizationStore();
        _ledgerStore = ledgerStore ?? new ResetCreditProtectionLedgerStore();
        RestorePersistedState();
    }

    public event EventHandler? StatusChanged;
    public event EventHandler<ResetCreditProtectionCacheUpdate>? CreditsChanged;
    public event EventHandler<ResetCreditProtectionNotice>? NoticeRaised;

    public ResetCreditProtectionStatus Status
    {
        get { lock (_stateGate) return _status; }
    }

    public bool Enabled => _settings.ResetCreditProtectionEnabled
                           && _consent is not null
                           && !_ledgerCorrupt
                           && _settings.Preview == DashboardPreview.Live;

    public Task EnableAsync(CancellationToken cancellationToken) =>
        RunExclusiveAsync(
            async token =>
            {
                var generation = Interlocked.Increment(ref _generation);
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Enabling));
                var clockAnchor = ResetCreditProtectionClockSample.Now();

                using var processLock =
                    ResetCreditProtectionProcessLock.TryAcquire();
                if (processLock is null)
                {
                    SetBlocked(ResetCreditProtectionBlockReason.AnotherProcess);
                    return;
                }

                var journal = ReloadLedger();
                if (_ledgerCorrupt)
                {
                    FailClosed();
                    return;
                }
                if (journal is not null)
                {
                    await ReconcileJournalWhileLockedAsync(journal, token)
                        .ConfigureAwait(false);
                    return;
                }

                if (_settings.Preview != DashboardPreview.Live)
                {
                    SetBlocked(ResetCreditProtectionBlockReason.PreviewMode);
                    return;
                }

                try
                {
                    await using var client = new AppServerClient();
                    var accountFingerprint =
                        await ReadAccountFingerprintAsync(client, token)
                            .ConfigureAwait(false);
                    var response = await ReadBoundRateLimitsAsync(
                            client, accountFingerprint, token)
                        .ConfigureAwait(false);
                    PublishCache(response.ResetCredits, force: true);
                    if (response.ResetCredits is not { } summary)
                    {
                        SetBlocked(
                            ResetCreditProtectionBlockReason.DetailsUnavailable);
                        return;
                    }

                    var now = DateTimeOffset.UtcNow;
                    var decision = ResetCreditExpiryProtectionPolicy.Decide(
                        summary, now, _ledger.ExcludedCreditFingerprints);
                    var target = decision.Target;
                    if (target is null)
                    {
                        ApplyDecisionStatus(decision);
                        return;
                    }

                    var authorized = CurrentFingerprints(summary, now);
                    if (authorized is null)
                    {
                        SetBlocked(
                            ResetCreditProtectionBlockReason.DetailsIncomplete,
                            availableCount: summary.AvailableCount,
                            availableDetails: summary.Credits?
                                .Count(credit => credit.IsAvailable) ?? 0);
                        return;
                    }
                    if (authorized.Count == 0
                        || !authorized.Contains(target.CreditFingerprint))
                    {
                        SetBlocked(
                            ResetCreditProtectionBlockReason
                                .NoSupportedExpiringCredits,
                            availableCount: summary.AvailableCount);
                        return;
                    }

                    var clockReason =
                        ResetCreditProtectionAuthorization.ClockDiscontinuity(
                            clockAnchor,
                            ResetCreditProtectionClockSample.Now());
                    if (clockReason is not null)
                    {
                        DisableRequestedWithoutAuthorizationWrite();
                        SetBlocked(
                            ResetCreditProtectionBlockReason.ClockChanged,
                            detail: clockReason.ToString());
                        RaiseNotice(false, "reset-credit-protection-clock-changed");
                        return;
                    }

                    token.ThrowIfCancellationRequested();
                    ThrowIfSuperseded(generation);
                    var consent = new ResetCreditProtectionConsent(
                        ResetCreditProtectionAuthorization.ConsentVersion,
                        accountFingerprint,
                        Guid.NewGuid().ToString(),
                        now,
                        authorized,
                        clockAnchor);
                    _authorizationStore.Save(consent, () =>
                    {
                        token.ThrowIfCancellationRequested();
                        ThrowIfSuperseded(generation);
                        _settings.ResetCreditProtectionEnabled = true;
                        _settings.Save();
                    });
                    try
                    {
                        token.ThrowIfCancellationRequested();
                        ThrowIfSuperseded(generation);
                    }
                    catch
                    {
                        _authorizationStore.ClearIfCurrent(
                            consent,
                            DisableRequestedWithoutAuthorizationWrite);
                        throw;
                    }
                    _consent = consent;

                    if (decision.Kind
                        == ResetCreditProtectionDecisionKind.Ready)
                    {
                        await AttemptWhileLockedAsync(
                                target, null, client, generation, token)
                            .ConfigureAwait(false);
                    }
                    else
                    {
                        ApplyDecisionStatus(decision);
                    }
                }
                catch (OperationCanceledException)
                    when (token.IsCancellationRequested)
                {
                    if (_settings.ResetCreditProtectionEnabled)
                        SetStatus(ResetCreditProtectionStatus.Disabled);
                }
                catch (ResetCreditProtectionAccountBindingException ex)
                {
                    HandleAccountFailure(ex, null);
                }
                catch (Exception ex)
                {
                    SetBlockedForException(ex);
                }
            },
            cancellationToken);

    public Task PreviewAsync(CancellationToken cancellationToken) =>
        RunExclusiveAsync(
            async token =>
            {
                if (_ledger.ActiveAttempt is not null)
                {
                    await EvaluateCoreAsync(token).ConfigureAwait(false);
                    return;
                }
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Checking));
                try
                {
                    await using var client = new AppServerClient();
                    var accountFingerprint =
                        await ReadAccountFingerprintAsync(client, token)
                            .ConfigureAwait(false);
                    var response = await ReadBoundRateLimitsAsync(
                            client, accountFingerprint, token)
                        .ConfigureAwait(false);
                    PublishCache(response.ResetCredits, force: true);
                    if (response.ResetCredits is not { } summary)
                    {
                        SetBlocked(
                            ResetCreditProtectionBlockReason.DetailsUnavailable);
                        return;
                    }

                    var decision = ResetCreditExpiryProtectionPolicy.Decide(
                        summary,
                        DateTimeOffset.UtcNow,
                        _ledger.ExcludedCreditFingerprints);
                    switch (decision.Kind)
                    {
                        case ResetCreditProtectionDecisionKind.NoCredits:
                            SetStatus(new ResetCreditProtectionStatus(
                                ResetCreditProtectionStatusKind.PreviewNoCredits,
                                OccurredAt: DateTimeOffset.Now));
                            break;
                        case ResetCreditProtectionDecisionKind.Scheduled:
                        case ResetCreditProtectionDecisionKind.Ready:
                            SetStatus(new ResetCreditProtectionStatus(
                                ResetCreditProtectionStatusKind.Preview,
                                ActionAt: decision.Target!.ActionAt,
                                ExpiresAt: decision.Target.ExpiresAt,
                                AvailableCount: decision.Target.AvailableCount,
                                ReadyNow: decision.Kind
                                          == ResetCreditProtectionDecisionKind
                                              .Ready));
                            break;
                        default:
                            ApplyDecisionStatus(decision);
                            break;
                    }
                }
                catch (OperationCanceledException)
                    when (token.IsCancellationRequested)
                {
                }
                catch (ResetCreditProtectionAccountBindingException ex)
                {
                    HandleAccountFailure(ex, null, revoke: false);
                }
                catch (Exception ex)
                {
                    SetBlockedForException(ex);
                }
            },
            cancellationToken);

    public Task EvaluateAsync(CancellationToken cancellationToken) =>
        RunExclusiveAsync(EvaluateCoreAsync, cancellationToken);

    /// <summary>
    /// Revocation deliberately does not wait for the long-running operation
    /// gate. It cancels the active session and writes the revocation marker
    /// under the same lock checked immediately before the JSON-RPC line is sent.
    /// </summary>
    public void Disable()
    {
        Interlocked.Increment(ref _generation);
        CancellationTokenSource? active;
        lock (_stateGate) active = _activeOperation;
        try { active?.Cancel(); } catch { }

        try
        {
            _settings.ResetCreditProtectionEnabled = false;
            _authorizationStore.Clear(() => _settings.Save());
            _consent = null;
            SetStatus(_ledger.ActiveAttempt is { } journal
                ? new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Reconciling,
                    ExpiresAt: journal.ExpiresAt)
                : ResetCreditProtectionStatus.Disabled);
        }
        catch
        {
            DisableRequestedWithoutAuthorizationWrite();
            SetBlocked(
                ResetCreditProtectionBlockReason.JournalUnavailable);
        }
    }

    private async Task EvaluateCoreAsync(CancellationToken token)
    {
        if (_settings.Preview != DashboardPreview.Live)
        {
            if (_settings.ResetCreditProtectionEnabled) Disable();
            SetStatus(ResetCreditProtectionStatus.Disabled);
            return;
        }

        var journal = ReloadLedger();
        if (_ledgerCorrupt)
        {
            FailClosed();
            return;
        }
        if (journal is not null)
        {
            using var processLock =
                ResetCreditProtectionProcessLock.TryAcquire();
            if (processLock is null)
            {
                _nextRetryAt = DateTimeOffset.UtcNow + RetryDelay;
                SetBlocked(
                    ResetCreditProtectionBlockReason.AnotherProcess);
                return;
            }
            await ReconcileJournalWhileLockedAsync(journal, token)
                .ConfigureAwait(false);
            return;
        }
        if (!_settings.ResetCreditProtectionEnabled)
        {
            _consent = null;
            SetStatus(ResetCreditProtectionStatus.Disabled);
            return;
        }

        var storageState = _authorizationStore.ValidateClockOrRevoke(
            ResetCreditProtectionClockSample.Now(),
            out var consent,
            out var clockReason);
        if (storageState == ProtectionStorageState.Corrupt)
        {
            FailClosed();
            return;
        }
        if (storageState != ProtectionStorageState.Loaded
            || consent is null)
        {
            DisableRequestedWithoutAuthorizationWrite();
            _consent = null;
            if (clockReason is not null)
            {
                SetBlocked(
                    ResetCreditProtectionBlockReason.ClockChanged,
                    detail: clockReason.ToString());
                RaiseNotice(false, "reset-credit-protection-clock-changed");
            }
            else
            {
                SetStatus(ResetCreditProtectionStatus.Disabled);
            }
            return;
        }
        _consent = consent;

        try
        {
            await using var client = new AppServerClient();
            var response = await ReadBoundRateLimitsAsync(
                    client, consent.AccountFingerprint, token)
                .ConfigureAwait(false);
            PublishCache(response.ResetCredits);
            if (response.ResetCredits is not { } summary)
            {
                SetBlocked(
                    ResetCreditProtectionBlockReason.DetailsUnavailable);
                return;
            }

            var decision = ResetCreditExpiryProtectionPolicy.Decide(
                summary,
                DateTimeOffset.UtcNow,
                _ledger.ExcludedCreditFingerprints);
            if (decision.Target is { } selected
                && !ResetCreditProtectionAuthorization.Authorizes(
                    _settings.ResetCreditProtectionEnabled,
                    consent,
                    selected.CreditFingerprint))
            {
                RevokeExpected(consent);
                SetBlocked(
                    ResetCreditProtectionBlockReason.CreditNotAuthorized);
                return;
            }

            if (decision.Kind == ResetCreditProtectionDecisionKind.Ready
                && decision.Target is { } target)
            {
                if (_nextRetryAt > DateTimeOffset.UtcNow)
                {
                    SetStatus(new ResetCreditProtectionStatus(
                        ResetCreditProtectionStatusKind.WaitingForUsage,
                        ExpiresAt: target.ExpiresAt));
                    return;
                }
                await AttemptWithProcessLockAsync(target, token)
                    .ConfigureAwait(false);
                return;
            }
            ApplyDecisionStatus(decision);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
        }
        catch (ResetCreditProtectionAccountBindingException ex)
        {
            HandleAccountFailure(ex, null);
        }
        catch (Exception ex)
        {
            SetBlockedForException(ex);
        }
    }

    private async Task AttemptWithProcessLockAsync(
        ResetCreditProtectionTarget target,
        CancellationToken token)
    {
        using var processLock =
            ResetCreditProtectionProcessLock.TryAcquire();
        if (processLock is null)
        {
            _nextRetryAt = DateTimeOffset.UtcNow + RetryDelay;
            SetBlocked(ResetCreditProtectionBlockReason.AnotherProcess);
            return;
        }
        var journal = ReloadLedger();
        if (_ledgerCorrupt)
        {
            FailClosed();
            return;
        }
        if (journal is not null)
        {
            await ReconcileJournalWhileLockedAsync(journal, token)
                .ConfigureAwait(false);
            return;
        }
        await using var client = new AppServerClient();
        await AttemptWhileLockedAsync(
                target,
                null,
                client,
                Volatile.Read(ref _generation),
                token)
            .ConfigureAwait(false);
    }

    private async Task AttemptWhileLockedAsync(
        ResetCreditProtectionTarget target,
        ResetCreditProtectionAttemptJournal? existingJournal,
        AppServerClient client,
        long generation,
        CancellationToken token)
    {
        if (_settings.Preview != DashboardPreview.Live)
        {
            SetStatus(ResetCreditProtectionStatus.Disabled);
            return;
        }

        var loaded = _authorizationStore.Load();
        if (loaded.State == ProtectionStorageState.Corrupt)
        {
            FailClosed();
            return;
        }
        if (loaded.State != ProtectionStorageState.Loaded
            || loaded.Value is not { } consent)
        {
            DisableRequestedWithoutAuthorizationWrite();
            _consent = null;
            if (existingJournal is null)
                SetStatus(ResetCreditProtectionStatus.Disabled);
            return;
        }
        if (!ResetCreditProtectionAuthorization.Authorizes(
                _settings.ResetCreditProtectionEnabled,
                consent,
                target.CreditFingerprint))
        {
            RevokeExpected(consent);
            if (existingJournal is null)
                SetBlocked(
                    ResetCreditProtectionBlockReason.CreditNotAuthorized);
            return;
        }
        _consent = consent;
        SetStatus(new ResetCreditProtectionStatus(
            ResetCreditProtectionStatusKind.Checking));

        ResetCreditProtectionAttemptJournal? journal = null;
        var dispatched = false;
        try
        {
            var preflight = await ReadBoundRateLimitsAsync(
                    client, consent.AccountFingerprint, token)
                .ConfigureAwait(false);
            PublishCache(preflight.ResetCredits);
            if (!_settings.ResetCreditProtectionEnabled
                || preflight.ResetCredits is not { } summary)
            {
                SetBlocked(
                    ResetCreditProtectionBlockReason.DetailsUnavailable);
                return;
            }

            var now = DateTimeOffset.UtcNow;
            ResetCreditProtectionTarget validatedTarget;
            if (existingJournal is not null)
            {
                var recovery =
                    ResetCreditProtectionRecoveryPolicy.Decide(
                        existingJournal,
                        summary,
                        now,
                        protectionEnabled: true);
                if (recovery.Kind
                        != ResetCreditRecoveryDecisionKind.Retry
                    || recovery.Target is not { } currentTarget
                    || currentTarget.CreditFingerprint
                    != target.CreditFingerprint)
                {
                    await ApplyRecoveryAsync(
                            existingJournal, summary, client, token)
                        .ConfigureAwait(false);
                    return;
                }
                validatedTarget = currentTarget;
            }
            else
            {
                var decision = ResetCreditExpiryProtectionPolicy.Decide(
                    summary,
                    now,
                    _ledger.ExcludedCreditFingerprints);
                if (decision.Kind
                        != ResetCreditProtectionDecisionKind.Ready
                    || decision.Target is not { } currentTarget
                    || currentTarget.CreditFingerprint
                    != target.CreditFingerprint)
                {
                    ApplyDecisionStatus(decision);
                    return;
                }
                validatedTarget = currentTarget;
            }

            if (!ResetCreditProtectionAuthorization.Authorizes(
                    _settings.ResetCreditProtectionEnabled,
                    consent,
                    validatedTarget.CreditFingerprint))
            {
                RevokeExpected(consent);
                SetBlocked(
                    ResetCreditProtectionBlockReason.CreditNotAuthorized);
                return;
            }

            var currentFingerprints = CurrentFingerprints(summary, now);
            var remainingAuthorized =
                new HashSet<string>(
                    consent.AuthorizedCreditFingerprints,
                    StringComparer.Ordinal);
            remainingAuthorized.ExceptWith(
                _ledger.ExcludedCreditFingerprints);
            if (currentFingerprints is null
                || !currentFingerprints.SetEquals(remainingAuthorized))
            {
                RevokeExpected(consent);
                SetBlocked(
                    ResetCreditProtectionBlockReason.CreditNotAuthorized);
                return;
            }

            var details = summary.Credits;
            if (details is null)
            {
                SetBlocked(
                    ResetCreditProtectionBlockReason.DetailsUnavailable,
                    availableCount: summary.AvailableCount);
                return;
            }
            var matching = details.Where(credit =>
                    ResetCreditPrivacy.Fingerprint(credit.Id)
                    == validatedTarget.CreditFingerprint)
                .ToArray();
            if (matching.Length != 1)
            {
                SetBlocked(
                    ResetCreditProtectionBlockReason.DetailsIncomplete,
                    availableCount: summary.AvailableCount,
                    availableDetails:
                    details.Count(credit => credit.IsAvailable));
                return;
            }

            journal = existingJournal
                      ?? new ResetCreditProtectionAttemptJournal(
                          1,
                          consent.AccountFingerprint,
                          validatedTarget.CreditFingerprint,
                          Guid.NewGuid().ToString(),
                          validatedTarget.ExpiresAt,
                          summary.AvailableCount,
                          ResetCreditAttemptPhase.Sending,
                          null,
                          now);
            if (journal.AccountFingerprint
                    != consent.AccountFingerprint
                || journal.CreditFingerprint
                != validatedTarget.CreditFingerprint)
            {
                HandleAccountFailure(
                    new ResetCreditProtectionAccountBindingException(
                        ResetCreditProtectionAccountBindingFailure
                            .AccountChanged),
                    journal);
                return;
            }
            journal = journal with
            {
                Phase = ResetCreditAttemptPhase.Sending,
                ConfirmedOutcome = null,
                UpdatedAt = now
            };
            SaveActiveJournal(journal);

            token.ThrowIfCancellationRequested();
            ThrowIfSuperseded(generation);
            if (!_settings.ResetCreditProtectionEnabled
                || _settings.Preview != DashboardPreview.Live)
            {
                RestorePreDispatchJournal(existingJournal);
                SetStatus(ResetCreditProtectionStatus.Disabled);
                return;
            }
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Using,
                ExpiresAt: validatedTarget.ExpiresAt));

            ResetCreditConsumeOutcome outcome;
            try
            {
                outcome = await ConsumeBoundAsync(
                        client,
                        matching[0].Id,
                        journal.IdempotencyKey,
                        consent,
                        validatedTarget.CreditFingerprint,
                        generation,
                        () => dispatched = true,
                        token)
                    .ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                if (!dispatched)
                {
                    RestorePreDispatchJournal(existingJournal);
                    if (ex is ResetCreditAuthorizationException
                        || ex is ResetCreditPreDispatchException
                        || ex is OperationCanceledException)
                    {
                        if (_settings.ResetCreditProtectionEnabled)
                            RevokeExpected(consent);
                        SetStatus(_settings.ResetCreditProtectionEnabled
                            ? new ResetCreditProtectionStatus(
                                ResetCreditProtectionStatusKind.Blocked,
                                BlockReason:
                                ResetCreditProtectionBlockReason.RequestFailed)
                            : ResetCreditProtectionStatus.Disabled);
                        return;
                    }
                    if (ex
                        is ResetCreditProtectionAccountBindingException
                            preDispatchBinding)
                    {
                        HandleAccountFailure(
                            preDispatchBinding, existingJournal);
                        return;
                    }
                    SetBlockedForException(ex);
                    return;
                }

                journal = journal with
                {
                    Phase = ResetCreditAttemptPhase.SentUnknown,
                    ConfirmedOutcome = null,
                    UpdatedAt = DateTimeOffset.UtcNow
                };
                SaveActiveJournal(journal);
                if (ex
                    is ResetCreditProtectionAccountBindingException
                        postDispatchBinding)
                {
                    HandleAccountFailure(postDispatchBinding, journal);
                    return;
                }
                if (IsUnsupported(ex))
                {
                    RevokeExpected(consent);
                    SetBlocked(
                        ResetCreditProtectionBlockReason.UnsupportedCodex);
                    return;
                }
                if (IsAuthenticationFailure(ex))
                {
                    RevokeExpected(consent);
                    SetBlocked(
                        ResetCreditProtectionBlockReason.SignedOut);
                    return;
                }
                _nextRetryAt = DateTimeOffset.UtcNow + RetryDelay;
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Reconciling,
                    ExpiresAt: journal.ExpiresAt));
                if (ex is not OperationCanceledException)
                {
                    await TryReconcileWithClientAsync(
                            journal, client, token)
                        .ConfigureAwait(false);
                }
                return;
            }

            journal = journal with
            {
                Phase = ResetCreditAttemptPhase.OutcomeConfirmed,
                ConfirmedOutcome = outcome,
                UpdatedAt = DateTimeOffset.UtcNow
            };
            SaveActiveJournal(journal);
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Reconciling,
                ExpiresAt: journal.ExpiresAt));
            await TryReconcileWithClientAsync(journal, client, token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            if (journal is not null && dispatched)
            {
                SaveActiveJournal(journal with
                {
                    Phase = ResetCreditAttemptPhase.SentUnknown,
                    ConfirmedOutcome = null,
                    UpdatedAt = DateTimeOffset.UtcNow
                });
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Reconciling,
                    ExpiresAt: journal.ExpiresAt));
            }
            else
            {
                RestorePreDispatchJournal(existingJournal);
            }
        }
        catch (ResetCreditProtectionAccountBindingException ex)
        {
            HandleAccountFailure(ex, journal ?? existingJournal);
        }
        catch (Exception ex)
        {
            SetBlockedForException(ex);
        }
    }

    private async Task ReconcileJournalWhileLockedAsync(
        ResetCreditProtectionAttemptJournal journal,
        CancellationToken token)
    {
        try
        {
            await using var client = new AppServerClient();
            var response = await ReadBoundRateLimitsAsync(
                    client, journal.AccountFingerprint, token)
                .ConfigureAwait(false);
            PublishCache(response.ResetCredits);
            await ApplyRecoveryAsync(
                    journal, response.ResetCredits, client, token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Reconciling,
                ExpiresAt: journal.ExpiresAt));
        }
        catch (ResetCreditProtectionAccountBindingException ex)
        {
            HandleAccountFailure(ex, journal);
        }
        catch (Exception ex)
        {
            if (DateTimeOffset.UtcNow >= journal.ExpiresAt)
                MarkMissed(journal);
            else
                SetBlockedForException(ex, journal.ExpiresAt);
        }
    }

    private async Task TryReconcileWithClientAsync(
        ResetCreditProtectionAttemptJournal journal,
        AppServerClient client,
        CancellationToken token)
    {
        try
        {
            var response = await ReadBoundRateLimitsAsync(
                    client, journal.AccountFingerprint, token)
                .ConfigureAwait(false);
            PublishCache(response.ResetCredits);
            await ApplyRecoveryAsync(
                    journal, response.ResetCredits, client, token)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
            when (token.IsCancellationRequested)
        {
        }
        catch (ResetCreditProtectionAccountBindingException ex)
        {
            HandleAccountFailure(ex, journal);
        }
        catch
        {
            _nextRetryAt = DateTimeOffset.UtcNow + RetryDelay;
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Reconciling,
                ExpiresAt: journal.ExpiresAt));
        }
    }

    private async Task ApplyRecoveryAsync(
        ResetCreditProtectionAttemptJournal journal,
        RateLimitResetCreditsSummary? summary,
        AppServerClient client,
        CancellationToken token)
    {
        var decision = ResetCreditProtectionRecoveryPolicy.Decide(
            journal,
            summary,
            DateTimeOffset.UtcNow,
            Enabled,
            _nextRetryAt);
        switch (decision.Kind)
        {
            case ResetCreditRecoveryDecisionKind.ConfirmedUsed:
                FinishVerified(journal);
                break;
            case ResetCreditRecoveryDecisionKind.ConfirmedNotConsumed:
                ClearActiveJournal();
                _nextRetryAt = DateTimeOffset.UtcNow + RetryDelay;
                SetStatus(Enabled
                    ? new ResetCreditProtectionStatus(
                        ResetCreditProtectionStatusKind.WaitingForUsage,
                        ExpiresAt: decision.ExpiresAt)
                    : ResetCreditProtectionStatus.Disabled);
                break;
            case ResetCreditRecoveryDecisionKind.Reconciling:
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Reconciling,
                    ExpiresAt: journal.ExpiresAt));
                break;
            case ResetCreditRecoveryDecisionKind.Missed:
                MarkMissed(journal);
                break;
            case ResetCreditRecoveryDecisionKind.Retry:
                await AttemptWhileLockedAsync(
                        decision.Target!,
                        journal,
                        client,
                        Volatile.Read(ref _generation),
                        token)
                    .ConfigureAwait(false);
                break;
        }
    }

    private static async Task<string> ReadAccountFingerprintAsync(
        AppServerClient client,
        CancellationToken token)
    {
        var account = await client.ReadAccountAsync(token)
            .ConfigureAwait(false);
        if (account.ProtectionIdentitySeed is not { } seed)
            throw new ResetCreditProtectionAccountBindingException(
                ResetCreditProtectionAccountBindingFailure
                    .AccountUnavailable);
        return ResetCreditPrivacy.Fingerprint(seed);
    }

    private static async Task VerifyAccountAsync(
        AppServerClient client,
        string expectedFingerprint,
        CancellationToken token)
    {
        var current = await ReadAccountFingerprintAsync(client, token)
            .ConfigureAwait(false);
        if (!string.Equals(
                current, expectedFingerprint, StringComparison.Ordinal))
            throw new ResetCreditProtectionAccountBindingException(
                ResetCreditProtectionAccountBindingFailure.AccountChanged);
    }

    private static async Task<ProtectionRateLimitResponse>
        ReadBoundRateLimitsAsync(
            AppServerClient client,
            string accountFingerprint,
            CancellationToken token)
    {
        await VerifyAccountAsync(client, accountFingerprint, token)
            .ConfigureAwait(false);
        var response = await client.ReadProtectionRateLimitsAsync(token)
            .ConfigureAwait(false);
        await VerifyAccountAsync(client, accountFingerprint, token)
            .ConfigureAwait(false);
        return response;
    }

    private async Task<ResetCreditConsumeOutcome> ConsumeBoundAsync(
        AppServerClient client,
        string creditId,
        string idempotencyKey,
        ResetCreditProtectionConsent consent,
        string creditFingerprint,
        long generation,
        Action markDispatched,
        CancellationToken token)
    {
        await VerifyAccountAsync(
                client, consent.AccountFingerprint, token)
            .ConfigureAwait(false);
        ResetCreditConsumeOutcome? outcome = null;
        Exception? failure = null;
        try
        {
            outcome = await client.ConsumeResetCreditAsync(
                    creditId,
                    idempotencyKey,
                    dispatch => _authorizationStore.PerformAuthorizedDispatch(
                        consent,
                        creditFingerprint,
                        () =>
                        {
                            if (!_settings.ResetCreditProtectionEnabled
                                || _settings.Preview
                                != DashboardPreview.Live
                                || generation
                                != Volatile.Read(ref _generation))
                                throw new ResetCreditAuthorizationException(
                                    "Reset-credit authorization was revoked.");
                            token.ThrowIfCancellationRequested();
                            // Once the authorization gate opens, classify every
                            // subsequent transport failure as sent-unknown. A
                            // synchronous pipe write can fail after emitting a
                            // partial JSON line, so marking only after WriteLine
                            // returns could permit an unsafe blind retry.
                            markDispatched();
                            dispatch();
                        }),
                    token)
                .ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            failure = ex;
        }

        await VerifyAccountAsync(
                client, consent.AccountFingerprint, token)
            .ConfigureAwait(false);
        if (failure is not null)
            System.Runtime.ExceptionServices.ExceptionDispatchInfo
                .Capture(failure).Throw();
        return outcome
               ?? throw new InvalidDataException(
                   "Codex returned no reset-credit outcome.");
    }

    private HashSet<string>? CurrentFingerprints(
        RateLimitResetCreditsSummary summary,
        DateTimeOffset now)
    {
        var availableCount = Math.Max(0, summary.AvailableCount);
        if (availableCount == 0)
            return summary.Credits?.Any(credit => credit.IsAvailable)
                       == true
                ? null
                : [];
        if (summary.Credits is null) return null;
        var available = summary.Credits
            .Where(credit => credit.IsAvailable).ToArray();
        var uniqueIds = available.Select(credit => credit.Id)
            .ToHashSet(StringComparer.Ordinal);
        if (available.Length != availableCount
            || available.Any(credit => string.IsNullOrEmpty(credit.Id))
            || uniqueIds.Count != availableCount)
            return null;

        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (var credit in available)
        {
            var fingerprint =
                ResetCreditPrivacy.Fingerprint(credit.Id);
            if (credit.IsSupportedCodexReset
                && credit.ExpiresAtDate is { } expiry
                && expiry > now
                && !_ledger.ExcludedCreditFingerprints.Contains(
                    fingerprint))
                result.Add(fingerprint);
        }
        return result;
    }

    private void ApplyDecisionStatus(
        ResetCreditProtectionDecision decision)
    {
        switch (decision.Kind)
        {
            case ResetCreditProtectionDecisionKind.NoCredits:
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.NoCredits,
                    OccurredAt: DateTimeOffset.Now));
                break;
            case ResetCreditProtectionDecisionKind.DetailsUnavailable:
                SetBlocked(
                    ResetCreditProtectionBlockReason.DetailsUnavailable,
                    availableCount: decision.AvailableCount);
                break;
            case ResetCreditProtectionDecisionKind.DetailsIncomplete:
                SetBlocked(
                    ResetCreditProtectionBlockReason.DetailsIncomplete,
                    availableCount: decision.AvailableCount,
                    availableDetails: decision.AvailableDetails);
                break;
            case ResetCreditProtectionDecisionKind
                .NoSupportedExpiringCredits:
                SetBlocked(
                    ResetCreditProtectionBlockReason
                        .NoSupportedExpiringCredits,
                    availableCount: decision.AvailableCount);
                break;
            case ResetCreditProtectionDecisionKind.Scheduled:
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Scheduled,
                    ActionAt: decision.Target!.ActionAt,
                    ExpiresAt: decision.Target.ExpiresAt,
                    AvailableCount: decision.Target.AvailableCount));
                break;
            case ResetCreditProtectionDecisionKind.Ready:
                SetStatus(new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Checking));
                break;
        }
    }

    private void PublishCache(
        RateLimitResetCreditsSummary? summary,
        bool force = false)
    {
        if (summary is null
            || (!force && !Enabled && _ledger.ActiveAttempt is null))
            return;
        var credits = summary.Credits?.Select(credit =>
                new ResetCredit(
                    credit.Title ?? "",
                    credit.Status,
                    credit.GrantedAtDate.ToLocalTime(),
                    credit.ExpiresAtDate?.ToLocalTime(),
                    ResetCreditPrivacy.Fingerprint(credit.Id),
                    credit.ResetType))
            .ToArray() ?? [];
        CreditsChanged?.Invoke(
            this,
            new ResetCreditProtectionCacheUpdate(
                credits,
                Math.Max(0, summary.AvailableCount),
                DateTimeOffset.Now));
    }

    private ResetCreditProtectionAttemptJournal? ReloadLedger()
    {
        var loaded = _ledgerStore.Load();
        switch (loaded.State)
        {
            case ProtectionStorageState.Absent:
                _ledger = new ResetCreditProtectionLedger();
                _ledgerCorrupt = false;
                return null;
            case ProtectionStorageState.Loaded:
                _ledger = loaded.Value!;
                _ledgerCorrupt = false;
                return _ledger.ActiveAttempt;
            default:
                _ledger = new ResetCreditProtectionLedger();
                _ledgerCorrupt = true;
                return null;
        }
    }

    private void SaveActiveJournal(
        ResetCreditProtectionAttemptJournal journal)
    {
        _ledger.ActiveAttempt = journal;
        _ledgerStore.Save(_ledger);
        _ledgerCorrupt = false;
    }

    private void RestorePreDispatchJournal(
        ResetCreditProtectionAttemptJournal? existing)
    {
        _ledger.ActiveAttempt = existing;
        _ledgerStore.Save(_ledger);
        _ledgerCorrupt = false;
    }

    private void ClearActiveJournal()
    {
        _ledger.ActiveAttempt = null;
        _ledgerStore.Save(_ledger);
        _ledgerCorrupt = false;
    }

    private void ArchiveJournal(
        ResetCreditProtectionAttemptJournal journal,
        ResetCreditTombstoneDisposition disposition)
    {
        if (_ledger.ActiveAttempt != journal)
            throw new InvalidDataException(
                "Reset-credit journal changed during reconciliation.");
        _ledger.ActiveAttempt = null;
        _ledger.Tombstones.Add(
            new ResetCreditProtectionTombstone(
                journal.AccountFingerprint,
                journal.CreditFingerprint,
                journal.IdempotencyKey,
                journal.ExpiresAt,
                disposition,
                DateTimeOffset.UtcNow));
        _ledgerStore.Save(_ledger);
        _ledgerCorrupt = false;
    }

    private void FinishVerified(
        ResetCreditProtectionAttemptJournal journal)
    {
        try
        {
            ArchiveJournal(
                journal,
                ResetCreditTombstoneDisposition.ConfirmedUsed);
            _nextRetryAt = null;
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Succeeded,
                ExpiresAt: journal.ExpiresAt,
                OccurredAt: DateTimeOffset.Now));
            RaiseNotice(
                true,
                "reset-credit-protection-success-"
                + journal.CreditFingerprint,
                journal.ExpiresAt);
        }
        catch
        {
            FailClosed();
        }
    }

    private void MarkMissed(
        ResetCreditProtectionAttemptJournal journal)
    {
        try
        {
            ArchiveJournal(
                journal,
                ResetCreditTombstoneDisposition.Ambiguous);
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Missed,
                ExpiresAt: journal.ExpiresAt));
            RaiseNotice(
                false,
                "reset-credit-protection-missed-"
                + journal.ExpiresAt.ToUnixTimeSeconds(),
                journal.ExpiresAt);
        }
        catch
        {
            FailClosed();
        }
    }

    private void HandleAccountFailure(
        ResetCreditProtectionAccountBindingException exception,
        ResetCreditProtectionAttemptJournal? journal,
        bool revoke = true)
    {
        if (journal is not null
            && DateTimeOffset.UtcNow >= journal.ExpiresAt)
        {
            MarkMissed(journal);
            return;
        }
        if (revoke && _consent is { } consent)
            RevokeExpected(consent);
        SetBlocked(
            exception.Failure
            == ResetCreditProtectionAccountBindingFailure.AccountChanged
                ? ResetCreditProtectionBlockReason.AccountChanged
                : ResetCreditProtectionBlockReason.SignedOut);
        RaiseNotice(
            false,
            exception.Failure
            == ResetCreditProtectionAccountBindingFailure.AccountChanged
                ? "reset-credit-protection-account-changed"
                : "reset-credit-protection-signed-out",
            journal?.ExpiresAt);
    }

    private void RevokeExpected(
        ResetCreditProtectionConsent consent)
    {
        try
        {
            if (_authorizationStore.ClearIfCurrent(
                    consent,
                    DisableRequestedWithoutAuthorizationWrite))
            {
                if (ReferenceEquals(_consent, consent)
                    || ResetCreditProtectionAuthorizationStore.Equivalent(
                        _consent, consent))
                    _consent = null;
            }
        }
        catch
        {
            DisableRequestedWithoutAuthorizationWrite();
            _consent = null;
        }
    }

    private void FailClosed()
    {
        _ledgerCorrupt = true;
        _consent = null;
        try
        {
            _authorizationStore.Clear(
                DisableRequestedWithoutAuthorizationWrite);
        }
        catch
        {
            DisableRequestedWithoutAuthorizationWrite();
        }
        SetBlocked(
            ResetCreditProtectionBlockReason.JournalUnavailable);
        RaiseNotice(
            false,
            "reset-credit-protection-authorization-unavailable");
    }

    private void DisableRequestedWithoutAuthorizationWrite()
    {
        _settings.ResetCreditProtectionEnabled = false;
        try { _settings.Save(); } catch { }
    }

    private void RestorePersistedState()
    {
        var journal = ReloadLedger();
        if (_ledgerCorrupt)
        {
            FailClosed();
            return;
        }
        if (_settings.Preview != DashboardPreview.Live)
        {
            if (_settings.ResetCreditProtectionEnabled)
                Disable();
            return;
        }

        var state = _authorizationStore.ValidateClockOrRevoke(
            ResetCreditProtectionClockSample.Now(),
            out var consent,
            out var reason);
        if (state == ProtectionStorageState.Corrupt)
        {
            FailClosed();
            return;
        }
        if (_settings.ResetCreditProtectionEnabled
            && state == ProtectionStorageState.Loaded
            && consent is not null)
        {
            _consent = consent;
            SetStatus(journal is null
                ? new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Checking)
                : new ResetCreditProtectionStatus(
                    ResetCreditProtectionStatusKind.Reconciling,
                    ExpiresAt: journal.ExpiresAt));
            return;
        }

        if (!_settings.ResetCreditProtectionEnabled
            && state == ProtectionStorageState.Loaded)
        {
            try { _authorizationStore.Clear(); }
            catch
            {
                SetBlocked(
                    ResetCreditProtectionBlockReason.JournalUnavailable);
                return;
            }
        }
        if (_settings.ResetCreditProtectionEnabled)
            DisableRequestedWithoutAuthorizationWrite();
        if (journal is not null)
        {
            SetStatus(new ResetCreditProtectionStatus(
                ResetCreditProtectionStatusKind.Reconciling,
                ExpiresAt: journal.ExpiresAt));
        }
        else if (reason is not null)
        {
            SetBlocked(
                ResetCreditProtectionBlockReason.ClockChanged,
                detail: reason.ToString());
        }
    }

    private async Task RunExclusiveAsync(
        Func<CancellationToken, Task> operation,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _operationGate.WaitAsync(cancellationToken)
            .ConfigureAwait(false);
        using var linked =
            CancellationTokenSource.CreateLinkedTokenSource(
                cancellationToken);
        lock (_stateGate) _activeOperation = linked;
        try
        {
            await operation(linked.Token).ConfigureAwait(false);
        }
        finally
        {
            lock (_stateGate)
            {
                if (ReferenceEquals(_activeOperation, linked))
                    _activeOperation = null;
            }
            _operationGate.Release();
        }
    }

    private void ThrowIfSuperseded(long generation)
    {
        if (generation != Volatile.Read(ref _generation))
            throw new OperationCanceledException(
                "Reset-credit protection operation was superseded.");
    }

    private void SetBlockedForException(
        Exception exception,
        DateTimeOffset? expiresAt = null)
    {
        var reason = exception switch
        {
            FileNotFoundException =>
                ResetCreditProtectionBlockReason.CodexUnavailable,
            AppServerRpcException rpc when rpc.Code == -32601 =>
                ResetCreditProtectionBlockReason.UnsupportedCodex,
            _ when IsAuthenticationFailure(exception) =>
                ResetCreditProtectionBlockReason.SignedOut,
            _ => ResetCreditProtectionBlockReason.RequestFailed
        };
        SetBlocked(
            reason,
            expiresAt: expiresAt,
            detail: reason == ResetCreditProtectionBlockReason.RequestFailed
                ? exception.GetType().Name
                : null);
    }

    private static bool IsUnsupported(Exception exception) =>
        exception is AppServerRpcException { Code: -32601 };

    private static bool IsAuthenticationFailure(Exception exception) =>
        exception.Message.Contains(
            "authentication",
            StringComparison.OrdinalIgnoreCase)
        || exception.Message.Contains(
            "not logged in",
            StringComparison.OrdinalIgnoreCase);

    private void SetBlocked(
        ResetCreditProtectionBlockReason reason,
        int availableCount = 0,
        int availableDetails = 0,
        DateTimeOffset? expiresAt = null,
        string? detail = null) =>
        SetStatus(new ResetCreditProtectionStatus(
            ResetCreditProtectionStatusKind.Blocked,
            ExpiresAt: expiresAt,
            AvailableCount: availableCount,
            AvailableDetails: availableDetails,
            BlockReason: reason,
            Detail: detail));

    private void SetStatus(ResetCreditProtectionStatus status)
    {
        var changed = false;
        lock (_stateGate)
        {
            if (_status != status)
            {
                _status = status;
                changed = true;
            }
        }
        if (changed) StatusChanged?.Invoke(this, EventArgs.Empty);
    }

    private void RaiseNotice(
        bool success,
        string identifier,
        DateTimeOffset? expiresAt = null) =>
        NoticeRaised?.Invoke(
            this,
            new ResetCreditProtectionNotice(
                success, identifier, expiresAt));

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        CancellationTokenSource? active;
        lock (_stateGate)
        {
            active = _activeOperation;
            _activeOperation = null;
        }
        try { active?.Cancel(); } catch { }
    }
}
