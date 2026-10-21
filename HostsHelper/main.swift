import Foundation

// Privileged helper entry point. Runs as a root LaunchDaemon and serves the
// XPC mach service that the main app connects to for writing /etc/hosts.
let delegate = HostsHelperDelegate()
let listener = NSXPCListener(machServiceName: HostsHelperConstants.serviceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
