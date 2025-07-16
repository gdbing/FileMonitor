# FileMonitor

A lightweight Swift library for monitoring file system changes to a specific file. Monitors and responds to file events like `write`, `extend`, `delete`, `link`, and `rename`.

## Usage

### Initializing with a URL

Create a `FileMonitor` instance by providing a file `URL`. FileMonitor will create and manage a security-scoped bookmark to handle renames and maintain access.

```swift
import FileMonitor
import Foundation

let fileURL = URL(fileURLWithPath: "/path/to/your/document.txt")

let fileMonitor = FileMonitor(url: fileURL) {
    print("File did change!")
}

// When you're done:
// fileMonitor.stopMonitoring()
```

### Initializing with a Bookmark

Save the `bookmark` data and use it to initialize a new monitor in a later application launch.

**Saving the bookmark:**

```swift
// After initial access is granted
guard let bookmarkData = fileMonitor.bookmark else { return }
// Save bookmarkData to UserDefaults, a file, etc.
```

**Restoring access on next launch:**

```swift
// Load bookmarkData from its saved location
let newFileMonitor = FileMonitor(bookmark: bookmarkData) {
    print("File did change!")
}
```
