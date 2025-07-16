import Foundation

// TODO:
//   - handle expired security scope ?

public class FileMonitor {
    private var bookmark: Data?
    private var monitoredFileDescriptor: CInt = -1
    private let fileMonitorQueue = DispatchQueue(label: "FileMonitorQueue", attributes: .concurrent)
    private var source: DispatchSourceFileSystemObject?

    var url: Foundation.URL
    var fileDidChange: (() -> Void)
    var isPaused = false

    public init(url: Foundation.URL, changeHandler: @escaping () -> Void) {
        self.url = url
        self.fileDidChange = changeHandler

        self.startMonitoring()
    }

    public convenience init?(bookmark: Data, changeHandler: @escaping () -> Void) {
        do {
            var isStale = false
            let url = try Foundation.URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

            if isStale {
                print("Warning: The bookmark data was stale and has been resolved to a new location.")
            }

            self.init(url: url, changeHandler: changeHandler)

        } catch {
            print("ERROR: Failed to initialize FileMonitor from bookmark: \(error)")
            return nil
        }
    }

    public func startMonitoring() {
        guard source == nil && monitoredFileDescriptor == -1 else {
            print("ERROR: FileMonitor already has an open file")
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            print("ERROR: startAccessingSecurityScopedResource failed \(url.absoluteString)")
            return
        }

        if self.bookmark == nil {
            do {
                self.bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            } catch {
                print("ERROR: Failed to create bookmark data: \(error)")
            }
        }

        monitoredFileDescriptor = open(url.path, O_EVTONLY)
        url.stopAccessingSecurityScopedResource()

        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: monitoredFileDescriptor, eventMask: [.extend, .write, .delete, .link, .rename], queue: fileMonitorQueue)

        let cleanup: (FileMonitor) -> Void = { strongSelf in
            close(strongSelf.monitoredFileDescriptor)
            strongSelf.monitoredFileDescriptor = -1
            strongSelf.source = nil
        }

        source?.setEventHandler { [weak self] in
            guard let strongSelf = self, let event = strongSelf.source?.data, !strongSelf.isPaused else { return }

            switch(event) {
            case .rename:
                guard let oldBookmark = strongSelf.bookmark else {
                    print("ERROR: File was renamed, but no bookmark data is available.")
                    break
                }

                do {
                    var isStale = false
                    let newURL = try Foundation.URL(resolvingBookmarkData: oldBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    cleanup(strongSelf)
                    strongSelf.url = newURL
                    if isStale {
                        print("Bookmark was stale, creating a new one.")
                        strongSelf.bookmark = try newURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    }
                    strongSelf.startMonitoring()
                } catch {
                    print("ERROR: Could not resolve bookmark after rename: \(error)")
                    cleanup(strongSelf)
                }
                break
            case [.link, .delete]:
                cleanup(strongSelf)
                strongSelf.startMonitoring()
                break
            default:
                break
            }
            
            self?.fileDidChange()
        }

        source?.setCancelHandler { [weak self] in
            guard let strongSelf = self else { return }
            cleanup(strongSelf)
        }

        source?.resume()
    }

    public func stopMonitoring() {
        source?.cancel()
        self.bookmark = nil
    }

    private var writingTask: Task<(), any Error>?
    public func pauseMonitoring(for duration: Duration = .seconds(1)) {
        isPaused = true
        self.writingTask?.cancel() // NB a long pause could be cancelled and replaced by a shorter pause
        self.writingTask = Task {
            try await Task.sleep(for: duration)
            isPaused = false
        }
    }

    deinit {
        source?.cancel()
    }
}
