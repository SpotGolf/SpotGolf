import Foundation

extension URL {
    /// True for a folder on disk.
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
