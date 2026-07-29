using System.Drawing.Drawing2D;
using System.Globalization;

namespace CodexRadar.Windows;

internal sealed class QuotaHistoryChartControl : Control
{
    private readonly QuotaHistoryTimeline _timeline;
    private readonly QuotaHistoryRange _range;
    private readonly DateTimeOffset _endingAt;
    private readonly bool _chinese;
    private readonly bool _storageUnavailable;
    private Rectangle _plotBounds;
    private Rectangle _dataBounds;
    private QuotaHistorySample? _selectedSample;
    private bool _dragging;

    public QuotaHistoryChartControl(
        QuotaHistoryTimeline timeline,
        QuotaHistoryRange range,
        DateTimeOffset endingAt,
        bool chinese,
        bool storageUnavailable)
    {
        _timeline = timeline;
        _range = range;
        _endingAt = endingAt;
        _chinese = chinese;
        _storageUnavailable = storageUnavailable;
        Name = "quotaHistoryChart";
        Height = 230;
        MinimumSize = new Size(260, 180);
        Dock = DockStyle.Top;
        Margin = new Padding(0, 4, 0, 5);
        TabStop = true;
        AccessibleRole = AccessibleRole.Chart;
        AccessibleName = T(
            "周额度剩余历史曲线",
            "Weekly quota remaining history chart");
        SetStyle(
            ControlStyles.UserPaint
            | ControlStyles.AllPaintingInWmPaint
            | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.ResizeRedraw
            | ControlStyles.SupportsTransparentBackColor,
            true);
        BackColor = Color.Transparent;
        UpdateAccessibleDescription();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.TextRenderingHint =
            System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

        var visible = _timeline.SamplesIn(_range, _endingAt);
        var top = 0;
        if (_storageUnavailable)
        {
            using var warningFont = new Font(
                Font,
                FontStyle.Bold);
            TextRenderer.DrawText(
                e.Graphics,
                T(
                    "⚠ 本地历史暂时无法安全读写",
                    "⚠ Local history is temporarily unavailable"),
                warningFont,
                new Rectangle(
                    0,
                    0,
                    Width,
                    Dpi(24)),
                Color.FromArgb(184, 98, 0),
                TextFormatFlags.Left
                | TextFormatFlags.VerticalCenter
                | TextFormatFlags.SingleLine
                | TextFormatFlags.EndEllipsis);
            top = Dpi(28);
        }

        if (visible.Count == 0)
        {
            DrawEmptyState(e.Graphics, top);
            _plotBounds = Rectangle.Empty;
            _dataBounds = Rectangle.Empty;
            return;
        }

        DrawSampleHeader(e.Graphics, visible, top);
        var headerHeight = Dpi(58);
        var axisLabelHeight = Dpi(20);
        var footerHeight = Dpi(25);
        _plotBounds = Rectangle.FromLTRB(
            Dpi(7),
            top + headerHeight,
            Math.Max(
                Dpi(8),
                Width - Dpi(42)),
            Math.Max(
                top + headerHeight + Dpi(80),
                Height
                - axisLabelHeight
                - footerHeight));
        var edgeInset = Math.Min(
            Dpi(7),
            Math.Max(Dpi(2), _plotBounds.Width / 20));
        _dataBounds = Rectangle.FromLTRB(
            _plotBounds.Left + edgeInset,
            _plotBounds.Top,
            Math.Max(
                _plotBounds.Left + edgeInset + 1,
                _plotBounds.Right - edgeInset),
            _plotBounds.Bottom);
        DrawChart(e.Graphics);
        DrawFooter(
            e.Graphics,
            Height - footerHeight + Dpi(2));
    }

    private void DrawEmptyState(Graphics graphics, int top)
    {
        var bounds = new Rectangle(
            0,
            top,
            Math.Max(1, Width - 1),
            Math.Max(Dpi(72), Height - top - 1));
        using var path = RoundedPath(
            bounds,
            Dpi(9));
        using var background =
            new SolidBrush(Color.FromArgb(245, 247, 250));
        graphics.FillPath(background, path);

        using var heading = new Font(
            "Segoe UI Semibold",
            Font.Size + .4f,
            FontStyle.Bold);
        TextRenderer.DrawText(
            graphics,
            T("开始记录中", "Recording starts now"),
            heading,
            new Rectangle(
                bounds.X + Dpi(10),
                bounds.Y + Dpi(9),
                bounds.Width - Dpi(20),
                Dpi(24)),
            Color.FromArgb(35, 40, 48),
            TextFormatFlags.Left
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(
            graphics,
            T(
                "读取到周额度后会留下第一个本机点；之后的变化、重置与数据断档会按实际观测显示。",
                "The first local point appears after weekly quota loads. Later changes, resets, and gaps are shown exactly as observed."),
            Font,
            new Rectangle(
                bounds.X + Dpi(10),
                bounds.Y + Dpi(37),
                bounds.Width - Dpi(20),
                bounds.Height - Dpi(46)),
            Color.FromArgb(96, 101, 110),
            TextFormatFlags.Left
            | TextFormatFlags.Top
            | TextFormatFlags.WordBreak);
    }

    private void DrawSampleHeader(
        Graphics graphics,
        IReadOnlyList<QuotaHistorySample> visible,
        int top)
    {
        var presented = _selectedSample ?? visible[^1];
        using var valueFont = new Font(
            "Segoe UI Semibold",
            Font.Size + 4.5f,
            FontStyle.Bold);
        TextRenderer.DrawText(
            graphics,
            $"{FormatNumber(presented.RemainingPercent)}%",
            valueFont,
            new Rectangle(
                0,
                top,
                Width / 2,
                Dpi(28)),
            Color.FromArgb(30, 94, 176),
            TextFormatFlags.Left
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(
            graphics,
            SampleTimestamp(presented.Timestamp),
            Font,
            new Rectangle(
                0,
                top + Dpi(26),
                Width / 2,
                Dpi(20)),
            Color.FromArgb(98, 103, 112),
            TextFormatFlags.Left
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine);

        if (_timeline.PreviousSample(presented) is not { } previous)
            return;
        var change =
            presented.RemainingPercent
            - previous.RemainingPercent;
        var changeColor = change > 0
            ? Color.FromArgb(16, 124, 65)
            : change < 0
                ? Color.FromArgb(184, 98, 0)
                : Color.FromArgb(98, 103, 112);
        using var changeFont = new Font(
            "Segoe UI Semibold",
            Font.Size + .3f,
            FontStyle.Bold);
        TextRenderer.DrawText(
            graphics,
            $"{(change > 0 ? "+" : "")}{FormatNumber(change)} pp",
            changeFont,
            new Rectangle(
                Width / 2,
                top,
                Math.Max(
                    1,
                    Width - Width / 2 - Dpi(42)),
                Dpi(24)),
            changeColor,
            TextFormatFlags.Right
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(
            graphics,
            _timeline.IsResetSample(presented)
                ? T("观察到重置", "Observed reset")
                : T("较上次记录", "vs previous sample"),
            Font,
            new Rectangle(
                Width / 2,
                top + Dpi(24),
                Math.Max(
                    1,
                    Width - Width / 2 - Dpi(42)),
                Dpi(20)),
            Color.FromArgb(98, 103, 112),
            TextFormatFlags.Right
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine);
    }

    private void DrawChart(Graphics graphics)
    {
        if (_plotBounds.Width <= 1
            || _plotBounds.Height <= 1)
            return;

        using var gridPen = new Pen(
            Color.FromArgb(225, 229, 235));
        foreach (var value in new[] { 0, 50, 100 })
        {
            var y = MapY(value);
            graphics.DrawLine(
                gridPen,
                _plotBounds.Left,
                y,
                _plotBounds.Right,
                y);
            TextRenderer.DrawText(
                graphics,
                $"{value}%",
                Font,
                new Rectangle(
                    _plotBounds.Right + Dpi(3),
                    y - Dpi(9),
                    Math.Max(
                        1,
                        Width
                        - _plotBounds.Right
                        - Dpi(3)),
                    Dpi(18)),
                Color.FromArgb(112, 117, 126),
                TextFormatFlags.Left
                | TextFormatFlags.VerticalCenter
                | TextFormatFlags.SingleLine);
        }

        using var axisPen = new Pen(
            Color.FromArgb(235, 238, 242));
        for (var index = 0; index < 5; index++)
        {
            var ratio = index / 4d;
            var x = _plotBounds.Left
                    + (int)Math.Round(
                        ratio * _plotBounds.Width);
            graphics.DrawLine(
                axisPen,
                x,
                _plotBounds.Top,
                x,
                _plotBounds.Bottom);
            var date = _endingAt - _range.Duration()
                       + TimeSpan.FromTicks(
                           (long)(
                               _range.Duration().Ticks
                               * ratio));
            var label = AxisTimestamp(date);
            var labelWidth = Math.Min(
                Dpi(70),
                Math.Max(
                    Dpi(40),
                    _plotBounds.Width / 4));
            TextRenderer.DrawText(
                graphics,
                label,
                Font,
                new Rectangle(
                    Math.Clamp(
                        x - labelWidth / 2,
                        0,
                        Math.Max(0, Width - labelWidth)),
                    _plotBounds.Bottom + Dpi(1),
                    labelWidth,
                    Dpi(18)),
                Color.FromArgb(112, 117, 126),
                TextFormatFlags.HorizontalCenter
                | TextFormatFlags.VerticalCenter
                | TextFormatFlags.SingleLine);
        }

        var display = _timeline.DisplaySamples(
            _range,
            _endingAt);
        if (display.Count == 0) return;

        var segments = new List<List<QuotaHistorySample>>();
        foreach (var sample in display)
        {
            if (segments.Count == 0
                || sample.Timestamp
                - segments[^1][^1].Timestamp
                > _range.ContinuityGap())
                segments.Add([]);
            segments[^1].Add(sample);
        }

        foreach (var segment in segments)
            DrawSegment(graphics, segment);

        foreach (var reset in _timeline.ResetEvents(
                     _range,
                     _endingAt))
        {
            var point = new PointF(
                MapX(reset.Timestamp),
                MapY(reset.RemainingPercent));
            using var brush =
                new SolidBrush(Color.FromArgb(16, 124, 65));
            graphics.FillEllipse(
                brush,
                point.X - Dpi(4),
                point.Y - Dpi(4),
                Dpi(8),
                Dpi(8));
        }

        var latest = _timeline.SamplesIn(
            _range,
            _endingAt).LastOrDefault();
        if (latest is not null)
        {
            var latestPoint = new PointF(
                MapX(latest.Timestamp),
                MapY(latest.RemainingPercent));
            using var latestBrush =
                new SolidBrush(Color.FromArgb(38, 120, 208));
            using var latestOutline =
                new Pen(Color.White, 1.5f);
            graphics.FillEllipse(
                latestBrush,
                latestPoint.X - Dpi(4),
                latestPoint.Y - Dpi(4),
                Dpi(8),
                Dpi(8));
            graphics.DrawEllipse(
                latestOutline,
                latestPoint.X - Dpi(4),
                latestPoint.Y - Dpi(4),
                Dpi(8),
                Dpi(8));
        }

        if (_selectedSample is { } selected)
        {
            var x = MapX(selected.Timestamp);
            using var rule = new Pen(
                Color.FromArgb(125, 94, 99, 108),
                1)
            {
                DashStyle = DashStyle.Dash
            };
            graphics.DrawLine(
                rule,
                x,
                _plotBounds.Top,
                x,
                _plotBounds.Bottom);
            using var selectedBrush =
                new SolidBrush(Color.FromArgb(40, 40, 43));
            graphics.FillEllipse(
                selectedBrush,
                x - Dpi(4),
                MapY(selected.RemainingPercent)
                - Dpi(4),
                Dpi(8),
                Dpi(8));
        }
    }

    private void DrawSegment(
        Graphics graphics,
        IReadOnlyList<QuotaHistorySample> segment)
    {
        if (segment.Count == 0) return;
        var points = segment.Select(sample =>
            new PointF(
                MapX(sample.Timestamp),
                MapY(sample.RemainingPercent)))
            .ToArray();
        if (points.Length == 1)
        {
            using var pointBrush =
                new SolidBrush(Color.FromArgb(38, 120, 208));
            graphics.FillEllipse(
                pointBrush,
                points[0].X - Dpi(3),
                points[0].Y - Dpi(3),
                Dpi(6),
                Dpi(6));
            return;
        }

        using (var area = new GraphicsPath())
        {
            area.AddLines(points);
            area.AddLine(
                points[^1].X,
                points[^1].Y,
                points[^1].X,
                _plotBounds.Bottom);
            area.AddLine(
                points[^1].X,
                _plotBounds.Bottom,
                points[0].X,
                _plotBounds.Bottom);
            area.CloseFigure();
            using var fill = new LinearGradientBrush(
                _plotBounds,
                Color.FromArgb(72, 38, 120, 208),
                Color.FromArgb(6, 38, 120, 208),
                LinearGradientMode.Vertical);
            graphics.FillPath(fill, area);
        }

        using var line = new Pen(
            Color.FromArgb(38, 120, 208),
            Dpi(2))
        {
            StartCap = LineCap.Round,
            EndCap = LineCap.Round,
            LineJoin = LineJoin.Round
        };
        graphics.DrawLines(line, points);
    }

    private void DrawFooter(Graphics graphics, int top)
    {
        var summary = _timeline.Summary(
            _range,
            _endingAt);
        TextRenderer.DrawText(
            graphics,
            T(
                $"区间观测消耗 {FormatNumber(summary.ObservedConsumption)} 个百分点",
                $"Observed use {FormatNumber(summary.ObservedConsumption)} pp"),
            Font,
            new Rectangle(
                0,
                top,
                Width * 2 / 3,
                Dpi(22)),
            Color.FromArgb(98, 103, 112),
            TextFormatFlags.Left
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine
            | TextFormatFlags.EndEllipsis);
        TextRenderer.DrawText(
            graphics,
            T(
                $"{summary.ResetCount} 次重置",
                $"{summary.ResetCount} resets"),
            Font,
            new Rectangle(
                Width * 2 / 3,
                top,
                Width - Width * 2 / 3,
                Dpi(22)),
            Color.FromArgb(98, 103, 112),
            TextFormatFlags.Right
            | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left) return;
        _dragging = true;
        Focus();
        SelectAt(e.X);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        if (_plotBounds.Contains(e.Location)
            && (_dragging || e.Button == MouseButtons.None))
            SelectAt(e.X);
    }

    protected override void OnMouseUp(MouseEventArgs e)
    {
        base.OnMouseUp(e);
        _dragging = false;
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        _dragging = false;
        if (_selectedSample is null) return;
        _selectedSample = null;
        UpdateAccessibleDescription();
        Invalidate();
    }

    protected override bool IsInputKey(Keys keyData) =>
        keyData is Keys.Left or Keys.Right
        || base.IsInputKey(keyData);

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.KeyCode is not (Keys.Left or Keys.Right))
            return;
        var visible = _timeline.SamplesIn(
            _range,
            _endingAt);
        if (visible.Count == 0) return;
        var current = _selectedSample ?? visible[^1];
        var index = visible
            .Select((sample, position) =>
                (sample, position))
            .FirstOrDefault(item =>
                item.sample.Timestamp
                == current.Timestamp)
            .position;
        index = e.KeyCode == Keys.Right
            ? Math.Min(visible.Count - 1, index + 1)
            : Math.Max(0, index - 1);
        _selectedSample = visible[index];
        UpdateAccessibleDescription();
        Invalidate();
        e.Handled = true;
    }

    private void SelectAt(int x)
    {
        if (_dataBounds.Width <= 0
            || x < _plotBounds.Left
            || x > _plotBounds.Right)
            return;
        var ratio = Math.Clamp(
            (x - _dataBounds.Left)
            / (double)_dataBounds.Width,
            0,
            1);
        var timestamp =
            _endingAt - _range.Duration()
            + TimeSpan.FromTicks(
                (long)(
                    _range.Duration().Ticks
                    * ratio));
        var sample = _timeline.NearestSample(
            timestamp,
            _range,
            _endingAt);
        if (sample?.Timestamp
            == _selectedSample?.Timestamp)
            return;
        _selectedSample = sample;
        UpdateAccessibleDescription();
        Invalidate();
    }

    private int MapX(DateTimeOffset timestamp)
    {
        var start = _endingAt - _range.Duration();
        var ratio = Math.Clamp(
            (timestamp - start).TotalSeconds
            / _range.Duration().TotalSeconds,
            0,
            1);
        return _dataBounds.Left
               + (int)Math.Round(
                   ratio * _dataBounds.Width);
    }

    private int MapY(double value)
    {
        var ratio = 1 - Math.Clamp(value / 100d, 0, 1);
        return _plotBounds.Top
               + (int)Math.Round(
                   ratio * _plotBounds.Height);
    }

    private void UpdateAccessibleDescription()
    {
        var sample = _selectedSample
                     ?? _timeline.SamplesIn(
                         _range,
                         _endingAt)
                         .LastOrDefault();
        AccessibleDescription = sample is null
            ? T("尚无记录", "No samples yet")
            : T(
                $"{SampleTimestamp(sample.Timestamp)}，剩余 {FormatNumber(sample.RemainingPercent)}%",
                $"{SampleTimestamp(sample.Timestamp)}, {FormatNumber(sample.RemainingPercent)}% remaining");
    }

    private string SampleTimestamp(DateTimeOffset timestamp) =>
        timestamp.LocalDateTime.ToString(
            _chinese ? "M月d日 HH:mm" : "MMM d, HH:mm",
            _chinese
                ? CultureInfo.GetCultureInfo("zh-CN")
                : CultureInfo.GetCultureInfo("en-US"));

    private string AxisTimestamp(DateTimeOffset timestamp) =>
        timestamp.LocalDateTime.ToString(
            _range == QuotaHistoryRange.Hours24
                ? "HH:mm"
                : _chinese
                    ? "M/d"
                    : "MMM d",
            _chinese
                ? CultureInfo.GetCultureInfo("zh-CN")
                : CultureInfo.GetCultureInfo("en-US"));

    private static string FormatNumber(double value) =>
        Math.Abs(Math.Round(value) - value) < .05
            ? value.ToString("0")
            : value.ToString("0.0");

    private int Dpi(int logical) =>
        logical == 0
            ? 0
            : Math.Max(
                1,
                (int)Math.Round(
                    logical
                    * DeviceDpi
                    / 96d,
                    MidpointRounding.AwayFromZero));

    private string T(string chinese, string english) =>
        _chinese ? chinese : english;

    private static GraphicsPath RoundedPath(
        Rectangle bounds,
        int radius)
    {
        var path = new GraphicsPath();
        var diameter = Math.Min(
            radius * 2,
            Math.Min(bounds.Width, bounds.Height));
        if (diameter < 2)
        {
            path.AddRectangle(bounds);
            return path;
        }
        path.AddArc(
            bounds.Left,
            bounds.Top,
            diameter,
            diameter,
            180,
            90);
        path.AddArc(
            bounds.Right - diameter,
            bounds.Top,
            diameter,
            diameter,
            270,
            90);
        path.AddArc(
            bounds.Right - diameter,
            bounds.Bottom - diameter,
            diameter,
            diameter,
            0,
            90);
        path.AddArc(
            bounds.Left,
            bounds.Bottom - diameter,
            diameter,
            diameter,
            90,
            90);
        path.CloseFigure();
        return path;
    }
}
