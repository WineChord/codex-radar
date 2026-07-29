using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexRadar.Windows;

internal enum ProtectionStorageState
{
    Absent,
    Loaded,
    Corrupt
}

internal sealed record ProtectionStorageLoad<T>(
    ProtectionStorageState State,
    T? Value = default);

internal static class ResetCreditProtectionPaths
{
    public static readonly string DirectoryPath = Path.Combine(
        AppSettings.SettingsDirectory, "reset-credit-protection");
    public static readonly string ProcessLock = Path.Combine(
        DirectoryPath, "process.lock");
    public static readonly string DispatchLock = Path.Combine(
        DirectoryPath, "dispatch.lock");
    public static readonly string Authorization = Path.Combine(
        DirectoryPath, "authorization-v2.json");
    public static readonly string Ledger = Path.Combine(
        DirectoryPath, "ledger-v1.json");
}

internal static class ResetCreditProtectionJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };
}

internal sealed class ResetCreditProtectionProcessLock : IDisposable
{
    private FileStream? _stream;

    private ResetCreditProtectionProcessLock(FileStream stream) => _stream = stream;

    public static ResetCreditProtectionProcessLock? TryAcquire()
    {
        try
        {
            Directory.CreateDirectory(ResetCreditProtectionPaths.DirectoryPath);
            return new ResetCreditProtectionProcessLock(new FileStream(
                ResetCreditProtectionPaths.ProcessLock,
                FileMode.OpenOrCreate,
                FileAccess.ReadWrite,
                FileShare.None,
                1,
                FileOptions.WriteThrough));
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    public void Dispose()
    {
        Interlocked.Exchange(ref _stream, null)?.Dispose();
        GC.SuppressFinalize(this);
    }
}

internal sealed class ResetCreditProtectionAuthorizationStore
{
    private readonly string _authorizationPath;
    private readonly string _dispatchLockPath;

    public ResetCreditProtectionAuthorizationStore(
        string? authorizationPath = null,
        string? dispatchLockPath = null)
    {
        _authorizationPath = authorizationPath
                             ?? ResetCreditProtectionPaths.Authorization;
        _dispatchLockPath = dispatchLockPath
                            ?? ResetCreditProtectionPaths.DispatchLock;
    }

    private sealed record RevocationMarker(int Version, bool Revoked)
    {
        public static readonly RevocationMarker Current = new(1, true);
    }

    public ProtectionStorageLoad<ResetCreditProtectionConsent> Load()
    {
        if (!File.Exists(_authorizationPath))
            return new ProtectionStorageLoad<ResetCreditProtectionConsent>(
                ProtectionStorageState.Absent);
        try
        {
            var json = File.ReadAllText(_authorizationPath);
            var marker = JsonSerializer.Deserialize<RevocationMarker>(
                json, ResetCreditProtectionJson.Options);
            if (marker == RevocationMarker.Current)
                return new ProtectionStorageLoad<ResetCreditProtectionConsent>(
                    ProtectionStorageState.Absent);
            var consent = JsonSerializer.Deserialize<ResetCreditProtectionConsent>(
                json, ResetCreditProtectionJson.Options);
            return ResetCreditProtectionAuthorization.IsStructurallyValid(consent)
                ? new ProtectionStorageLoad<ResetCreditProtectionConsent>(
                    ProtectionStorageState.Loaded, consent)
                : new ProtectionStorageLoad<ResetCreditProtectionConsent>(
                    ProtectionStorageState.Corrupt);
        }
        catch
        {
            return new ProtectionStorageLoad<ResetCreditProtectionConsent>(
                ProtectionStorageState.Corrupt);
        }
    }

    public void Save(
        ResetCreditProtectionConsent consent,
        Action? enableRequested = null)
    {
        if (!ResetCreditProtectionAuthorization.IsStructurallyValid(consent))
            throw new InvalidDataException("Reset-credit authorization is invalid.");
        using var lease = AcquireDispatchLock();
        AtomicWrite(_authorizationPath, consent);
        try
        {
            enableRequested?.Invoke();
        }
        catch
        {
            AtomicWrite(
                _authorizationPath,
                RevocationMarker.Current);
            throw;
        }
    }

    public void Clear(Action? disableRequested = null)
    {
        using var lease = AcquireDispatchLock();
        disableRequested?.Invoke();
        AtomicWrite(_authorizationPath, RevocationMarker.Current);
    }

    public bool ClearIfCurrent(
        ResetCreditProtectionConsent expected,
        Action? disableRequested = null)
    {
        using var lease = AcquireDispatchLock();
        var current = Load();
        if (current.State == ProtectionStorageState.Corrupt)
            throw new InvalidDataException("Reset-credit authorization cannot be verified.");
        if (current.State == ProtectionStorageState.Loaded
            && !Equivalent(current.Value, expected))
            return false;
        disableRequested?.Invoke();
        AtomicWrite(_authorizationPath, RevocationMarker.Current);
        return true;
    }

    public ProtectionStorageState ValidateClockOrRevoke(
        ResetCreditProtectionClockSample current,
        out ResetCreditProtectionConsent? consent,
        out ClockDiscontinuityReason? reason)
    {
        using var lease = AcquireDispatchLock();
        var loaded = Load();
        consent = loaded.Value;
        reason = null;
        if (loaded.State == ProtectionStorageState.Loaded)
        {
            reason = ResetCreditProtectionAuthorization.ClockDiscontinuity(
                loaded.Value, current);
            if (reason is null) return ProtectionStorageState.Loaded;
            AtomicWrite(_authorizationPath, RevocationMarker.Current);
            return ProtectionStorageState.Absent;
        }
        if (loaded.State == ProtectionStorageState.Corrupt)
            AtomicWrite(_authorizationPath, RevocationMarker.Current);
        return loaded.State;
    }

    public void PerformAuthorizedDispatch(
        ResetCreditProtectionConsent expected,
        string creditFingerprint,
        Action body)
    {
        using var lease = AcquireDispatchLock();
        var loaded = Load();
        if (loaded.State != ProtectionStorageState.Loaded
            || loaded.Value is null
            || !Equivalent(loaded.Value, expected)
            || !ResetCreditProtectionAuthorization.Authorizes(
                true, loaded.Value, creditFingerprint))
            throw new ResetCreditAuthorizationException(
                loaded.State == ProtectionStorageState.Corrupt
                    ? "Reset-credit authorization cannot be verified."
                    : "Reset-credit authorization was revoked.");
        body();
    }

    public static bool Equivalent(
        ResetCreditProtectionConsent? left,
        ResetCreditProtectionConsent? right) =>
        left is not null && right is not null
        && left.Version == right.Version
        && left.AccountFingerprint == right.AccountFingerprint
        && left.AuthorizationId == right.AuthorizationId
        && left.GrantedAt == right.GrantedAt
        && left.ClockAnchor == right.ClockAnchor
        && left.AuthorizedCreditFingerprints.SetEquals(
            right.AuthorizedCreditFingerprints);

    private ExclusiveFileLease AcquireDispatchLock() =>
        ExclusiveFileLease.Acquire(
            _dispatchLockPath,
            blocking: true)
        ?? throw new IOException("Reset-credit dispatch lock is unavailable.");

    private static void AtomicWrite<T>(string path, T value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(
            value, ResetCreditProtectionJson.Options);
        var temporary = path + $".{Environment.ProcessId}.{Guid.NewGuid():N}.tmp";
        try
        {
            using (var stream = new FileStream(
                       temporary,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       4096,
                       FileOptions.WriteThrough))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }
            File.Move(temporary, path, true);
        }
        finally
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); } catch { }
        }
    }

    internal static void AtomicWriteForLedger<T>(string path, T value) =>
        AtomicWrite(path, value);
}

internal sealed class ResetCreditProtectionLedgerStore
{
    private readonly string _ledgerPath;

    public ResetCreditProtectionLedgerStore(string? ledgerPath = null) =>
        _ledgerPath = ledgerPath ?? ResetCreditProtectionPaths.Ledger;

    public ProtectionStorageLoad<ResetCreditProtectionLedger> Load()
    {
        if (!File.Exists(_ledgerPath))
            return new ProtectionStorageLoad<ResetCreditProtectionLedger>(
                ProtectionStorageState.Absent);
        try
        {
            var ledger = JsonSerializer.Deserialize<ResetCreditProtectionLedger>(
                File.ReadAllText(_ledgerPath),
                ResetCreditProtectionJson.Options);
            return IsValid(ledger)
                ? new ProtectionStorageLoad<ResetCreditProtectionLedger>(
                    ProtectionStorageState.Loaded, ledger)
                : new ProtectionStorageLoad<ResetCreditProtectionLedger>(
                    ProtectionStorageState.Corrupt);
        }
        catch
        {
            return new ProtectionStorageLoad<ResetCreditProtectionLedger>(
                ProtectionStorageState.Corrupt);
        }
    }

    public void Save(ResetCreditProtectionLedger ledger)
    {
        if (!IsValid(ledger))
            throw new InvalidDataException("Reset-credit ledger is invalid.");
        ResetCreditProtectionAuthorizationStore.AtomicWriteForLedger(
            _ledgerPath, ledger);
    }

    internal static bool IsValid(ResetCreditProtectionLedger? ledger)
    {
        if (ledger is not { Version: 1 }) return false;
        if (ledger.ActiveAttempt is not null && !IsValid(ledger.ActiveAttempt))
            return false;
        var fingerprints = new HashSet<string>(StringComparer.Ordinal);
        foreach (var tombstone in ledger.Tombstones)
        {
            if (!ResetCreditPrivacy.IsValidFingerprint(tombstone.AccountFingerprint)
                || !ResetCreditPrivacy.IsValidFingerprint(tombstone.CreditFingerprint)
                || !Guid.TryParse(tombstone.IdempotencyKey, out _)
                || !fingerprints.Add(tombstone.CreditFingerprint))
                return false;
        }
        return ledger.ActiveAttempt is null
               || !fingerprints.Contains(ledger.ActiveAttempt.CreditFingerprint);
    }

    internal static bool IsValid(ResetCreditProtectionAttemptJournal journal) =>
        journal.Version == 1
        && ResetCreditPrivacy.IsValidFingerprint(journal.AccountFingerprint)
        && ResetCreditPrivacy.IsValidFingerprint(journal.CreditFingerprint)
        && Guid.TryParse(journal.IdempotencyKey, out _)
        && journal.AvailableCountBefore >= 0
        && (journal.Phase == ResetCreditAttemptPhase.OutcomeConfirmed
            ? journal.ConfirmedOutcome is not null
            : journal.ConfirmedOutcome is null);
}

internal sealed class ExclusiveFileLease : IDisposable
{
    private FileStream? _stream;

    private ExclusiveFileLease(FileStream stream) => _stream = stream;

    public static ExclusiveFileLease? Acquire(string path, bool blocking)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var attempts = blocking ? 100 : 1;
        for (var attempt = 0; attempt < attempts; attempt++)
        {
            try
            {
                return new ExclusiveFileLease(new FileStream(
                    path,
                    FileMode.OpenOrCreate,
                    FileAccess.ReadWrite,
                    FileShare.None,
                    1,
                    FileOptions.WriteThrough));
            }
            catch (IOException) when (attempt + 1 < attempts)
            {
                Thread.Sleep(20);
            }
            catch (IOException)
            {
                return null;
            }
            catch (UnauthorizedAccessException)
            {
                return null;
            }
        }
        return null;
    }

    public void Dispose()
    {
        Interlocked.Exchange(ref _stream, null)?.Dispose();
        GC.SuppressFinalize(this);
    }
}
