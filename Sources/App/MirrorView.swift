import SwiftUI

struct MirrorView: View {
    @ObservedObject var model: AppModel
    let showSettings: () -> Void, showText: () -> Void
    private func icon(_ symbol: String, name: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action:action) { Image(systemName:symbol).font(.system(size:19,weight:.medium)).frame(width:42,height:42).foregroundStyle(id == "keyboard" && model.keyboardVisible ? Theme.accent : .white).background(Theme.card).clipShape(RoundedRectangle(cornerRadius:10)) }.accessibilityLabel(name).accessibilityIdentifier(id)
    }
    private var back: some View { icon("chevron.left",name:L("返回","Back"),id:"navBack") { model.key(4) } }
    private var home: some View { icon("house",name:"Home",id:"navHome") { model.key(3) } }
    private var recent: some View { icon("square.on.square",name:L("最近任务","Recents"),id:"navRecent") { model.key(187) } }
    private var keyboard: some View { icon("keyboard",name:L("虚拟键盘","Virtual keyboard"),id:"keyboard") { model.toggleKeyboard() } }
    private var settings: some View { icon("gearshape",name:L("远控设置","Remote settings"),id:"runtimeSettings",action:showSettings) }
    private var status: some View {
        Text((model.ready ? "● " : "") + model.status + (model.deviceName.isEmpty ? "" : "\n"+model.deviceName))
            .font(.system(size:10)).foregroundStyle(model.ready ? Theme.accent : Theme.muted).multilineTextAlignment(.center).lineLimit(5).minimumScaleFactor(0.6)
            .accessibilityIdentifier("connectionState").accessibilityValue(model.ready ? "ready" : "connecting")
    }
    private var canvas: some View {
        RemoteCanvas(model:model).clipped().overlay {
            if !model.ready { VStack(spacing:10) { ProgressView().tint(Theme.accent); Text(L("正在连接，请在远端允许调试","Connecting · allow debugging on Android")).font(.system(size:11)).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }.padding() }
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing:0) {
                if model.notice != nil { NoticeBanner(model:model).padding(.horizontal,10).padding(.bottom,6) }
                if landscape {
                    HStack(spacing:6) {
                        status.frame(width:44).padding(.vertical,22)
                        canvas.frame(maxWidth:.infinity,maxHeight:.infinity)
                        if model.keyboardVisible && !model.profile.viewOnly { VirtualKeyboard(model:model,showText:showText,compact:true).frame(width:min(380,geometry.size.width*0.45)) }
                        VStack(spacing:7) { Spacer(minLength:0); if model.profile.showNavigation { back; home; recent }; keyboard.disabled(model.profile.viewOnly); settings; Spacer(minLength:0) }.padding(.vertical,8)
                    }.padding(.horizontal,5)
                } else {
                    canvas.frame(maxWidth:.infinity,maxHeight:.infinity)
                    if model.keyboardVisible && !model.profile.viewOnly { VirtualKeyboard(model:model,showText:showText).padding(.horizontal,4).padding(.top,4) }
                    ZStack {
                        HStack { status.frame(width:74); Spacer(); HStack(spacing:4) { keyboard.disabled(model.profile.viewOnly); settings } }
                        if model.profile.showNavigation { HStack(spacing:4) { back; home; recent } }
                    }.frame(height:50).padding(.horizontal,6).padding(.top,3)
                }
            }
            .padding(.top,landscape ? 0 : max(0,24-geometry.safeAreaInsets.top))
            .onAppear { model.orientation(landscape) }
            .onChange(of:landscape) { model.orientation($0) }
        }.background(Color.black)
    }
}
