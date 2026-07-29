import Darwin
import Foundation

public enum QuotaHistoryRange: String, CaseIterable, Codable, Sendable {
    case hours24
    case days7
    case days30

    public var duration: TimeInterval {
        switch self {
        case .hours24:
            return 24 * 60 * 60
        case .days7:
            return 7 * 24 * 60 * 60
        case .days30:
            return 30 * 24 * 60 * 60
        }
    }

    public var displayBucketDuration: TimeInterval {
        switch self {
        case .hours24:
            return 15 * 60
        case .days7:
            return 60 * 60
        case .days30:
            return 4 * 60 * 60
        }
    }

    public var continuityGap: TimeInterval {
        switch self {
        case .hours24:
            return 20 * 60
        case .days7:
            return 2 * 60 * 60
        case .days30:
            return 8 * 60 * 60
        }
    }
}

public struct QuotaHistorySample: Codable, Equatable, Identifiable, Sendable {
    public let timestamp: Date
    public let remainingPercent: Double
    public let resetsAt: Date?

    public var id: Date {
        timestamp
    }

    public init(
        timestamp: Date,
        remainingPercent: Double,
        resetsAt: Date?
    ) {
        self.timestamp = timestamp
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public struct QuotaHistoryResetEvent: Equatable, Identifiable, Sendable {
    public let timestamp: Date
    public let previousRemainingPercent: Double
    public let remainingPercent: Double

    public var id: Date {
        timestamp
    }

    public var increase: Double {
        remainingPercent - previousRemainingPercent
    }
}

public struct QuotaHistorySummary: Equatable, Sendable {
    public let observedConsumption: Double
    public let resetCount: Int
    public let sampleCount: Int

    public init(
        observedConsumption: Double,
        resetCount: Int,
        sampleCount: Int
    ) {
        self.observedConsumption = observedConsumption
        self.resetCount = resetCount
        self.sampleCount = sampleCount
    }
}

public struct QuotaHistoryTimeline: Equatable, Sendable {
    public static let archiveVersion = 1
    public static let retentionDuration: TimeInterval = 31 * 24 * 60 * 60

    public private(set) var samples: [QuotaHistorySample]

    public init(samples: [QuotaHistorySample] = []) {
        var byTimestamp: [Date: QuotaHistorySample] = [:]
        for sample in samples where Self.isValid(sample) {
            byTimestamp[sample.timestamp] = sample
        }
        self.samples = byTimestamp.values.sorted {
            $0.timestamp < $1.timestamp
        }
    }

    @discardableResult
    public mutating func record(
        _ sample: QuotaHistorySample,
        minimumInterval: TimeInterval = 5 * 60,
        minimumChange: Double = 0.25,
        endingAt now: Date
    ) -> Bool {
        guard Self.isValid(sample),
              sample.timestamp <= now.addingTimeInterval(5 * 60) else {
            return false
        }

        prune(endingAt: now)
        guard let previous = samples.last else {
            samples.append(sample)
            return true
        }
        guard sample.timestamp > previous.timestamp else {
            return false
        }

        let interval = sample.timestamp.timeIntervalSince(previous.timestamp)
        let change = abs(
            sample.remainingPercent - previous.remainingPercent
        )
        let resetBoundaryChanged = sample.resetsAt != previous.resetsAt
        guard interval >= minimumInterval
                || change >= minimumChange
                || resetBoundaryChanged else {
            return false
        }

        samples.append(sample)
        prune(endingAt: now)
        return true
    }

    public mutating func prune(endingAt now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retentionDuration)
        samples.removeAll { $0.timestamp < cutoff }
    }

    public func samples(
        in range: QuotaHistoryRange,
        endingAt now: Date
    ) -> [QuotaHistorySample] {
        let start = now.addingTimeInterval(-range.duration)
        return samples.filter {
            $0.timestamp >= start && $0.timestamp <= now
        }
    }

    public func displaySamples(
        in range: QuotaHistoryRange,
        endingAt now: Date
    ) -> [QuotaHistorySample] {
        let visible = samples(in: range, endingAt: now)
        guard visible.count > 2 else {
            return visible
        }

        let start = now.addingTimeInterval(-range.duration)
        let resetTimes = Set(
            resetEvents(in: range, endingAt: now).map(\.timestamp)
        )
        var selected = Set<Date>()
        var buckets: [Int: [QuotaHistorySample]] = [:]

        for sample in visible {
            let offset = sample.timestamp.timeIntervalSince(start)
            let bucket = Int(floor(offset / range.displayBucketDuration))
            buckets[bucket, default: []].append(sample)
        }

        for bucket in buckets.values {
            guard let first = bucket.first, let last = bucket.last else {
                continue
            }
            selected.insert(first.timestamp)
            selected.insert(last.timestamp)

            if let minimum = bucket.min(
                by: { $0.remainingPercent < $1.remainingPercent }
            ) {
                selected.insert(minimum.timestamp)
            }
            if let maximum = bucket.max(
                by: { $0.remainingPercent < $1.remainingPercent }
            ) {
                selected.insert(maximum.timestamp)
            }
            for sample in bucket where resetTimes.contains(sample.timestamp) {
                selected.insert(sample.timestamp)
            }
        }

        return visible.filter { selected.contains($0.timestamp) }
    }

    public func resetEvents(
        in range: QuotaHistoryRange,
        endingAt now: Date
    ) -> [QuotaHistoryResetEvent] {
        let visible = samples(in: range, endingAt: now)
        guard visible.count >= 2 else {
            return []
        }

        return zip(visible, visible.dropFirst()).compactMap {
            previous, current in
            guard Self.isObservedReset(
                previous: previous,
                current: current
            ) else {
                return nil
            }
            return QuotaHistoryResetEvent(
                timestamp: current.timestamp,
                previousRemainingPercent: previous.remainingPercent,
                remainingPercent: current.remainingPercent
            )
        }
    }

    public func summary(
        in range: QuotaHistoryRange,
        endingAt now: Date
    ) -> QuotaHistorySummary {
        let visible = samples(in: range, endingAt: now)
        let consumption = zip(visible, visible.dropFirst()).reduce(0.0) {
            partial, pair in
            partial + max(
                0,
                pair.0.remainingPercent - pair.1.remainingPercent
            )
        }
        return QuotaHistorySummary(
            observedConsumption: consumption,
            resetCount: resetEvents(in: range, endingAt: now).count,
            sampleCount: visible.count
        )
    }

    public func nearestSample(
        to date: Date,
        in range: QuotaHistoryRange,
        endingAt now: Date
    ) -> QuotaHistorySample? {
        let visible = samples(in: range, endingAt: now)
        guard !visible.isEmpty else {
            return nil
        }

        var lower = 0
        var upper = visible.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if visible[middle].timestamp < date {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        if lower == 0 {
            return visible[0]
        }
        if lower == visible.count {
            return visible[visible.count - 1]
        }
        let before = visible[lower - 1]
        let after = visible[lower]
        return date.timeIntervalSince(before.timestamp)
            <= after.timestamp.timeIntervalSince(date)
            ? before
            : after
    }

    public func previousSample(
        before sample: QuotaHistorySample
    ) -> QuotaHistorySample? {
        guard let index = samples.firstIndex(
            where: { $0.timestamp == sample.timestamp }
        ), index > 0 else {
            return nil
        }
        return samples[index - 1]
    }

    public func isResetSample(_ sample: QuotaHistorySample) -> Bool {
        guard let previous = previousSample(before: sample) else {
            return false
        }
        return Self.isObservedReset(previous: previous, current: sample)
    }

    static func isValid(_ sample: QuotaHistorySample) -> Bool {
        sample.timestamp.timeIntervalSinceReferenceDate.isFinite
            && sample.remainingPercent.isFinite
            && (0...100).contains(sample.remainingPercent)
            && (
                sample.resetsAt == nil
                    || sample.resetsAt?.timeIntervalSinceReferenceDate
                    .isFinite == true
            )
    }

    static func isObservedReset(
        previous: QuotaHistorySample,
        current: QuotaHistorySample
    ) -> Bool {
        let increase =
            current.remainingPercent - previous.remainingPercent
        guard increase > 0 else {
            return false
        }

        if let previousReset = previous.resetsAt,
           let currentReset = current.resetsAt,
           currentReset.timeIntervalSince(previousReset) >= 30 * 60,
           increase >= 5 {
            return true
        }
        if current.remainingPercent >= 80, increase >= 20 {
            return true
        }
        return increase >= 50
    }
}

public struct QuotaHistoryRecordResult: Equatable, Sendable {
    public let timeline: QuotaHistoryTimeline
    public let didChange: Bool

    public init(timeline: QuotaHistoryTimeline, didChange: Bool) {
        self.timeline = timeline
        self.didChange = didChange
    }
}

public struct QuotaHistoryStore: Sendable {
    public enum LoadResult: Equatable, Sendable {
        case absent
        case loaded(QuotaHistoryTimeline)
        case corrupt
        case unavailable
    }

    public enum StorageError: LocalizedError {
        case cannotPrepareDirectory
        case cannotLock
        case corruptArchive
        case cannotEncode
        case cannotWrite
        case cannotSync
        case cannotReplace

        public var errorDescription: String? {
            switch self {
            case .cannotPrepareDirectory:
                return "Quota history directory is unavailable"
            case .cannotLock:
                return "Quota history is being updated by another process"
            case .corruptArchive:
                return "Quota history cannot be decoded safely"
            case .cannotEncode:
                return "Quota history cannot be encoded"
            case .cannotWrite:
                return "Quota history cannot be written"
            case .cannotSync:
                return "Quota history cannot be synchronized"
            case .cannotReplace:
                return "Quota history cannot be committed"
            }
        }
    }

    public let url: URL
    private let lockURL: URL

    public init(url: URL = Self.defaultURL) {
        self.url = url
        self.lockURL = url
            .deletingPathExtension()
            .appendingPathExtension("lock")
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(
                AppConstants.bundleIdentifier,
                isDirectory: true
            )
            .appendingPathComponent("weekly-quota-history-v1.json")
    }

    public func load(endingAt now: Date = Date()) -> LoadResult {
        do {
            return try withLock(operation: LOCK_SH) {
                try loadUnlocked(endingAt: now)
            }
        } catch {
            return .unavailable
        }
    }

    public func record(
        _ sample: QuotaHistorySample,
        endingAt now: Date = Date()
    ) throws -> QuotaHistoryRecordResult {
        try withLock(operation: LOCK_EX) {
            var timeline: QuotaHistoryTimeline
            switch try loadUnlocked(endingAt: now) {
            case .absent:
                timeline = QuotaHistoryTimeline()
            case .loaded(let loaded):
                timeline = loaded
            case .corrupt:
                throw StorageError.corruptArchive
            case .unavailable:
                throw StorageError.cannotWrite
            }

            let changed = timeline.record(sample, endingAt: now)
            guard changed else {
                return QuotaHistoryRecordResult(
                    timeline: timeline,
                    didChange: false
                )
            }
            try saveUnlocked(timeline)
            return QuotaHistoryRecordResult(
                timeline: timeline,
                didChange: true
            )
        }
    }

    private struct Archive: Codable {
        let version: Int
        let samples: [QuotaHistorySample]
    }

    private func loadUnlocked(endingAt now: Date) throws -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .absent
        }
        guard let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(
                  Archive.self,
                  from: data
              ),
              archive.version == QuotaHistoryTimeline.archiveVersion,
              archive.samples.count <= 100_000,
              zip(
                  archive.samples,
                  archive.samples.dropFirst()
              ).allSatisfy({ $0.timestamp < $1.timestamp }),
              archive.samples.allSatisfy(QuotaHistoryTimeline.isValid) else {
            return .corrupt
        }

        var timeline = QuotaHistoryTimeline(samples: archive.samples)
        timeline.prune(endingAt: now)
        return .loaded(timeline)
    }

    private func saveUnlocked(_ timeline: QuotaHistoryTimeline) throws {
        let archive = Archive(
            version: QuotaHistoryTimeline.archiveVersion,
            samples: timeline.samples
        )
        guard let data = try? JSONEncoder().encode(archive) else {
            throw StorageError.cannotEncode
        }
        try Self.atomicWrite(data, to: url)
    }

    private func withLock<T>(
        operation: Int32,
        _ body: () throws -> T
    ) throws -> T {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw StorageError.cannotPrepareDirectory
        }

        let descriptor = lockURL.path.withCString {
            Darwin.open(
                $0,
                O_CREAT | O_RDWR | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0,
              Darwin.fchmod(
                  descriptor,
                  S_IRUSR | S_IWUSR
              ) == 0 else {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            throw StorageError.cannotLock
        }
        while flock(descriptor, operation) != 0 {
            if errno == EINTR {
                continue
            }
            Darwin.close(descriptor)
            throw StorageError.cannotLock
        }
        defer {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        return try body()
    }

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let descriptor = temporaryURL.path.withCString {
            Darwin.open(
                $0,
                O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            throw StorageError.cannotWrite
        }

        var descriptorIsOpen = true
        var shouldRemoveTemporary = true
        defer {
            if descriptorIsOpen {
                Darwin.close(descriptor)
            }
            if shouldRemoveTemporary {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let wroteAllBytes = data.withUnsafeBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress else {
                return data.isEmpty
            }
            var written = 0
            while written < buffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    buffer.count - written
                )
                if result < 0, errno == EINTR {
                    continue
                }
                guard result > 0 else {
                    return false
                }
                written += result
            }
            return true
        }
        guard wroteAllBytes else {
            throw StorageError.cannotWrite
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw StorageError.cannotSync
        }
        let closeResult = Darwin.close(descriptor)
        descriptorIsOpen = false
        guard closeResult == 0 else {
            throw StorageError.cannotSync
        }
        let renameResult = temporaryURL.path.withCString { temporaryPath in
            url.path.withCString { destinationPath in
                Darwin.rename(temporaryPath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw StorageError.cannotReplace
        }
        shouldRemoveTemporary = false

        let directoryDescriptor = directory.path.withCString {
            Darwin.open($0, O_RDONLY | O_CLOEXEC)
        }
        guard directoryDescriptor >= 0 else {
            throw StorageError.cannotSync
        }
        defer {
            Darwin.close(directoryDescriptor)
        }
        guard Darwin.fsync(directoryDescriptor) == 0 else {
            throw StorageError.cannotSync
        }
    }
}
