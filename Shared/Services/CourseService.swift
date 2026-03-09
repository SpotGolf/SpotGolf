import Foundation
import Compression
import CoreLocation

// MARK: - NearbyResult

struct NearbyResult {
    let entry: CourseIndexEntry
    let distanceMiles: Double
}

// MARK: - CourseServiceError

enum CourseServiceError: Error {
    case invalidVersion
    case invalidURL
    case compressionFailed
    case decompressionFailed
}

// MARK: - CourseService

@MainActor
class CourseService: ObservableObject {

    @Published var index: [CourseIndexEntry] = []

    static let maxCacheBytes = 5 * 1024 * 1024
    private static let tenMilesInMeters: Double = 16093.44

    private static let baseURL = "https://raw.githubusercontent.com/SpotGolf/CourseData/main/"

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.cacheDirectory = documents.appendingPathComponent("CourseCache")
        }
        try? fileManager.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Index Management

    func refreshIndex() async {
        do {
            guard let versionURL = URL(string: Self.baseURL + "index.version") else {
                throw CourseServiceError.invalidURL
            }

            let (versionData, _) = try await URLSession.shared.data(from: versionURL)
            guard let versionString = String(data: versionData, encoding: .utf8),
                  let remoteVersion = Self.parseVersion(versionString) else {
                throw CourseServiceError.invalidVersion
            }

            let cachedVersion = cachedIndexVersion()

            if cachedVersion == nil || remoteVersion > cachedVersion! {
                guard let indexURL = URL(string: Self.baseURL + "index.json") else {
                    throw CourseServiceError.invalidURL
                }

                let (indexData, _) = try await URLSession.shared.data(from: indexURL)
                try cacheIndex(data: indexData, version: remoteVersion)
                index = try JSONDecoder().decode([CourseIndexEntry].self, from: indexData)
            } else {
                if let cached = try loadCachedIndex() {
                    index = cached
                }
            }
        } catch {
            print("[CourseService] refreshIndex failed: \(error)")
            if let cached = try? loadCachedIndex() {
                index = cached
            }
        }
    }

    static func parseVersion(_ string: String) -> Int? {
        Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func cachedIndexVersion() -> Int? {
        let versionFile = cacheDirectory.appendingPathComponent("index.version")
        guard let data = try? Data(contentsOf: versionFile),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return Self.parseVersion(string)
    }

    func cacheIndex(data: Data, version: Int) throws {
        let compressed = try compress(data)

        let indexFile = cacheDirectory.appendingPathComponent("index.json.gz")
        try compressed.write(to: indexFile)

        let versionFile = cacheDirectory.appendingPathComponent("index.version")
        try "\(version)".data(using: .utf8)!.write(to: versionFile)
    }

    func loadCachedIndex() throws -> [CourseIndexEntry]? {
        let indexFile = cacheDirectory.appendingPathComponent("index.json.gz")
        guard fileManager.fileExists(atPath: indexFile.path) else {
            return nil
        }

        let compressed = try Data(contentsOf: indexFile)
        let decompressed = try decompress(compressed)
        return try JSONDecoder().decode([CourseIndexEntry].self, from: decompressed)
    }

    // MARK: - Course Fetch

    func fetchCourse(path: String) async throws -> Course {
        guard let url = URL(string: Self.baseURL + path) else {
            throw CourseServiceError.invalidURL
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try cacheCourseData(data, forPath: path)
            return try JSONDecoder().decode(Course.self, from: data)
        } catch {
            if let cached = try loadCachedCourse(path: path) {
                return cached
            }
            throw error
        }
    }

    func cacheCourseData(_ data: Data, forPath path: String) throws {
        let coursesDir = cacheDirectory.appendingPathComponent("courses")
        let fileURL = coursesDir.appendingPathComponent(sanitizedPath(path) + ".gz")
        let parentDir = fileURL.deletingLastPathComponent()

        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let compressed = try compress(data)
        try compressed.write(to: fileURL)

        enforceCacheLimit()
    }

    func loadCachedCourse(path: String) throws -> Course? {
        let coursesDir = cacheDirectory.appendingPathComponent("courses")
        let fileURL = coursesDir.appendingPathComponent(sanitizedPath(path) + ".gz")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let compressed = try Data(contentsOf: fileURL)
        let decompressed = try decompress(compressed)
        return try JSONDecoder().decode(Course.self, from: decompressed)
    }

    // MARK: - Nearby & Search

    func nearbyCourses(from location: CLLocation) -> [NearbyResult] {
        index.compactMap { entry in
            let courseLocation = entry.coordinate.clLocation
            let distanceMeters = location.distance(from: courseLocation)
            guard distanceMeters <= Self.tenMilesInMeters else { return nil }
            let distanceMiles = distanceMeters / 1609.344
            return NearbyResult(entry: entry, distanceMiles: distanceMiles)
        }
        .sorted { $0.distanceMiles < $1.distanceMiles }
    }

    func searchCourses(query: String) -> [CourseIndexEntry] {
        guard !query.isEmpty else { return [] }
        let lowered = query.lowercased()
        return index.filter { entry in
            entry.name.lowercased().contains(lowered)
        }
    }

    // MARK: - Cache Management

    func cacheSizeBytes() -> Int {
        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }

    private func enforceCacheLimit() {
        let totalSize = cacheSizeBytes()
        guard totalSize > Self.maxCacheBytes else { return }

        let coursesDir = cacheDirectory.appendingPathComponent("courses")
        guard let enumerator = fileManager.enumerator(
            at: coursesDir,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var files: [(url: URL, accessDate: Date, size: Int)] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                continue
            }
            let date = values.contentAccessDate ?? Date.distantPast
            let size = values.fileSize ?? 0
            files.append((url: fileURL, accessDate: date, size: size))
        }

        // Sort oldest-accessed first
        files.sort { $0.accessDate < $1.accessDate }

        var currentSize = totalSize
        for file in files {
            guard currentSize > Self.maxCacheBytes else { break }
            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
        }
    }

    // MARK: - Compression Helpers

    private func compress(_ data: Data) throws -> Data {
        let sourceSize = data.count
        let destinationSize = sourceSize + 512 // zlib may slightly expand incompressible data
        var destinationBuffer = [UInt8](repeating: 0, count: destinationSize)

        let compressedSize = data.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_encode_buffer(
                &destinationBuffer,
                destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else {
            throw CourseServiceError.compressionFailed
        }

        // Prepend original size as 8-byte little-endian for decompression
        var size = UInt64(sourceSize).littleEndian
        var result = Data(bytes: &size, count: 8)
        result.append(Data(bytes: destinationBuffer, count: compressedSize))
        return result
    }

    private func decompress(_ data: Data) throws -> Data {
        guard data.count > 8 else {
            throw CourseServiceError.decompressionFailed
        }

        let originalSize: UInt64 = data.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self).littleEndian
        }

        let maxDecompressedSize: UInt64 = 50 * 1024 * 1024
        guard originalSize > 0, originalSize <= maxDecompressedSize else {
            throw CourseServiceError.decompressionFailed
        }

        let compressedData = data.dropFirst(8)
        let destinationSize = Int(originalSize)
        var destinationBuffer = [UInt8](repeating: 0, count: destinationSize)

        let decompressedSize = compressedData.withUnsafeBytes { sourcePtr -> Int in
            guard let baseAddress = sourcePtr.baseAddress else { return 0 }
            return compression_decode_buffer(
                &destinationBuffer,
                destinationSize,
                baseAddress.assumingMemoryBound(to: UInt8.self),
                compressedData.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else {
            throw CourseServiceError.decompressionFailed
        }

        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    // MARK: - Path Helpers

    private func sanitizedPath(_ path: String) -> String {
        // Replace path separators to create a flat filename
        path.replacingOccurrences(of: "/", with: "_")
    }
}
