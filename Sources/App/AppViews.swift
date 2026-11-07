import SwiftUI
import ScrcpyCore

struct Theme {
    static let background = Color(red:0.051,green:0.078,blue:0.106)
    static let card = Color(red:0.09,green:0.137,blue:0.176)
    static let field = Color(red:0.055,green:0.098,blue:0.129)
    static let accent = Color(red:0.502,green:0.886,blue:0.765)
    static let muted = Color(red:0.588,green:0.667,blue:0.725)
}
struct AppButton: ButtonStyle {
    var primary = false, danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size:15,weight:.semibold)).foregroundStyle(primary ? Theme.background : danger ? Color(red:1,green:0.7,blue:0.66) : Color.white)
            .frame(maxWidth:.infinity,minHeight:44).padding(.horizontal,10)
            .background(primary ? Theme.accent : danger ? Color(red:0.21,green:0.16,blue:0.19) : Color.white.opacity(0.065))
            .clipShape(RoundedRectangle(cornerRadius:13)).opacity(configuration.isPressed ? 0.72 : 1)
    }
}
struct AppCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { VStack(alignment:.leading,spacing:12,content:content).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Theme.card).clipShape(RoundedRectangle(cornerRadius:22)) }
}
struct NoticeBanner: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let message = model.notice {
            HStack(alignment:.top,spacing:8) { Image(systemName:"info.circle"); Text(message).font(.system(size:12)); Spacer(minLength:0); Button { model.notice = nil } label: { Image(systemName:"xmark").padding(3) } }
                .foregroundStyle(Color(red:1,green:0.78,blue:0.71)).padding(12).background(Color(red:0.20,green:0.14,blue:0.16)).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier("notice")
        }
    }
}
struct FormField: View {
    let title: String
    @Binding var text: String
    var id: String
    var numeric = true
    var body: some View {
        VStack(alignment:.leading,spacing:7) {
            Text(title).font(.system(size:12)).foregroundStyle(Theme.muted)
            TextField(title,text:$text).keyboardType(numeric ? .numberPad : .URL).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(size:16,design:.rounded)).padding(12).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:12)).accessibilityIdentifier(id)
        }
    }
}
struct SheetPanel<Content: View, Footer: View>: View {
    let title: String, subtitle: String
    @ObservedObject var model: AppModel
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) { Text(title).font(.system(size:23,weight:.bold)); if !subtitle.isEmpty { Text(subtitle).font(.system(size:12)).foregroundStyle(Theme.muted) }; NoticeBanner(model:model); content() }.padding(22).frame(maxWidth:.infinity,alignment:.leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge:.bottom,spacing:0) { footer().padding(.horizontal,22).padding(.top,10).padding(.bottom,12).background(.ultraThinMaterial) }
        .background(Theme.card.opacity(0.88)).preferredColorScheme(.dark).presentationDragIndicator(.visible)
    }
}
extension View {
    @ViewBuilder func transparentSheet() -> some View {
        if #available(iOS 16.4, *) { self.presentationBackground(.clear) } else { self }
    }
}
struct ConfirmCard: View {
    let title: String, message: String, actionTitle: String
    let cancel: () -> Void, action: () -> Void
    var body: some View {
        ZStack { Color.black.opacity(0.55).ignoresSafeArea(); VStack(alignment:.leading,spacing:16) {
            Text(title).font(.system(size:21,weight:.bold)); Text(message).font(.system(size:14)).foregroundStyle(Theme.muted)
            HStack { Button(L("取消","Cancel"),action:cancel).buttonStyle(AppButton()); Button(actionTitle,action:action).buttonStyle(AppButton(danger:true)).accessibilityIdentifier("confirmAction") }
        }.padding(22).background(Theme.card).clipShape(RoundedRectangle(cornerRadius:22)).padding(24).frame(maxWidth:440) }
    }
}

@main struct ScrcpyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene { WindowGroup { RootView(model:model).preferredColorScheme(.dark).tint(Theme.accent).environment(\.locale,model.effectiveLocale).onChange(of:phase) { if $0 == .background && model.active { model.disconnect(message:L("已离开远控界面，连接结束","Left the remote screen; connection closed")) } } } }
}
private struct FormBottom: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct FormHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
struct RootView: View {
    @ObservedObject var model: AppModel
    @State private var appSettings = false
    @State private var profiles = false
    @State private var save = false
    @State private var runtime = false
    @State private var text = false
    @State private var formBottom: CGFloat = 0
    @State private var formHeight: CGFloat = 0
    var body: some View {
        Group {
            if model.active { MirrorView(model:model,showSettings:{runtime=true},showText:{text=true}) }
            else { form }
        }
        .background(Theme.background.ignoresSafeArea()).foregroundStyle(.white)
        .statusBar(hidden:model.active).persistentSystemOverlays(model.active ? .hidden : .automatic).defersSystemGestures(on:model.active ? .all : [])
        .sheet(isPresented:$appSettings) { ApplicationSettings(model:model).presentationDetents([.height(490),.large]) }
        .sheet(isPresented:$profiles) { ProfilePicker(model:model).presentationDetents([.medium,.large]) }
        .sheet(isPresented:$save) { SaveProfile(model:model).presentationDetents([.height(290),.medium]) }
        .sheet(isPresented:$runtime) { RuntimeSettings(model:model).presentationDetents([.medium,.large]).transparentSheet() }
        .sheet(isPresented:$text) { TextEditorSheet(model:model).presentationDetents([.medium,.large]) }
        .onChange(of:model.active) { if !$0 { runtime=false; text=false } }
    }
    private var form: some View {
        ScrollView {
            VStack(spacing:14) {
                HStack(alignment:.center,spacing:8) {
                    Text(L("远程控制","Remote control")).font(.system(size:24,weight:.bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("SCRCPY / iOS").font(.system(size:9,weight:.medium)).foregroundStyle(Theme.accent).lineLimit(1)
                    Spacer(minLength:0)
                    Button { appSettings=true } label: { Image(systemName:"gearshape").font(.system(size:21)).frame(width:40,height:40).background(Theme.card).clipShape(RoundedRectangle(cornerRadius:11)) }.accessibilityIdentifier("appSettings")
                }
                NoticeBanner(model:model)
                AppCard {
                    Text(model.profile.name.isEmpty ? L("连接配置","Connection profile") : model.profile.name).font(.system(size:12)).foregroundStyle(Theme.muted)
                    HStack { Button { profiles=true } label: { Label(L("切换配置","Switch profile"),systemImage:"chevron.down") }.buttonStyle(AppButton()).accessibilityIdentifier("profilePicker")
                        Button(L("保存配置","Save profile")) { save=true }.buttonStyle(AppButton()).accessibilityIdentifier("saveProfile") }
                    HStack(alignment:.bottom,spacing:10) {
                        FormField(title:L("设备 IP / 主机名","Device IP / hostname"),text:model.hostBinding(),id:"host",numeric:false)
                        FormField(title:L("ADB 端口","ADB port"),text:model.portBinding(),id:"port").frame(width:105)
                    }
                    Text(L("首次连接，请在 Android 上允许调试。","Allow debugging on Android when connecting for the first time.")).font(.system(size:11)).foregroundStyle(Theme.muted)
                }
                AppCard {
                    HStack { Text(L("画面与控制","Video and control")).font(.system(size:16,weight:.semibold)); Spacer(); Menu {
                        Button(L("省流","Economy")) { model.quality(0) }; Button(L("均衡","Balanced")) { model.quality(1) }; Button(L("高清","High quality")) { model.quality(2) }
                    } label: { HStack { Text(model.qualityName); Image(systemName:"chevron.down").font(.system(size:10)) }.font(.system(size:12,weight:.semibold)).padding(.horizontal,12).padding(.vertical,9).background(Color.white.opacity(0.06)).clipShape(Capsule()) }.accessibilityIdentifier("quality") }
                    HStack(spacing:10) { FormField(title:L("最长边 · px","Max edge · px"),text:$model.size,id:"maxSize"); FormField(title:L("码率 · Mbps","Bitrate · Mbps"),text:$model.bitrate,id:"bitrate") }
                    HStack(spacing:12) {
                        FormField(title:L("帧率上限","Max FPS"),text:$model.fps,id:"fps")
                        VStack(alignment:.leading,spacing:7) { Text(L("视频编码","Video codec")).font(.system(size:12)).foregroundStyle(Theme.muted); Menu { Button("H.264") { model.profile.codec="h264" }; Button("H.265") { model.profile.codec="h265" } } label: { HStack { Text(model.profile.codec == "h264" ? "H.264" : "H.265"); Spacer(); Image(systemName:"chevron.down") }.padding(12).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:12)) }.accessibilityIdentifier("codec") }.frame(maxWidth:.infinity)
                    }
                    Toggle(L("展示虚拟按键","Show navigation keys"),isOn:model.option(\.showNavigation))
                    Toggle(L("仅观看","View only"),isOn:model.option(\.viewOnly))
                    Divider().overlay(Theme.muted.opacity(0.15))
                    Toggle(L("播放远端声音","Play remote audio"),isOn:model.option(\.forwardAudio))
                    Toggle(L("转发本机麦克风","Forward local microphone"),isOn:model.option(\.forwardMic)).disabled(model.profile.viewOnly)
                    Toggle(L("同步远端屏幕方向","Sync remote orientation"),isOn:model.option(\.syncRotation)).disabled(model.profile.viewOnly)
                    Toggle(L("充电时保持远端唤醒","Keep remote awake while charging"),isOn:model.option(\.stayAwake))
                }.font(.system(size:14))
                Text(L("从远控画面边缘滑动：左右返回、底部 Home、顶部控制中心。iOS 版通过网络 ADB 连接。","Swipe inward at the remote picture edges: Back on either side, Home at the bottom, control center at the top. iOS connects over network ADB.")).font(.system(size:11)).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,4)
            }.padding(.horizontal,16).padding(.top,12).padding(.bottom,18).frame(maxWidth:650)
                .frame(maxWidth:.infinity)
                .background(GeometryReader { proxy in Color.clear.preference(key:FormBottom.self,value:proxy.frame(in:.named("configuration")).maxY) })
        }
        .coordinateSpace(name:"configuration")
        .background(GeometryReader { proxy in Color.clear.preference(key:FormHeight.self,value:proxy.size.height) })
        .onPreferenceChange(FormBottom.self) { formBottom = $0 }
        .onPreferenceChange(FormHeight.self) { formHeight = $0 }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge:.bottom,spacing:0) { VStack(spacing:4) {
            if formBottom > formHeight + 20 { Text(L("更多设置可上下滑动查看","Scroll to see more settings")).font(.system(size:10)).foregroundStyle(Theme.muted) }
            Button { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil); model.connect() } label: { HStack { Text(L("连接设备","Connect device")); Image(systemName:"arrow.right") }.font(.system(size:18,weight:.bold)) }.buttonStyle(AppButton(primary:true)).accessibilityIdentifier("connect")
        }.padding(.horizontal,16).padding(.top,12).padding(.bottom,8).background(.ultraThinMaterial)
            .overlay(alignment:.top) { LinearGradient(colors:[Theme.background.opacity(0),Theme.background.opacity(0.8)],startPoint:.top,endPoint:.bottom).frame(height:18).offset(y:-18).allowsHitTesting(false) } }
    }
}
