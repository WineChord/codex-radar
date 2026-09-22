using System.Security.AccessControl;
using System.Security.Principal;
using System.Runtime.InteropServices;

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
        // Never follow a redirected control directory. The owner-only parent is
        // the trust boundary: another user cannot create or replace its socket.
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) return false;
        FileSystemSecurity security = Directory.Exists(path)
            ? new DirectoryInfo(path).GetAccessControl(AccessControlSections.Owner | AccessControlSections.Access)
            : new FileInfo(path).GetAccessControl(AccessControlSections.Owner | AccessControlSections.Access);
        if (!Equals(
                security.GetOwner(typeof(SecurityIdentifier)),
                identity))
            return false;
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

    internal static bool IsUnixDomainSocket(string path)
    {
        // AF_UNIX is an NTFS reparse tag, not a symbolic link or ordinary file.
        // Enumerating its metadata works on Windows versions that reject opening
        // the socket with CreateFile/GetFileSecurity (ERROR_CANT_ACCESS_FILE).
        var handle = FindFirstFileW(path, out var data);
        if (handle == new IntPtr(-1)) return false;
        try { return (data.Attributes & 0x400) != 0 && data.ReparseTag == 0x80000023; }
        finally { _ = FindClose(handle); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct FindData
    {
        public uint Attributes;
        public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime, AccessTime, WriteTime;
        public uint SizeHigh, SizeLow, ReparseTag, Reserved;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string FileName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string AlternateFileName;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern IntPtr FindFirstFileW(string path, out FindData data);

    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FindClose(IntPtr handle);
}
