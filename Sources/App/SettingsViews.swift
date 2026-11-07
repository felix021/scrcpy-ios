import SwiftUI

private struct LanguageRow: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack { Text(L("界面语言","Interface language")); Spacer(); Menu {
            Button(L("跟随系统","Follow system")) { model.language="system" }; Button("简体中文") { model.language="zh" }; Button("English") { model.language="en" }
        } label: { HStack { Text(model.language == "system" ? L("跟随系统","Follow system") : model.language == "zh" ? "简体中文" : "English"); Image(systemName:"chevron.down").font(.system(size:10)) }.font(.system(size:13,weight:.semibold)).padding(12).background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius:12)) }.accessibilityIdentifier("languagePicker") }
    }
}
struct ApplicationSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return L("版本 ","Version ") + version + " (" + build + ")"
    }
    var body: some View {
        SheetPanel(title:L("设置","Settings"),subtitle:L("语言与应用信息","Language and app information"),model:model) {
            LanguageRow(model:model); Divider().padding(.vertical,5)
            Text(L("关于","About")).font(.system(size:12,weight:.semibold)).foregroundStyle(Theme.muted)
            HStack(spacing:12) { Image("AppMark").resizable().frame(width:48,height:48).clipShape(RoundedRectangle(cornerRadius:12)); VStack(alignment:.leading,spacing:5) { Text(L("远控 · scrcpy","Remote · scrcpy")).font(.system(size:20,weight:.bold)); Text(L("用 iPhone 或 iPad 控制 Android。","Control Android from iPhone or iPad.")).font(.system(size:12)).foregroundStyle(Theme.muted) } }
            Text(versionText).font(.system(size:13)).accessibilityIdentifier("appVersion")
            Text(L("开源许可 · GPL-3.0","License · GPL-3.0")).font(.system(size:12)).foregroundStyle(Theme.muted)
            Link(destination:URL(string:"https://github.com/felix021/scrcpy-ios")!) { VStack(alignment:.leading,spacing:5) { Label(L("代码仓库","Code repository"),systemImage:"arrow.up.right").font(.system(size:14,weight:.semibold)); Text("github.com/felix021/scrcpy-ios").font(.system(size:11)).foregroundStyle(Theme.muted) }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:14)) }.accessibilityIdentifier("repository")
        } footer: { Button(L("完成","Done")) { dismiss() }.buttonStyle(AppButton(primary:true)).accessibilityIdentifier("settingsDone") }
    }
}
struct RuntimeSettings: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirm = false
    var body: some View {
        SheetPanel(title:L("远控设置","Remote settings"),subtitle:L("修改立即生效，并记住当前连接配置。","Changes take effect immediately and are remembered for this profile."),model:model) {
            HStack { Button { model.rotate(right:false) } label: { Label(L("向左旋转","Rotate left"),systemImage:"rotate.left") }.accessibilityIdentifier("rotateLeft"); Button { model.rotate(right:true) } label: { Label(L("向右旋转","Rotate right"),systemImage:"rotate.right") }.accessibilityIdentifier("rotateRight") }.buttonStyle(AppButton()).disabled(model.profile.viewOnly)
            Toggle(L("展示虚拟按键","Show navigation keys"),isOn:model.option(\.showNavigation)).accessibilityIdentifier("opt.navigation")
            Toggle(L("播放远端声音","Play remote audio"),isOn:model.option(\.forwardAudio)).accessibilityIdentifier("opt.audio")
            Toggle(L("转发本机麦克风","Forward local microphone"),isOn:model.option(\.forwardMic)).disabled(model.profile.viewOnly).accessibilityIdentifier("opt.microphone")
            Toggle(L("充电时保持远端唤醒","Keep remote awake while charging"),isOn:model.option(\.stayAwake)).accessibilityIdentifier("opt.awake")
            Toggle(L("同步远端屏幕方向","Sync remote orientation"),isOn:model.option(\.syncRotation)).disabled(model.profile.viewOnly).accessibilityIdentifier("opt.rotation")
            Toggle(L("展示完整键盘","Show full keyboard"),isOn:Binding(get:{model.keyboardVisible},set:{_ in model.toggleKeyboard()})).disabled(model.profile.viewOnly).accessibilityIdentifier("opt.keyboard")
            Text(L("关闭方向同步或保持唤醒会恢复远端原设置；仅观看不发送控制、麦克风与方向变更。","Turning off orientation sync or keep-awake restores the original settings. View-only does not send input, microphone or rotation changes.")).font(.system(size:11)).foregroundStyle(Theme.muted)
            LanguageRow(model:model)
        } footer: {
            HStack { Button(L("断开连接","Disconnect")) { confirm=true }.buttonStyle(AppButton(danger:true)).accessibilityIdentifier("disconnect"); Button(L("完成","Done")) { dismiss() }.buttonStyle(AppButton(primary:true)).accessibilityIdentifier("runtimeDone") }
        }
        .overlay { if confirm { ConfirmCard(title:L("断开连接？","Disconnect?"),message:L("确认结束当前远控会话。","End this remote-control session?"),actionTitle:L("确认断开","Disconnect"),cancel:{confirm=false},action:{dismiss();model.disconnect()}) } }
    }
}
struct TextEditorSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @FocusState private var focused: Bool
    var body: some View {
        SheetPanel(title:L("输入文字","Enter text"),subtitle:L("使用远端剪贴板粘贴，单次最多 64 KiB。","Pastes through the remote clipboard, up to 64 KiB."),model:model) {
            TextEditor(text:$value).font(.system(size:17)).frame(minHeight:120).padding(10).scrollContentBackground(.hidden).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:13)).focused($focused).accessibilityIdentifier("textEditor")
        } footer: { HStack { Button(L("取消","Cancel")) { dismiss() }.buttonStyle(AppButton()); Button(L("发送","Send")) {
            guard value.utf8.count <= 65536 else { model.notice=L("单次文字不能超过 64 KiB","Text cannot exceed 64 KiB");return }; model.text(value); dismiss()
        }.buttonStyle(AppButton(primary:true)).accessibilityIdentifier("sendText") } }
        .onAppear { focused=true }
    }
}
