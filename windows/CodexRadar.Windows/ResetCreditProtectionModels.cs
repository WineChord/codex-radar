using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexRadar.Windows;

internal sealed record CodexAccountIdentity(
    string Type,
    string? Email,
    string? PlanType,
    bool RequiresOpenAiAuth)
{
    public string? ProtectionIdentitySeed =>
        Type.Equals("chatgpt", StringComparison.Ordinal)
        && !string.IsNullOrWhiteSpace(Email)
            ? $"chatgpt:{Email.Trim().ToLowerInvariant()}"
            : null;

    public static CodexAccountIdentity Parse(JsonElement root)
    {
        var account = root.Object("account");
        return new CodexAccountIdentity(
            account?.String("type") ?? "",
            account?.String("email"),
            account?.String("planType", "plan_type"),
            root.Bool("requiresOpenaiAuth", "requires_openai_auth") ?? false);
    }
}

internal sealed record ProtectionRateLimitResponse(
    RateLimitResetCreditsSummary? ResetCredits)
{
    public static ProtectionRateLimitResponse Parse(JsonElement root)
    {
        var summary = root.Object("rateLimitResetCredits", "rate_limit_reset_credits");
        if (summary is null)
            return new ProtectionRateLimitResponse(
                (RateLimitResetCreditsSummary?)null);
        var availableCount = summary.Value.Int32("availableCount", "available_count")
                             ?? throw new JsonException("Reset-credit summary has no available count.");
        IReadOnlyList<RateLimitResetCredit>? credits = null;
        if (summary.Value.TryGetProperty("credits", out var items))
        {
            if (items.ValueKind == JsonValueKind.Array)
                credits = items.EnumerateArray().Select(RateLimitResetCredit.Parse).ToArray();
            else if (items.ValueKind != JsonValueKind.Null)
                throw new JsonException("Reset-credit details must be an array or null.");
        }
        return new ProtectionRateLimitResponse(
            new RateLimitResetCreditsSummary(availableCount, credits));
    }
}

internal sealed record RateLimitResetCreditsSummary(
    int AvailableCount,
    IReadOnlyList<RateLimitResetCredit>? Credits);

internal sealed record RateLimitResetCredit(
    string Id,
    string ResetType,
    string Status,
    long GrantedAt,
    long? ExpiresAt,
    string? Title,
    string? Description)
{
    public DateTimeOffset GrantedAtDate => DateTimeOffset.FromUnixTimeSeconds(GrantedAt);
    public DateTimeOffset? ExpiresAtDate =>
        ExpiresAt is long value ? DateTimeOffset.FromUnixTimeSeconds(value) : null;
    public bool IsAvailable => Status == "available";
    public bool IsSupportedCodexReset => ResetType == "codexRateLimits";

    public static RateLimitResetCredit Parse(JsonElement item) => new(
        item.String("id") ?? throw new JsonException("Reset credit has no ID."),
        item.String("resetType", "reset_type")
        ?? throw new JsonException("Reset credit has no reset type."),
        item.String("status") ?? throw new JsonException("Reset credit has no status."),
        item.Int64("grantedAt", "granted_at")
        ?? throw new JsonException("Reset credit has no granted time."),
        item.Int64("expiresAt", "expires_at"),
        item.String("title"),
        item.String("description"));
}

[JsonConverter(typeof(JsonStringEnumConverter))]
internal enum ResetCreditConsumeOutcome
{
    Reset,
    AlreadyRedeemed,
    NothingToReset,
    NoCredit
}

internal sealed class ResetCreditAuthorizationException(string message) :
    InvalidOperationException(message);

internal sealed class ResetCreditPreDispatchException(
    string message,
    Exception? inner = null) : InvalidOperationException(message, inner);

internal sealed record ResetCreditProtectionClockSample(
    DateTimeOffset WallTime,
    double ContinuousTimeSeconds)
{
    public static ResetCreditProtectionClockSample Now(
        DateTimeOffset? wallTime = null) => new(
        wallTime ?? DateTimeOffset.UtcNow,
        Environment.TickCount64 / 1000d);
}

internal sealed record ResetCreditProtectionTarget(
    string CreditId,
    string CreditFingerprint,
    DateTimeOffset ExpiresAt,
    DateTimeOffset ActionAt,
    int AvailableCount);

internal enum ResetCreditProtectionDecisionKind
{
    NoCredits,
    DetailsUnavailable,
    DetailsIncomplete,
    NoSupportedExpiringCredits,
    Scheduled,
    Ready
}

internal sealed record ResetCreditProtectionDecision(
    ResetCreditProtectionDecisionKind Kind,
    int AvailableCount = 0,
    int AvailableDetails = 0,
    ResetCreditProtectionTarget? Target = null);

internal static class ResetCreditExpiryProtectionPolicy
{
    public static readonly TimeSpan LeadTime = TimeSpan.FromMinutes(30);

    public static ResetCreditProtectionDecision Decide(
        RateLimitResetCreditsSummary summary,
        DateTimeOffset? now = null,
        IReadOnlySet<string>? excludingCreditFingerprints = null)
    {
        var current = now ?? DateTimeOffset.UtcNow;
        var availableCount = Math.Max(0, summary.AvailableCount);
        if (availableCount == 0)
            return new ResetCreditProtectionDecision(
                ResetCreditProtectionDecisionKind.NoCredits);
        if (summary.Credits is null)
            return new ResetCreditProtectionDecision(
                ResetCreditProtectionDecisionKind.DetailsUnavailable,
                availableCount);

        var available = summary.Credits.Where(credit => credit.IsAvailable).ToArray();
        var uniqueIds = available.Select(credit => credit.Id)
            .ToHashSet(StringComparer.Ordinal);
        if (available.Length != availableCount
            || available.Any(credit => string.IsNullOrEmpty(credit.Id))
            || uniqueIds.Count != availableCount)
            return new ResetCreditProtectionDecision(
                ResetCreditProtectionDecisionKind.DetailsIncomplete,
                availableCount,
                uniqueIds.Count);

        var excluded = excludingCreditFingerprints ?? new HashSet<string>();
        var selected = available
            .Select(credit => (Credit: credit, Expiry: credit.ExpiresAtDate))
            .Where(item => item.Credit.IsSupportedCodexReset
                           && item.Expiry is DateTimeOffset expiry
                           && expiry > current
                           && !excluded.Contains(
                               ResetCreditPrivacy.Fingerprint(item.Credit.Id)))
            .OrderBy(item => item.Expiry)
            .ThenBy(item => item.Credit.Id, StringComparer.Ordinal)
            .FirstOrDefault();
        if (selected.Credit is null || selected.Expiry is not DateTimeOffset expiresAt)
            return new ResetCreditProtectionDecision(
                ResetCreditProtectionDecisionKind.NoSupportedExpiringCredits,
                availableCount);

        var target = new ResetCreditProtectionTarget(
            selected.Credit.Id,
            ResetCreditPrivacy.Fingerprint(selected.Credit.Id),
            expiresAt,
            expiresAt - LeadTime,
            availableCount);
        return new ResetCreditProtectionDecision(
            current >= target.ActionAt
                ? ResetCreditProtectionDecisionKind.Ready
                : ResetCreditProtectionDecisionKind.Scheduled,
            availableCount,
            Target: target);
    }
}

internal sealed record ResetCreditProtectionConsent(
    int Version,
    string AccountFingerprint,
    string AuthorizationId,
    DateTimeOffset GrantedAt,
    HashSet<string> AuthorizedCreditFingerprints,
    ResetCreditProtectionClockSample ClockAnchor);

internal enum ClockDiscontinuityReason
{
    WallClockOffset,
    ContinuousClockReset,
    InvalidSample
}

internal static class ResetCreditProtectionAuthorization
{
    public const int ConsentVersion = 2;
    public const double ClockToleranceSeconds = 5;

    public static bool IsStructurallyValid(ResetCreditProtectionConsent? consent) =>
        consent is
        {
            Version: ConsentVersion,
            AccountFingerprint.Length: > 0,
            AuthorizedCreditFingerprints.Count: > 0
        }
        && Guid.TryParse(consent.AuthorizationId, out _)
        && ResetCreditPrivacy.IsValidFingerprint(consent.AccountFingerprint)
        && consent.AuthorizedCreditFingerprints.All(ResetCreditPrivacy.IsValidFingerprint)
        && double.IsFinite(consent.ClockAnchor.ContinuousTimeSeconds)
        && consent.ClockAnchor.ContinuousTimeSeconds >= 0;

    public static ClockDiscontinuityReason? ClockDiscontinuity(
        ResetCreditProtectionConsent? consent,
        ResetCreditProtectionClockSample? current = null) =>
        consent is null || !IsStructurallyValid(consent)
            ? ClockDiscontinuityReason.InvalidSample
            : ClockDiscontinuity(consent.ClockAnchor, current ?? ResetCreditProtectionClockSample.Now());

    public static ClockDiscontinuityReason? ClockDiscontinuity(
        ResetCreditProtectionClockSample anchor,
        ResetCreditProtectionClockSample current)
    {
        if (!double.IsFinite(anchor.ContinuousTimeSeconds)
            || !double.IsFinite(current.ContinuousTimeSeconds)
            || anchor.ContinuousTimeSeconds < 0
            || current.ContinuousTimeSeconds < 0)
            return ClockDiscontinuityReason.InvalidSample;
        var continuousElapsed = current.ContinuousTimeSeconds - anchor.ContinuousTimeSeconds;
        if (continuousElapsed < 0) return ClockDiscontinuityReason.ContinuousClockReset;
        var wallElapsed = (current.WallTime - anchor.WallTime).TotalSeconds;
        return Math.Abs(wallElapsed - continuousElapsed) > ClockToleranceSeconds
            ? ClockDiscontinuityReason.WallClockOffset
            : null;
    }

    public static bool IsEnabled(
        bool requested,
        ResetCreditProtectionConsent? consent,
        ResetCreditProtectionClockSample? current = null) =>
        requested && IsStructurallyValid(consent)
                  && ClockDiscontinuity(consent, current) is null;

    public static bool Authorizes(
        bool requested,
        ResetCreditProtectionConsent? consent,
        string creditFingerprint) =>
        IsEnabled(requested, consent)
        && ResetCreditPrivacy.IsValidFingerprint(creditFingerprint)
        && consent!.AuthorizedCreditFingerprints.Contains(creditFingerprint);
}

[JsonConverter(typeof(JsonStringEnumConverter))]
internal enum ResetCreditAttemptPhase
{
    Sending,
    SentUnknown,
    OutcomeConfirmed
}

internal sealed record ResetCreditProtectionAttemptJournal(
    int Version,
    string AccountFingerprint,
    string CreditFingerprint,
    string IdempotencyKey,
    DateTimeOffset ExpiresAt,
    int AvailableCountBefore,
    ResetCreditAttemptPhase Phase,
    ResetCreditConsumeOutcome? ConfirmedOutcome,
    DateTimeOffset UpdatedAt);

[JsonConverter(typeof(JsonStringEnumConverter))]
internal enum ResetCreditTombstoneDisposition
{
    ConfirmedUsed,
    Ambiguous
}

internal sealed record ResetCreditProtectionTombstone(
    string AccountFingerprint,
    string CreditFingerprint,
    string IdempotencyKey,
    DateTimeOffset ExpiresAt,
    ResetCreditTombstoneDisposition Disposition,
    DateTimeOffset TerminalAt);

internal sealed record ResetCreditProtectionLedger
{
    public int Version { get; init; } = 1;
    public ResetCreditProtectionAttemptJournal? ActiveAttempt { get; set; }
    public List<ResetCreditProtectionTombstone> Tombstones { get; init; } = [];
    [JsonIgnore]
    public HashSet<string> ExcludedCreditFingerprints =>
        Tombstones.Select(item => item.CreditFingerprint).ToHashSet(StringComparer.Ordinal);
}

internal enum ResetCreditRecoveryDecisionKind
{
    ConfirmedUsed,
    ConfirmedNotConsumed,
    Reconciling,
    Missed,
    Retry
}

internal sealed record ResetCreditRecoveryDecision(
    ResetCreditRecoveryDecisionKind Kind,
    DateTimeOffset? ExpiresAt = null,
    ResetCreditProtectionTarget? Target = null);

internal enum ResetCreditProtectionBlockReason
{
    AccountIdentityUnavailable,
    AccountChanged,
    DetailsUnavailable,
    DetailsIncomplete,
    NoSupportedExpiringCredits,
    CodexUnavailable,
    SignedOut,
    UnsupportedCodex,
    AnotherProcess,
    JournalUnavailable,
    CreditNotAuthorized,
    ClockChanged,
    RequestFailed,
    PreviewMode
}

internal enum ResetCreditProtectionStatusKind
{
    Disabled,
    Enabling,
    Checking,
    NoCredits,
    Preview,
    PreviewNoCredits,
    Scheduled,
    WaitingForUsage,
    Using,
    Reconciling,
    Succeeded,
    Unavailable,
    Missed,
    Blocked
}

internal sealed record ResetCreditProtectionStatus(
    ResetCreditProtectionStatusKind Kind,
    DateTimeOffset? ActionAt = null,
    DateTimeOffset? ExpiresAt = null,
    DateTimeOffset? OccurredAt = null,
    int AvailableCount = 0,
    int AvailableDetails = 0,
    bool ReadyNow = false,
    ResetCreditProtectionBlockReason? BlockReason = null,
    string? Detail = null)
{
    public static readonly ResetCreditProtectionStatus Disabled =
        new(ResetCreditProtectionStatusKind.Disabled);

    public bool IsBusy => Kind is ResetCreditProtectionStatusKind.Enabling
        or ResetCreditProtectionStatusKind.Checking
        or ResetCreditProtectionStatusKind.Using
        or ResetCreditProtectionStatusKind.Reconciling;

    public bool NeedsAttention => Kind is ResetCreditProtectionStatusKind.Using
        or ResetCreditProtectionStatusKind.Reconciling
        or ResetCreditProtectionStatusKind.Missed
        or ResetCreditProtectionStatusKind.Blocked;
}

internal sealed record ResetCreditProtectionCacheUpdate(
    IReadOnlyList<ResetCredit> Credits,
    int Available,
    DateTimeOffset CheckedAt);

internal sealed record ResetCreditProtectionNotice(
    bool Success,
    string Identifier,
    DateTimeOffset? ExpiresAt = null);

internal enum ResetCreditProtectionAccountBindingFailure
{
    AccountChanged,
    AccountUnavailable
}

internal sealed class ResetCreditProtectionAccountBindingException(
    ResetCreditProtectionAccountBindingFailure failure) :
    InvalidOperationException(failure.ToString())
{
    public ResetCreditProtectionAccountBindingFailure Failure { get; } = failure;
}

internal static class ResetCreditProtectionRecoveryPolicy
{
    public static ResetCreditRecoveryDecision Decide(
        ResetCreditProtectionAttemptJournal journal,
        RateLimitResetCreditsSummary? summary,
        DateTimeOffset? now = null,
        bool protectionEnabled = false,
        DateTimeOffset? retryAt = null)
    {
        var current = now ?? DateTimeOffset.UtcNow;
        if (journal.Phase == ResetCreditAttemptPhase.OutcomeConfirmed)
        {
            if (journal.ConfirmedOutcome is ResetCreditConsumeOutcome.Reset
                or ResetCreditConsumeOutcome.AlreadyRedeemed)
                return new ResetCreditRecoveryDecision(
                    ResetCreditRecoveryDecisionKind.ConfirmedUsed);
            if (journal.ConfirmedOutcome is null)
                return new ResetCreditRecoveryDecision(
                    ResetCreditRecoveryDecisionKind.Reconciling);
        }
        if (summary?.Credits is null)
            return new ResetCreditRecoveryDecision(
                current >= journal.ExpiresAt
                    ? ResetCreditRecoveryDecisionKind.Missed
                    : ResetCreditRecoveryDecisionKind.Reconciling);

        var matching = summary.Credits.Where(credit =>
            ResetCreditPrivacy.Fingerprint(credit.Id) == journal.CreditFingerprint).ToArray();
        if (matching.Length == 1)
        {
            var credit = matching[0];
            switch (credit.Status)
            {
                case "redeemed":
                    return new ResetCreditRecoveryDecision(
                        ResetCreditRecoveryDecisionKind.ConfirmedUsed);
                case "redeeming":
                    return new ResetCreditRecoveryDecision(
                        current >= journal.ExpiresAt
                            ? ResetCreditRecoveryDecisionKind.Missed
                            : ResetCreditRecoveryDecisionKind.Reconciling);
                case "available":
                {
                    var availableIds = summary.Credits.Where(item => item.IsAvailable)
                        .Select(item => item.Id).ToArray();
                    var uniqueIds = availableIds.ToHashSet(StringComparer.Ordinal);
                    if (!credit.IsSupportedCodexReset
                        || credit.ExpiresAtDate is not DateTimeOffset expiresAt
                        || expiresAt <= current
                        || summary.AvailableCount <= 0
                        || availableIds.Any(string.IsNullOrEmpty)
                        || availableIds.Length != uniqueIds.Count
                        || uniqueIds.Count != summary.AvailableCount)
                        return new ResetCreditRecoveryDecision(
                            current >= journal.ExpiresAt
                                ? ResetCreditRecoveryDecisionKind.Missed
                                : ResetCreditRecoveryDecisionKind.Reconciling);
                    if (journal.Phase == ResetCreditAttemptPhase.OutcomeConfirmed
                        && journal.ConfirmedOutcome is ResetCreditConsumeOutcome.NothingToReset
                            or ResetCreditConsumeOutcome.NoCredit)
                        return new ResetCreditRecoveryDecision(
                            ResetCreditRecoveryDecisionKind.ConfirmedNotConsumed,
                            expiresAt);
                    if (!protectionEnabled || retryAt > current)
                        return new ResetCreditRecoveryDecision(
                            ResetCreditRecoveryDecisionKind.Reconciling);
                    var target = new ResetCreditProtectionTarget(
                        credit.Id,
                        journal.CreditFingerprint,
                        expiresAt,
                        expiresAt - ResetCreditExpiryProtectionPolicy.LeadTime,
                        summary.AvailableCount);
                    return current >= target.ActionAt
                        ? new ResetCreditRecoveryDecision(
                            ResetCreditRecoveryDecisionKind.Retry,
                            Target: target)
                        : new ResetCreditRecoveryDecision(
                            ResetCreditRecoveryDecisionKind.Reconciling);
                }
            }
        }
        return new ResetCreditRecoveryDecision(
            current >= journal.ExpiresAt
                ? ResetCreditRecoveryDecisionKind.Missed
                : ResetCreditRecoveryDecisionKind.Reconciling);
    }
}
