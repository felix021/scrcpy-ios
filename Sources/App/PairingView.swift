import SwiftUI
import CoreImage.CIFilterBuiltins
import ScrcpyCore

@MainActor final class PairingModel: ObservableObject {
    @Published var host=""
    @Published var pairingPort=""
    @Published var connectPort=""
    @Published var code=""
    @Published var qr=true
    @Published var busy=false
    @Published var paired=false
    @Published var status=""
    @Published var services: [AdbService]=[]
    @Published var challenge: PairingChallenge?
    @Published var discoveryFailed=false
    private let discovery=AdbDiscovery()
    private var client: AdbPairingClient?
    private var generation=UUID()
    private var attemptedQR=false
    private var suggestedPort=false
    var localName=""
    func start() {
        discovery.onChange = { [weak self] services in self?.services=services; self?.matchQR(); self?.findConnectPort() }
        discovery.onError = { [weak self] in self?.discoveryFailed=true }
        discovery.start(); refreshQR()
    }
    func refreshQR() {
        cancel(); paired=false; attemptedQR=false; suggestedPort=false; connectPort=""; status=""
        do { challenge=try PairingChallenge() } catch { status=error.localizedDescription }
    }
    func switchMode(_ value: Bool) { guard qr != value else { return }; cancel(); qr=value; paired=false; suggestedPort=false; connectPort=""; status=""; if value { refreshQR() } }
    func cancel() { generation=UUID(); client?.cancel(); client=nil; busy=false }
    func stop() { cancel(); discovery.stop() }
    func pairCode() {
        guard code.utf8.count == 6, code.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { status=L("请输入 Android 上的 6 位配对码","Enter the six-digit code shown on Android"); return }
        pair(host:host,port:pairingPort,password:code)
    }
    private func matchQR() {
        guard qr, !busy, !paired, !attemptedQR, let challenge, let service=services.first(where:{$0.pairing && $0.name == challenge.serviceName}) else { return }
        attemptedQR=true; host=service.host; pairingPort=String(service.port); pair(host:service.host,port:String(service.port),password:challenge.password)
    }
    func findConnectPort() {
        guard paired, !suggestedPort, connectPort.isEmpty else { return }
        if let endpoint=services.first(where:{!$0.pairing && $0.host == host}) { connectPort=String(endpoint.port); suggestedPort=true }
    }
    private func pair(host: String, port: String, password: String) {
        guard !busy, let number=Int(port), (1...65535).contains(number) else { status=L("请输入有效的配对端口","Enter a valid pairing port"); return }
        do {
            let client=try AdbPairingClient(host:host.trimmingCharacters(in:.whitespacesAndNewlines),port:number,identity:AdbIdentity(),clientName:localName)
            self.client=client; let token=UUID(); generation=token; busy=true; status=L("正在安全配对…","Pairing securely…")
            Task.detached { [weak self] in
                let result=Result { try client.pair(password:password) }
                await self?.finished(result,token:token)
            }
        } catch { status=error.localizedDescription }
    }
    private func finished(_ result: Result<String,Error>, token: UUID) {
        guard token == generation else { return }; busy=false; client=nil
        switch result {
        case .success: paired=true; code=""; status=L("配对成功","Paired successfully"); findConnectPort()
        case .failure(let error): status=L("配对失败：","Pairing failed: ")+error.localizedDescription
        }
    }
    var qrImage: UIImage? {
        guard let challenge else { return nil }; let filter=CIFilter.qrCodeGenerator(); filter.message=Data(challenge.qrPayload.utf8); filter.correctionLevel="M"
        guard let output=filter.outputImage, let bitmap=CIContext().createCGImage(output.transformed(by:CGAffineTransform(scaleX:8,y:8)),from:output.extent.applying(CGAffineTransform(scaleX:8,y:8))) else { return nil }
        return UIImage(cgImage:bitmap)
    }
}

struct PairingView: View {
    @ObservedObject var model: AppModel
    @StateObject private var pair=PairingModel()
    @State private var settings=false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        SheetPanel(title:L("无线调试配对","Pair wireless debugging"),subtitle:L("Android 11 及以上，无需先接电脑。","Android 11 or later. No initial USB connection required."),model:model) {
            HStack { mode(L("二维码","QR code"),true); mode(L("配对码","Pairing code"),false) }
            Button { settings=true } label: { HStack { Label(model.localName,systemImage:"ipad.and.iphone"); Spacer(); Text(L("修改本机名称","Edit this device’s name")).font(.system(size:11)); Image(systemName:"chevron.right") }.font(.system(size:13)).padding(12).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:12)) }.accessibilityIdentifier("pairingDeviceName")
            if pair.paired {
                Label(L("已与 Android 配对","Paired with Android"),systemImage:"checkmark.shield.fill").foregroundStyle(Theme.accent).accessibilityIdentifier("pairingSuccess")
                Text(L("连接端口与配对端口不同。若未自动发现，请填写 Android 无线调试主页面的 IP 地址和端口。","The connection port differs from the pairing port. If not discovered, use the IP and port on Android’s main Wireless debugging page.")).font(.system(size:12)).foregroundStyle(Theme.muted)
                FormField(title:L("设备 IP / 主机名","Device IP / hostname"),text:$pair.host,id:"pairedHost",numeric:false)
                FormField(title:L("连接端口","Connection port"),text:$pair.connectPort,id:"pairedConnectPort")
            } else if pair.qr {
                Text(L("在 Android 的「开发者选项 → 无线调试 → 使用二维码配对」中扫描下方二维码，两台设备需在同一局域网。","On Android, open Developer options → Wireless debugging → Pair using QR code, then scan below. Both devices need the same local network.")).font(.system(size:13)).foregroundStyle(Theme.muted)
                if let image=pair.qrImage { Image(uiImage:image).interpolation(.none).resizable().scaledToFit().padding(16).background(.white).clipShape(RoundedRectangle(cornerRadius:16)).frame(maxWidth:300).frame(maxWidth:.infinity).accessibilityLabel(L("ADB 配对二维码","ADB pairing QR code")).accessibilityIdentifier("pairingQRCode") }
                Button(L("刷新二维码","Refresh QR code")) { pair.refreshQR() }.buttonStyle(AppButton()).disabled(pair.busy).accessibilityIdentifier("refreshPairingQR")
            } else {
                Text(L("Android 开发者选项 → 无线调试 → 使用配对码配对。保持该弹框打开，填写其中的地址、端口和 6 位配对码。","Open Developer options → Wireless debugging → Pair using pairing code on Android. Keep that dialog open and enter its address, port and six-digit code.")).font(.system(size:13)).foregroundStyle(Theme.muted)
                FormField(title:L("设备 IP / 主机名","Device IP / hostname"),text:$pair.host,id:"pairingHost",numeric:false).disabled(pair.busy)
                HStack { FormField(title:L("配对端口","Pairing port"),text:$pair.pairingPort,id:"pairingPort").disabled(pair.busy); FormField(title:L("6 位配对码","Six-digit code"),text:$pair.code,id:"pairingCode").disabled(pair.busy) }
                if !pair.services.filter({$0.pairing}).isEmpty {
                    Text(L("发现的配对设备","Discovered pairing devices")).font(.system(size:12)).foregroundStyle(Theme.muted)
                    ForEach(pair.services.filter(\.pairing)) { service in Button { pair.host=service.host; pair.pairingPort=String(service.port) } label: { VStack(alignment:.leading,spacing:4) { Text(service.name).lineLimit(1); Text("\(service.host):\(service.port)").font(.system(size:11)).foregroundStyle(Theme.muted) }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:12)) } }
                }
            }
            if pair.discoveryFailed { Text(L("无法发现局域网设备。请检查本地网络权限，或使用配对码手动填写地址。","Local discovery is unavailable. Check Local Network permission, or enter an address using pairing code.")).font(.system(size:12)).foregroundStyle(.orange) }
            if !pair.status.isEmpty { HStack { if pair.busy { ProgressView() }; Text(pair.status).font(.system(size:13)) }.accessibilityIdentifier("pairingStatus") }
        } footer: {
            HStack {
                Button(L("取消","Cancel")) { dismiss() }.buttonStyle(AppButton())
                if pair.paired {
                    Button(L("连接设备","Connect device")) { model.hostBinding().wrappedValue=pair.host; model.portBinding().wrappedValue=pair.connectPort; dismiss(); model.connect() }.buttonStyle(AppButton(primary:true)).disabled(Int(pair.connectPort).map { !(1...65535).contains($0) } ?? true).accessibilityIdentifier("connectPaired")
                } else if !pair.qr {
                    Button(L("配对","Pair")) { pair.localName=model.localName; pair.pairCode() }.buttonStyle(AppButton(primary:true)).disabled(pair.busy).accessibilityIdentifier("pairCodeConfirm")
                }
            }
        }
        .onAppear { pair.host=model.host; pair.connectPort=""; pair.localName=model.localName; pair.start() }
        .onChange(of:model.localName) { pair.localName=$0 }
        .onDisappear { pair.stop() }
        .sheet(isPresented:$settings) { ApplicationSettings(model:model).presentationDetents([.large]) }
    }
    private func mode(_ title: String, _ qr: Bool) -> some View { Button(title) { pair.switchMode(qr) }.buttonStyle(AppButton(primary:pair.qr == qr)).accessibilityIdentifier(qr ? "pairModeQR" : "pairModeCode") }
}
