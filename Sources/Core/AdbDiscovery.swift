import Foundation
import Darwin

public struct AdbService: Identifiable, Equatable {
    public let name: String, host: String, port: Int, pairing: Bool
    public var id: String { (pairing ? "pair:" : "connect:")+name }
}

/// Bonjour callbacks are scheduled on the main run loop. Pairing and TLS I/O
/// stay on background threads; the browser never blocks the UI run loop.
public final class AdbDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    public var onChange: (([AdbService]) -> Void)?
    public var onError: (() -> Void)?
    private var browsers: [NetServiceBrowser]=[]
    private var resolving: [String:NetService]=[:]
    public private(set) var services: [AdbService]=[]
    public func start() {
        guard browsers.isEmpty else { return }
        for type in ["_adb-tls-pairing._tcp.","_adb-tls-connect._tcp."] {
            let browser=NetServiceBrowser(); browser.delegate=self; browsers.append(browser)
            browser.searchForServices(ofType:type,inDomain:"local.")
        }
    }
    public func stop() { browsers.forEach { $0.stop() }; browsers=[]; resolving.values.forEach { $0.stop() }; resolving=[:]; services=[]; onChange?([]) }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) { let key=service.type+service.name; resolving[key]=service; service.delegate=self; service.resolve(withTimeout:8) }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) { resolving.removeValue(forKey:service.type+service.name)?.stop(); services.removeAll { $0.name == service.name && $0.pairing == service.type.contains("pairing") }; onChange?(services) }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String:NSNumber]) { onError?() }
    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard resolving[sender.type+sender.name] === sender, sender.port > 0 else { return }
        let sorted=(sender.addresses ?? []).sorted { ($0.count > 1 ? $0[1] : 0) < ($1.count > 1 ? $1[1] : 0) }
        for data in sorted {
            var buffer=[CChar](repeating:0,count:Int(NI_MAXHOST))
            let result=data.withUnsafeBytes { raw -> Int32 in
                guard let address=raw.baseAddress?.assumingMemoryBound(to:sockaddr.self) else { return -1 }
                return getnameinfo(address,socklen_t(data.count),&buffer,socklen_t(buffer.count),nil,0,NI_NUMERICHOST)
            }
            guard result == 0 else { continue }
            let service=AdbService(name:sender.name,host:String(cString:buffer),port:sender.port,pairing:sender.type.contains("pairing"))
            services.removeAll { $0.id == service.id }; services.append(service); services.sort { $0.name < $1.name }; onChange?(services); return
        }
    }
}
