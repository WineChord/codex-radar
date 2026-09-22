using System.Text.Json;

namespace CodexRadar.Windows;

internal static class QuotaHistoryObservationPolicy
{
    public static QuotaHistorySample? CreateSample(
        DashboardSnapshot snapshot,
        DateTimeOffset? previousObservation,
        DashboardPreview preview)
    {
        if (preview != DashboardPreview.Live
            || snapshot.QuotaObservedAt is not { } observedAt
            || observedAt == previousObservation
            || snapshot.WeeklyUsedPercent is not { } weeklyUsed)
            return null;

        return new QuotaHistorySample(
            observedAt,
            Math.Clamp(100 - weeklyUsed, 0, 100),
            snapshot.WeeklyResetsAt);
    }
}

internal static class QuotaHistoryRangeExtensions
{
    public static TimeSpan Duration(this QuotaHistoryRange range) => range switch
    {
        QuotaHistoryRange.Hours24 => TimeSpan.FromHours(24),
        QuotaHistoryRange.Days7 => TimeSpan.FromDays(7),
        _ => TimeSpan.FromDays(30)
    };

    public static TimeSpan DisplayBucketDuration(this QuotaHistoryRange range) => range switch
    {
        QuotaHistoryRange.Hours24 => TimeSpan.FromMinutes(15),
        QuotaHistoryRange.Days7 => TimeSpan.FromHours(1),
        _ => TimeSpan.FromHours(4)
    };

    public static TimeSpan ContinuityGap(this QuotaHistoryRange range) => range switch
    {
        QuotaHistoryRange.Hours24 => TimeSpan.FromMinutes(20),
        QuotaHistoryRange.Days7 => TimeSpan.FromHours(2),
        _ => TimeSpan.FromHours(8)
    };
}

internal sealed record QuotaHistorySample(
    DateTimeOffset Timestamp,
    double RemainingPercent,
    DateTimeOffset? ResetsAt);

internal sealed record QuotaHistoryResetEvent(
    DateTimeOffset Timestamp,
    double PreviousRemainingPercent,
    double RemainingPercent)
{
    public double Increase => RemainingPercent - PreviousRemainingPercent;
}

internal sealed record QuotaHistorySummary(
    double ObservedConsumption,
    int ResetCount,
    int SampleCount);

internal sealed class QuotaHistoryTimeline
{
    public const int ArchiveVersion = 1;
    public static readonly TimeSpan RetentionDuration = TimeSpan.FromDays(31);

    private readonly List<QuotaHistorySample> _samples;
    public IReadOnlyList<QuotaHistorySample> Samples => _samples;

    public QuotaHistoryTimeline(
        IEnumerable<QuotaHistorySample>? samples = null)
    {
        _samples = (samples ?? [])
            .Where(IsValid)
            .GroupBy(sample => sample.Timestamp)
            .Select(group => group.Last())
            .OrderBy(sample => sample.Timestamp)
            .ToList();
    }

    public bool Record(
        QuotaHistorySample sample,
        DateTimeOffset endingAt,
        TimeSpan? minimumInterval = null,
        double minimumChange = 0.25)
    {
        if (!IsValid(sample)
            || sample.Timestamp > endingAt.AddMinutes(5))
            return false;

        Prune(endingAt);
        if (_samples.Count == 0)
        {
            _samples.Add(sample);
            return true;
        }

        var previous = _samples[^1];
        if (sample.Timestamp <= previous.Timestamp)
            return false;

        var interval = sample.Timestamp - previous.Timestamp;
        var change = Math.Abs(
            sample.RemainingPercent
            - previous.RemainingPercent);
        var resetBoundaryChanged =
            sample.ResetsAt != previous.ResetsAt;
        if (interval < (minimumInterval ?? TimeSpan.FromMinutes(5))
            && change < minimumChange
            && !resetBoundaryChanged)
            return false;

        _samples.Add(sample);
        Prune(endingAt);
        return true;
    }

    public void Prune(DateTimeOffset endingAt)
    {
        var cutoff = endingAt - RetentionDuration;
        _samples.RemoveAll(sample => sample.Timestamp < cutoff);
    }

    public IReadOnlyList<QuotaHistorySample> SamplesIn(
        QuotaHistoryRange range,
        DateTimeOffset endingAt)
    {
        var start = endingAt - range.Duration();
        return _samples
            .Where(sample =>
                sample.Timestamp >= start
                && sample.Timestamp <= endingAt)
            .ToArray();
    }

    public IReadOnlyList<QuotaHistorySample> DisplaySamples(
        QuotaHistoryRange range,
        DateTimeOffset endingAt)
    {
        var visible = SamplesIn(range, endingAt);
        if (visible.Count <= 2) return visible;

        var start = endingAt - range.Duration();
        var resetTimes = ResetEvents(range, endingAt)
            .Select(item => item.Timestamp)
            .ToHashSet();
        var selected = new HashSet<DateTimeOffset>();
        var buckets = visible.GroupBy(sample =>
            (long)Math.Floor(
                (sample.Timestamp - start).TotalSeconds
                / range.DisplayBucketDuration().TotalSeconds));

        foreach (var bucket in buckets)
        {
            var items = bucket.ToArray();
            selected.Add(items[0].Timestamp);
            selected.Add(items[^1].Timestamp);
            selected.Add(items.MinBy(
                sample => sample.RemainingPercent)!.Timestamp);
            selected.Add(items.MaxBy(
                sample => sample.RemainingPercent)!.Timestamp);
            foreach (var sample in items
                         .Where(sample =>
                             resetTimes.Contains(sample.Timestamp)))
                selected.Add(sample.Timestamp);
        }

        return visible
            .Where(sample => selected.Contains(sample.Timestamp))
            .ToArray();
    }

    public IReadOnlyList<QuotaHistoryResetEvent> ResetEvents(
        QuotaHistoryRange range,
        DateTimeOffset endingAt)
    {
        var visible = SamplesIn(range, endingAt);
        if (visible.Count < 2) return [];

        var events = new List<QuotaHistoryResetEvent>();
        for (var index = 1; index < visible.Count; index++)
        {
            var previous = visible[index - 1];
            var current = visible[index];
            if (!IsObservedReset(previous, current)) continue;
            events.Add(new QuotaHistoryResetEvent(
                current.Timestamp,
                previous.RemainingPercent,
                current.RemainingPercent));
        }
        return events;
    }

    public QuotaHistorySummary Summary(
        QuotaHistoryRange range,
        DateTimeOffset endingAt)
    {
        var visible = SamplesIn(range, endingAt);
        var consumption = 0d;
        for (var index = 1; index < visible.Count; index++)
            consumption += Math.Max(
                0,
                visible[index - 1].RemainingPercent
                - visible[index].RemainingPercent);
        return new QuotaHistorySummary(
            consumption,
            ResetEvents(range, endingAt).Count,
            visible.Count);
    }

    public QuotaHistorySample? NearestSample(
        DateTimeOffset timestamp,
        QuotaHistoryRange range,
        DateTimeOffset endingAt)
    {
        var visible = SamplesIn(range, endingAt);
        if (visible.Count == 0) return null;

        var lower = 0;
        var upper = visible.Count;
        while (lower < upper)
        {
            var middle = (lower + upper) / 2;
            if (visible[middle].Timestamp < timestamp)
                lower = middle + 1;
            else
                upper = middle;
        }

        if (lower == 0) return visible[0];
        if (lower == visible.Count) return visible[^1];
        var before = visible[lower - 1];
        var after = visible[lower];
        return timestamp - before.Timestamp
               <= after.Timestamp - timestamp
            ? before
            : after;
    }

    public QuotaHistorySample? PreviousSample(
        QuotaHistorySample sample)
    {
        var index = _samples.FindIndex(
            item => item.Timestamp == sample.Timestamp);
        return index > 0 ? _samples[index - 1] : null;
    }

    public bool IsResetSample(QuotaHistorySample sample) =>
        PreviousSample(sample) is { } previous
        && IsObservedReset(previous, sample);

    public static QuotaHistoryTimeline CreatePreview(
        DateTimeOffset endingAt)
    {
        var samples = new List<QuotaHistorySample>();
        var start = endingAt - RetentionDuration;
        var resetAt = start.AddDays(7);
        var remaining = 96d;
        var index = 0;
        for (var time = start;
             time <= endingAt;
             time = time.AddHours(2), index++)
        {
            if (index is >= 210 and <= 218)
                continue;
            if (time >= resetAt)
            {
                remaining = 98;
                resetAt = resetAt.AddDays(7);
            }
            else
            {
                remaining = Math.Max(
                    8,
                    remaining - (index % 4 == 0 ? 1.4 : 0.35));
            }
            samples.Add(new QuotaHistorySample(
                time,
                remaining,
                resetAt));
        }
        return new QuotaHistoryTimeline(samples);
    }

    internal static bool IsValid(QuotaHistorySample sample) =>
        double.IsFinite(sample.RemainingPercent)
        && sample.RemainingPercent is >= 0 and <= 100;

    internal static bool IsObservedReset(
        QuotaHistorySample previous,
        QuotaHistorySample current)
    {
        var increase =
            current.RemainingPercent - previous.RemainingPercent;
        if (increase <= 0) return false;

        if (previous.ResetsAt is { } previousReset
            && current.ResetsAt is { } currentReset
            && currentReset - previousReset >= TimeSpan.FromMinutes(30)
            && increase >= 5)
            return true;
        if (current.RemainingPercent >= 80 && increase >= 20)
            return true;
        return increase >= 50;
    }
}

internal enum QuotaHistoryLoadStatus
{
    Absent,
    Loaded,
    Corrupt,
    Unavailable
}

internal sealed record QuotaHistoryLoadResult(
    QuotaHistoryLoadStatus Status,
    QuotaHistoryTimeline Timeline);

internal sealed record QuotaHistoryRecordResult(
    QuotaHistoryTimeline Timeline,
    bool DidChange);

internal sealed class QuotaHistoryStore
{
    private const int MaximumArchiveSamples = 100_000;
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = false
    };

    private readonly string _path;
    private readonly string _lockPath;

    public QuotaHistoryStore(string? path = null)
    {
        _path = path ?? Path.Combine(
            AppSettings.SettingsDirectory,
            "weekly-quota-history-v1.json");
        _lockPath = Path.ChangeExtension(_path, ".lock");
    }

    public QuotaHistoryLoadResult Load(
        DateTimeOffset? endingAt = null)
    {
        try
        {
            using var gate = AcquireLock();
            return LoadUnlocked(endingAt ?? DateTimeOffset.Now);
        }
        catch
        {
            return new QuotaHistoryLoadResult(
                QuotaHistoryLoadStatus.Unavailable,
                new QuotaHistoryTimeline());
        }
    }

    public QuotaHistoryRecordResult Record(
        QuotaHistorySample sample,
        DateTimeOffset? endingAt = null)
    {
        var now = endingAt ?? DateTimeOffset.Now;
        using var gate = AcquireLock();
        var loaded = LoadUnlocked(now);
        var timeline = loaded.Status switch
        {
            QuotaHistoryLoadStatus.Absent =>
                new QuotaHistoryTimeline(),
            QuotaHistoryLoadStatus.Loaded => loaded.Timeline,
            QuotaHistoryLoadStatus.Corrupt =>
                throw new InvalidDataException(
                    "Quota history archive is corrupt and was not overwritten."),
            _ => throw new IOException(
                "Quota history archive is unavailable.")
        };

        var changed = timeline.Record(sample, now);
        if (changed) SaveUnlocked(timeline);
        return new QuotaHistoryRecordResult(timeline, changed);
    }

    private QuotaHistoryLoadResult LoadUnlocked(
        DateTimeOffset endingAt)
    {
        if (!File.Exists(_path))
            return new QuotaHistoryLoadResult(
                QuotaHistoryLoadStatus.Absent,
                new QuotaHistoryTimeline());

        try
        {
            var bytes = File.ReadAllBytes(_path);
            var archive = JsonSerializer.Deserialize<Archive>(bytes);
            if (archive is null
                || !IsArchiveValid(
                    archive.Version,
                    archive.Samples))
                return new QuotaHistoryLoadResult(
                    QuotaHistoryLoadStatus.Corrupt,
                    new QuotaHistoryTimeline());

            var timeline =
                new QuotaHistoryTimeline(archive.Samples);
            timeline.Prune(endingAt);
            return new QuotaHistoryLoadResult(
                QuotaHistoryLoadStatus.Loaded,
                timeline);
        }
        catch (JsonException)
        {
            return new QuotaHistoryLoadResult(
                QuotaHistoryLoadStatus.Corrupt,
                new QuotaHistoryTimeline());
        }
        catch (NotSupportedException)
        {
            return new QuotaHistoryLoadResult(
                QuotaHistoryLoadStatus.Corrupt,
                new QuotaHistoryTimeline());
        }
    }

    internal static bool IsArchiveValid(
        int version,
        IReadOnlyList<QuotaHistorySample>? samples) =>
        version == QuotaHistoryTimeline.ArchiveVersion
        && samples is not null
        && samples.Count <= MaximumArchiveSamples
        && samples.All(QuotaHistoryTimeline.IsValid)
        && samples.Zip(
                samples.Skip(1),
                (left, right) =>
                    left.Timestamp < right.Timestamp)
            .All(valid => valid);

    private FileStream AcquireLock()
    {
        var directory = Path.GetDirectoryName(_path);
        if (string.IsNullOrWhiteSpace(directory))
            throw new IOException(
                "Quota history directory is unavailable.");
        PrivateStorageSecurity.EnsureDirectory(directory);

        IOException? lastFailure = null;
        for (var attempt = 0; attempt < 80; attempt++)
        {
            try
            {
                var stream = new FileStream(
                    _lockPath,
                    FileMode.OpenOrCreate,
                    FileAccess.ReadWrite,
                    FileShare.None,
                    1,
                    FileOptions.WriteThrough);
                PrivateStorageSecurity.EnsureFile(_lockPath);
                return stream;
            }
            catch (IOException ex)
            {
                lastFailure = ex;
                Thread.Sleep(25);
            }
        }
        throw new IOException(
            "Quota history is being updated by another process.",
            lastFailure);
    }

    private void SaveUnlocked(QuotaHistoryTimeline timeline)
    {
        var archive = new Archive(
            QuotaHistoryTimeline.ArchiveVersion,
            timeline.Samples.ToList());
        var bytes = JsonSerializer.SerializeToUtf8Bytes(
            archive,
            Json);
        var temporary = _path
                        + $".{Environment.ProcessId}."
                        + $"{Guid.NewGuid():N}.tmp";
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
                stream.Flush(flushToDisk: true);
            }
            PrivateStorageSecurity.EnsureFile(temporary);
            if (File.Exists(_path))
                File.Replace(
                    temporary,
                    _path,
                    destinationBackupFileName: null,
                    ignoreMetadataErrors: true);
            else
                File.Move(temporary, _path);
            PrivateStorageSecurity.EnsureFile(_path);
        }
        finally
        {
            try
            {
                if (File.Exists(temporary))
                    File.Delete(temporary);
            }
            catch
            {
            }
        }
    }

    private sealed record Archive(
        int Version,
        List<QuotaHistorySample> Samples);
}
