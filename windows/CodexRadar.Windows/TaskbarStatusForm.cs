using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace CodexRadar.Windows;

/// <summary>
/// A safe, no-activate status surface positioned next to Explorer's notification
/// area. It deliberately remains a normal top-level window: no Explorer process
/// injection, undocumented taskbar parenting, or shell memory modification.
/// </summary>
internal sealed class TaskbarStatusForm : Form
{
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private static readonly IntPtr HwndTopmost = new(-1);

    private readonly System.Windows.Forms.Timer _positionTimer = new() { Interval = 1_000 };
    private readonly ToolTip _toolTip = new() { InitialDelay = 350, ReshowDelay = 100, AutoPopDelay = 8_000 };
    private string _statusText = "--/--/-";
    private HealthLevel _health = HealthLevel.Unknown;
    private StatusBarHorizontalPadding _padding = StatusBarHorizontalPadding.System;
    private StatusBarFontScale _fontScale = StatusBarFontScale.Normal;
    private ContextMenuStrip? _statusContextMenu;
    private uint _targetDpi = 96;
    private bool _displayEnabled;
    private bool _lightTheme = true;
    private bool _placementAvailable;
    private string? _placementUnavailableReason;
    private bool _ignoreFullscreenForegroundForTesting;
    private int _themeProbeTicks;

    public event EventHandler? LeftClick;
    public event EventHandler? PlacementAvailabilityChanged;

    public bool PlacementAvailable => _placementAvailable;
    internal string? PlacementUnavailableReason => _placementUnavailableReason;

    public TaskbarStatusForm()
    {
        AutoScaleMode = AutoScaleMode.None;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        Text = "Codex Radar Sentinel · Taskbar status";
        DoubleBuffered = true;
        Cursor = Cursors.Hand;
        AccessibleName = "Codex Radar Sentinel";
        AccessibleDescription = "Codex quota and radar status";
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint
                 | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw
                 | ControlStyles.Opaque, true);

        _lightTheme = ReadLightTheme();
        _positionTimer.Tick += (_, _) =>
        {
            if (++_themeProbeTicks >= 10)
            {
                _themeProbeTicks = 0;
                var nextTheme = ReadLightTheme();
                if (nextTheme != _lightTheme)
                {
                    _lightTheme = nextTheme;
                    Invalidate();
                }
            }
            Reposition();
        };
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= WsExToolWindow | WsExNoActivate;
            return parameters;
        }
    }

    public void SetDisplayEnabled(bool enabled)
    {
        if (_displayEnabled == enabled)
        {
            if (enabled) Reposition();
            return;
        }

        _displayEnabled = enabled;
        if (enabled)
        {
            _positionTimer.Start();
            Reposition();
        }
        else
        {
            _positionTimer.Stop();
            _placementUnavailableReason = "The taskbar status display is disabled.";
            SetPlacementAvailable(false);
            Hide();
        }
    }

    internal void SetDisplayEnabledForVisualTest()
    {
        _ignoreFullscreenForegroundForTesting = true;
        SetDisplayEnabled(true);
    }

    public void SetStatus(string statusText, HealthLevel health, AppSettings settings)
    {
        var normalized = string.IsNullOrWhiteSpace(statusText) ? "--/--/-" : statusText.Trim();
        var changed = !string.Equals(_statusText, normalized, StringComparison.Ordinal)
                      || _health != health
                      || _padding != settings.HorizontalPadding
                      || _fontScale != settings.FontScale;
        _statusText = normalized;
        _health = health;
        _padding = settings.HorizontalPadding;
        _fontScale = settings.FontScale;
        AccessibleDescription = $"Codex Radar Sentinel · {_statusText}";
        _toolTip.SetToolTip(this, $"Codex Radar Sentinel · {_statusText}");
        if (!changed) return;
        Invalidate();
        if (_displayEnabled) Reposition();
    }

    public void SetStatusContextMenu(ContextMenuStrip? menu) => _statusContextMenu = menu;

    private void Reposition()
    {
        if (!_displayEnabled || IsDisposed || Disposing) return;

        var taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero || !IsWindow(taskbar) || !IsWindowVisible(taskbar)
            || !TryGetRectangle(taskbar, out var taskbarBounds))
        {
            _placementUnavailableReason = "Explorer's primary taskbar window is unavailable.";
            SetPlacementAvailable(false);
            Hide();
            return;
        }

        var screen = Screen.FromHandle(taskbar);
        var visibleTaskbar = Rectangle.Intersect(taskbarBounds, screen.Bounds);
        var horizontal = taskbarBounds.Width >= taskbarBounds.Height;
        var minimumThickness = Scale(12, SafeDpi(taskbar));
        if ((horizontal ? visibleTaskbar.Height : visibleTaskbar.Width) < minimumThickness)
        {
            _placementUnavailableReason =
                "The taskbar is hidden or its visible edge is too small.";
            SetPlacementAvailable(false);
            Hide();
            return;
        }
        if (!_ignoreFullscreenForegroundForTesting
            && IsFullscreenForeground(screen.Bounds, taskbar))
        {
            _placementUnavailableReason =
                "A foreground window is covering the taskbar in full-screen mode.";
            SetPlacementAvailable(false);
            Hide();
            return;
        }

        _targetDpi = SafeDpi(taskbar);
        var trayHandle = FindTrayNotifyWindow(taskbar);
        Rectangle? trayBounds = trayHandle != IntPtr.Zero && TryGetRectangle(trayHandle, out var tray)
            ? tray
            : null;
        var desired = MeasureDesiredSize(taskbarBounds);
        var gap = Scale(4, _targetDpi);
        var target = horizontal
            ? CalculateHorizontalBounds(taskbarBounds, trayBounds, desired, gap)
            : CalculateVerticalTaskbarBounds(taskbarBounds, trayBounds, screen.Bounds, desired, gap);

        if (target.Width < Scale(42, _targetDpi) || target.Height < Scale(18, _targetDpi))
        {
            _placementUnavailableReason =
                "The taskbar has no safe space for the status surface.";
            SetPlacementAvailable(false);
            Hide();
            return;
        }

        if (Bounds != target) Bounds = target;
        if (!Visible) Show();
        if (!SetWindowPos(Handle, HwndTopmost, target.X, target.Y, target.Width, target.Height,
                SwpNoActivate | SwpShowWindow))
        {
            _placementUnavailableReason =
                $"SetWindowPos failed with Win32 error {Marshal.GetLastWin32Error()}.";
            SetPlacementAvailable(false);
            Hide();
            return;
        }
        _placementUnavailableReason = null;
        SetPlacementAvailable(true);
    }

    internal static Rectangle CalculateHorizontalBounds(
        Rectangle taskbar,
        Rectangle? notificationArea,
        Size desired,
        int gap)
    {
        gap = Math.Max(0, gap);
        var height = Math.Min(desired.Height, Math.Max(1, taskbar.Height - gap));
        var width = Math.Min(desired.Width, Math.Max(1, taskbar.Width - gap * 2));
        var validNotificationArea = notificationArea is { } area
                                    && area.Left > taskbar.Left
                                    && Rectangle.Intersect(taskbar, area).Width > 0;
        var rightEdge = validNotificationArea ? notificationArea!.Value.Left - gap : taskbar.Right - gap;
        var x = Math.Max(taskbar.Left + gap, rightEdge - width);
        var y = taskbar.Top + Math.Max(0, (taskbar.Height - height) / 2);
        return new Rectangle(x, y, Math.Min(width, Math.Max(1, taskbar.Right - x)), height);
    }

    internal static bool TryGetTaskbarGeometry(
        out Rectangle taskbarBounds,
        out Rectangle? notificationArea)
    {
        var taskbar = FindWindow("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero
            || !IsWindow(taskbar)
            || !IsWindowVisible(taskbar)
            || !TryGetRectangle(taskbar, out taskbarBounds))
        {
            taskbarBounds = Rectangle.Empty;
            notificationArea = null;
            return false;
        }
        var trayHandle = FindTrayNotifyWindow(taskbar);
        notificationArea =
            trayHandle != IntPtr.Zero
            && TryGetRectangle(trayHandle, out var trayBounds)
                ? trayBounds
                : null;
        return true;
    }

    private static Rectangle CalculateVerticalTaskbarBounds(
        Rectangle taskbar,
        Rectangle? notificationArea,
        Rectangle screen,
        Size desired,
        int gap)
    {
        // Windows 10 still permits a vertical taskbar. Keep the text readable by
        // placing it immediately beside the tray end instead of clipping it into
        // the narrow vertical strip. Windows 11's supported taskbar is horizontal.
        var onLeft = taskbar.Left <= screen.Left + gap;
        var x = onLeft ? taskbar.Right + gap : taskbar.Left - desired.Width - gap;
        x = Math.Clamp(x, screen.Left, Math.Max(screen.Left, screen.Right - desired.Width));
        var trayTop = notificationArea is { } area && Rectangle.Intersect(taskbar, area).Height > 0
            ? area.Top
            : taskbar.Bottom;
        var y = Math.Clamp(trayTop - desired.Height - gap, screen.Top,
            Math.Max(screen.Top, screen.Bottom - desired.Height));
        return new Rectangle(x, y, desired.Width, desired.Height);
    }

    private Size MeasureDesiredSize(Rectangle taskbar)
    {
        using var font = CreateStatusFont();
        var flags = TextFormatFlags.SingleLine | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding;
        var measured = TextRenderer.MeasureText(_statusText, font, Size.Empty, flags);
        var horizontalPadding = _padding switch
        {
            StatusBarHorizontalPadding.Compact => Scale(7, _targetDpi),
            StatusBarHorizontalPadding.Tight => Scale(5, _targetDpi),
            _ => Scale(10, _targetDpi)
        };
        var accentSpace = Scale(8, _targetDpi);
        var width = measured.Width + horizontalPadding * 2 + accentSpace;
        var height = Math.Max(measured.Height + Scale(7, _targetDpi), Scale(26, _targetDpi));
        if (taskbar.Width >= taskbar.Height)
        {
            height = Math.Min(height, Math.Max(1, taskbar.Height - Scale(4, _targetDpi)));
            width = Math.Min(width, Math.Max(1, taskbar.Width / 2));
        }
        return new Size(Math.Max(Scale(58, _targetDpi), width), height);
    }

    private Font CreateStatusFont()
    {
        var pixels = _fontScale switch
        {
            StatusBarFontScale.Compact => 12f,
            StatusBarFontScale.Tiny => 11f,
            _ => 13f
        };
        return new Font("Segoe UI Semibold", pixels * _targetDpi / 96f, FontStyle.Bold, GraphicsUnit.Pixel);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var colors = StatusColors();
        e.Graphics.Clear(colors.Background);
        if (ClientSize.Width < 2 || ClientSize.Height < 2) return;

        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var bounds = new Rectangle(0, 0, Width - 1, Height - 1);
        using var path = RoundedPath(bounds, Math.Min(Scale(8, _targetDpi), Height / 2));
        using var background = new SolidBrush(colors.Background);
        using var border = new Pen(colors.Border);
        e.Graphics.FillPath(background, path);
        e.Graphics.DrawPath(border, path);

        var accent = HealthColor();
        var dotSize = Math.Max(3, Scale(4, _targetDpi));
        var dotX = Scale(7, _targetDpi);
        var dotY = Math.Max(1, (Height - dotSize) / 2);
        using var dot = new SolidBrush(accent);
        e.Graphics.FillEllipse(dot, dotX, dotY, dotSize, dotSize);

        using var font = CreateStatusFont();
        var textLeft = dotX + dotSize + Scale(3, _targetDpi);
        var textRightPadding = Scale(6, _targetDpi);
        var textBounds = Rectangle.FromLTRB(textLeft, 0, Math.Max(textLeft + 1, Width - textRightPadding), Height);
        TextRenderer.DrawText(e.Graphics, _statusText, font, textBounds, colors.Foreground,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine
            | TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (Width < 2 || Height < 2) return;
        using var path = RoundedPath(new Rectangle(0, 0, Width, Height), Math.Min(Scale(8, _targetDpi), Height / 2));
        var previous = Region;
        Region = new Region(path);
        previous?.Dispose();
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (e.Button == MouseButtons.Left)
        {
            LeftClick?.Invoke(this, EventArgs.Empty);
        }
        else if (e.Button == MouseButtons.Right && _statusContextMenu is { IsDisposed: false } menu)
        {
            menu.Show(Cursor.Position);
        }
    }

    private (Color Background, Color Foreground, Color Border) StatusColors()
    {
        if (SystemInformation.HighContrast)
            return (SystemColors.Window, SystemColors.WindowText, SystemColors.WindowFrame);
        return _lightTheme
            ? (Color.FromArgb(248, 248, 248), Color.FromArgb(32, 32, 32), Color.FromArgb(196, 196, 196))
            : (Color.FromArgb(38, 38, 38), Color.FromArgb(245, 245, 245), Color.FromArgb(82, 82, 82));
    }

    private Color HealthColor() => _health switch
    {
        HealthLevel.Good => Color.FromArgb(16, 124, 65),
        HealthLevel.Warning => Color.FromArgb(232, 140, 0),
        HealthLevel.Critical => Color.FromArgb(196, 43, 28),
        _ => Color.FromArgb(115, 115, 115)
    };

    private static GraphicsPath RoundedPath(Rectangle bounds, int radius)
    {
        var path = new GraphicsPath();
        var diameter = Math.Max(1, Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height)));
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

    private void SetPlacementAvailable(bool value)
    {
        if (_placementAvailable == value) return;
        _placementAvailable = value;
        PlacementAvailabilityChanged?.Invoke(this, EventArgs.Empty);
    }

    private static IntPtr FindTrayNotifyWindow(IntPtr taskbar)
    {
        var direct = FindWindowEx(taskbar, IntPtr.Zero, "TrayNotifyWnd", null);
        if (direct != IntPtr.Zero) return direct;

        var result = IntPtr.Zero;
        EnumChildWindows(taskbar, (window, _) =>
        {
            var name = new StringBuilder(64);
            _ = GetClassName(window, name, name.Capacity);
            if (!string.Equals(name.ToString(), "TrayNotifyWnd", StringComparison.Ordinal)) return true;
            result = window;
            return false;
        }, IntPtr.Zero);
        return result;
    }

    private bool IsFullscreenForeground(Rectangle screen, IntPtr taskbar)
    {
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero || foreground == taskbar || foreground == Handle) return false;
        var className = new StringBuilder(64);
        _ = GetClassName(foreground, className, className.Capacity);
        if (className.ToString() is "Progman" or "WorkerW" or "Shell_TrayWnd") return false;
        if (!TryGetRectangle(foreground, out var bounds)) return false;
        const int tolerance = 2;
        return bounds.Left <= screen.Left + tolerance && bounds.Top <= screen.Top + tolerance
               && bounds.Right >= screen.Right - tolerance && bounds.Bottom >= screen.Bottom - tolerance;
    }

    private static bool TryGetRectangle(IntPtr window, out Rectangle rectangle)
    {
        if (GetWindowRect(window, out var native))
        {
            rectangle = Rectangle.FromLTRB(native.Left, native.Top, native.Right, native.Bottom);
            return rectangle.Width > 0 && rectangle.Height > 0;
        }
        rectangle = Rectangle.Empty;
        return false;
    }

    private static uint SafeDpi(IntPtr window)
    {
        try
        {
            var dpi = GetDpiForWindow(window);
            return dpi is >= 96 and <= 768 ? dpi : 96;
        }
        catch (EntryPointNotFoundException)
        {
            return 96;
        }
    }

    private static int Scale(int value, uint dpi) => Math.Max(1,
        (int)Math.Round(value * dpi / 96d, MidpointRounding.AwayFromZero));

    private static bool ReadLightTheme()
    {
        if (SystemInformation.HighContrast) return true;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is not int value || value != 0;
        }
        catch
        {
            return true;
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _positionTimer.Stop();
            _positionTimer.Dispose();
            _toolTip.Dispose();
            Region?.Dispose();
        }
        base.Dispose(disposing);
    }

    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindow(string className, string? windowName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string className, string? windowName);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder className, int maximumCount);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr window, out NativeRect rectangle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
