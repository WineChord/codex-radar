using System.Security.Cryptography;
using System.Text;

namespace CodexRadar.Windows;

internal static class ResetCreditPrivacy
{
    public static string Fingerprint(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    public static bool IsValidFingerprint(string? value) =>
        value is { Length: 64 }
        && value.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');

    public static string DisplayFingerprint(string? value) =>
        IsValidFingerprint(value) ? value![..8] : "--------";

    public static ResetCredit NormalizeCachedCredit(ResetCredit credit)
    {
        if (IsValidFingerprint(credit.Fingerprint)) return credit;
        var seed = string.Join('\0',
            "codex-radar-legacy-cache-v1",
            credit.Title ?? "",
            credit.Status ?? "",
            credit.ResetType ?? "",
            credit.GrantedAt?.ToUniversalTime().ToString("O") ?? "",
            credit.ExpiresAt?.ToUniversalTime().ToString("O") ?? "",
            credit.RedeemStartedAt?.ToUniversalTime().ToString("O") ?? "",
            credit.RedeemedAt?.ToUniversalTime().ToString("O") ?? "");
        return credit with { Fingerprint = Fingerprint(seed) };
    }
}
