namespace CodexRadar.Windows;

internal static class TaskbarStatusVisualSmoke
{
    public static void Run(string? outputPath = null)
    {
        ApplicationConfiguration.Initialize();
        using var form = new TaskbarStatusForm();
        using var menu = new ContextMenuStrip();
        menu.Items.Add("Open Codex Radar");
        menu.Items.Add("Exit");
        form.SetStatusContextMenu(menu);
        form.SetStatus(
            "74%/88%/112",
            HealthLevel.Good,
            new AppSettings
            {
                Chinese = false,
                StatusDisplayMode = StatusDisplayMode.TaskbarText,
                SelectedStatusMetrics =
                [
                    StatusMetric.WeeklyQuota,
                    StatusMetric.ShortQuota,
                    StatusMetric.CodexIq
                ]
            });

        try
        {
            form.SetDisplayEnabledForVisualTest();
            var deadline = Environment.TickCount64 + 3_000;
            do
            {
                Application.DoEvents();
                if (form.PlacementAvailable) break;
                Thread.Sleep(50);
            } while (Environment.TickCount64 < deadline);

            Validate(form, menu);
            if (outputPath is not null)
                Capture(form, outputPath);
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException(
                "Taskbar status visual smoke test failed.",
                ex);
        }
        finally
        {
            form.SetDisplayEnabled(false);
            form.Close();
            Application.DoEvents();
        }
    }

    private static void Validate(
        TaskbarStatusForm form,
        ContextMenuStrip menu)
    {
        if (!form.PlacementAvailable
            || !form.Visible
            || form.Width < 58
            || form.Height < 18)
            throw new InvalidOperationException(
                "The taskbar status surface could not be placed. "
                + (form.PlacementUnavailableReason
                   ?? "No placement reason was reported."));
        if (!TaskbarStatusForm.TryGetTaskbarGeometry(
                out var taskbar,
                out var notificationArea))
            throw new InvalidOperationException(
                "Explorer taskbar geometry is unavailable.");
        if (!taskbar.IntersectsWith(form.Bounds))
            throw new InvalidOperationException(
                "The status surface is not inside the taskbar.");
        if (taskbar.Width >= taskbar.Height
            && notificationArea is Rectangle tray
            && form.Right > tray.Left)
            throw new InvalidOperationException(
                "The status surface overlaps the notification area.");
        if (!menu.Items.OfType<ToolStripItem>()
                .Any(item => item.Text == "Exit"))
            throw new InvalidOperationException(
                "The taskbar context menu has no Exit action.");

        using var bitmap = new Bitmap(form.Width, form.Height);
        form.DrawToBitmap(
            bitmap,
            new Rectangle(Point.Empty, form.Size));
        var colors = new HashSet<int>();
        for (var y = 0; y < bitmap.Height; y += 3)
        for (var x = 0; x < bitmap.Width; x += 3)
            colors.Add(bitmap.GetPixel(x, y).ToArgb());
        if (colors.Count < 4)
            throw new InvalidOperationException(
                "The taskbar status surface rendered blank.");
    }

    private static void Capture(
        TaskbarStatusForm form,
        string outputPath)
    {
        if (!TaskbarStatusForm.TryGetTaskbarGeometry(
                out var taskbar,
                out _))
            throw new InvalidOperationException(
                "Explorer taskbar geometry is unavailable.");
        var screen = Screen.FromRectangle(form.Bounds).Bounds;
        var capture = Rectangle.Intersect(
            Rectangle.FromLTRB(
                Math.Max(screen.Left, form.Left - 16),
                Math.Max(screen.Top, taskbar.Top - 8),
                screen.Right,
                Math.Min(screen.Bottom, taskbar.Bottom + 8)),
            screen);
        if (capture.Width <= 0 || capture.Height <= 0)
            throw new InvalidOperationException(
                "The taskbar preview bounds are invalid.");

        var directory = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrWhiteSpace(directory))
            Directory.CreateDirectory(directory);
        using var bitmap = new Bitmap(capture.Width, capture.Height);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(
                capture.Location,
                Point.Empty,
                capture.Size,
                CopyPixelOperation.SourceCopy);
        }
        if (HasVisualVariation(bitmap))
        {
            bitmap.Save(
                outputPath,
                System.Drawing.Imaging.ImageFormat.Png);
            return;
        }

        // Remote, locked, or capture-restricted desktops can return a uniform
        // black frame from CopyFromScreen. Preserve useful visual evidence of
        // the real status window while geometry validation above continues to
        // prove its placement relative to Explorer.
        using var fallback = new Bitmap(form.Width, form.Height);
        form.DrawToBitmap(
            fallback,
            new Rectangle(Point.Empty, form.Size));
        fallback.Save(
            outputPath,
            System.Drawing.Imaging.ImageFormat.Png);
    }

    private static bool HasVisualVariation(Bitmap bitmap)
    {
        var first = bitmap.GetPixel(0, 0).ToArgb();
        for (var y = 0; y < bitmap.Height; y += 3)
        for (var x = 0; x < bitmap.Width; x += 3)
            if (bitmap.GetPixel(x, y).ToArgb() != first)
                return true;
        return false;
    }
}
