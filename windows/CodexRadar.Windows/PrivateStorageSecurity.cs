using System.Security.AccessControl;
using System.Security.Principal;

namespace CodexRadar.Windows;

internal static class PrivateStorageSecurity
{
    public static void EnsureDirectory(string path)
    {
        Directory.CreateDirectory(path);
        var identity = CurrentIdentity();
        var security = new DirectorySecurity();
        security.SetOwner(identity);
        security.SetAccessRuleProtection(
            isProtected: true,
            preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(
            identity,
            FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit
            | InheritanceFlags.ObjectInherit,
            PropagationFlags.None,
            AccessControlType.Allow));
        new DirectoryInfo(path).SetAccessControl(security);
    }

    public static void EnsureFile(string path)
    {
        var identity = CurrentIdentity();
        var security = new FileSecurity();
        security.SetOwner(identity);
        security.SetAccessRuleProtection(
            isProtected: true,
            preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(
            identity,
            FileSystemRights.FullControl,
            AccessControlType.Allow));
        new FileInfo(path).SetAccessControl(security);
    }

    internal static bool IsRestrictedToCurrentUser(string path)
    {
        var identity = CurrentIdentity();
        var security = File.GetAttributes(path)
                       .HasFlag(FileAttributes.Directory)
            ? (FileSystemSecurity)new DirectoryInfo(path)
                .GetAccessControl()
            : new FileInfo(path).GetAccessControl();
        var rules = security.GetAccessRules(
                includeExplicit: true,
                includeInherited: true,
                targetType: typeof(SecurityIdentifier))
            .OfType<FileSystemAccessRule>()
            .Where(rule =>
                rule.AccessControlType
                == AccessControlType.Allow)
            .ToArray();
        return rules.Length > 0
               && rules.All(rule =>
                   Equals(rule.IdentityReference, identity));
    }

    private static SecurityIdentifier CurrentIdentity() =>
        WindowsIdentity.GetCurrent().User
        ?? throw new IOException(
            "The current Windows user identity is unavailable.");
}
