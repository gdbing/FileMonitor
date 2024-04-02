import Foundation

// TODO: 
//   - fix handling of rename
//   - handle expired security scope ?

public class FileMonitor {
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

    public func startMonitoring() {
        guard source == nil && monitoredFileDescriptor == -1 else {
            print("ERROR: FileMonitor already has an open file")
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            print("ERROR: startAccessingSecurityScopedResource failed \(url.absoluteString)")
            return
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
                var pathBuffer = [CChar](repeating: 0, count: Int(PATH_MAX))
                let result = fcntl(strongSelf.monitoredFileDescriptor, F_GETPATH, &pathBuffer)

                if result >= 0 {
                    let currentPath = String(cString: pathBuffer)
                    strongSelf.url = Foundation.URL(filePath:currentPath)
                    // TODO: this doesn't work, because we don't have the right to call startAccessingSecurityScopedResource on the new URL. Maybe if we save a bookmark? idgi
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
