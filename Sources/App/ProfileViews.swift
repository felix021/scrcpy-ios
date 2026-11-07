import SwiftUI
import ScrcpyCore

struct SaveProfile: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focused: Bool
    var body: some View {
        SheetPanel(title:L("保存连接配置","Save connection profile"),subtitle:L("保存地址、画面与全部控制设置，同名配置会更新。","Save the address, video and control settings. An existing name will be updated."),model:model) {
            TextField(L("配置名称","Profile name"),text:$name).textInputAutocapitalization(.never).padding(14).background(Theme.field).clipShape(RoundedRectangle(cornerRadius:13)).focused($focused).accessibilityIdentifier("profileName")
        } footer: { HStack { Button(L("取消","Cancel")) { dismiss() }.buttonStyle(AppButton()); Button(L("保存","Save")) { if model.save(name:name) { dismiss() } }.buttonStyle(AppButton(primary:true)).accessibilityIdentifier("saveConfirm") } }
        .onAppear { name=model.profile.name; focused=true }
    }
}
struct ProfilePicker: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var deleting: Profile?
    var body: some View {
        SheetPanel(title:L("切换连接配置","Switch connection profile"),subtitle:L("选择后确认切换，删除需要再次确认。","Select a profile and confirm. Deletion requires confirmation."),model:model) {
            if model.profiles.isEmpty { Text(L("尚未保存配置","No saved profiles")).font(.system(size:14)).foregroundStyle(Theme.muted).padding(.vertical,16) }
            ForEach(model.profiles) { profile in
                Button { selected=profile.id } label: { HStack(spacing:12) { VStack(alignment:.leading,spacing:6) { Text(profile.name).font(.system(size:16,weight:.semibold)).foregroundStyle(.white); Text("\(profile.host):\(profile.port)").font(.system(size:12)).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName:selected==profile.id ? "checkmark.circle.fill" : "circle").foregroundStyle(selected==profile.id ? Theme.accent : Theme.muted) }.padding(15).background(selected==profile.id ? Theme.accent.opacity(0.12) : Theme.field).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(selected==profile.id ? Theme.accent.opacity(0.5) : Color.clear)).contentShape(Rectangle()) }.accessibilityIdentifier("profile."+profile.name)
            }
        } footer: {
            HStack { Button(L("删除","Delete")) { deleting=model.profiles.first { $0.id==selected } }.buttonStyle(AppButton(danger:true)).disabled(selected==nil).accessibilityIdentifier("deleteProfile")
                Button(L("取消","Cancel")) { dismiss() }.buttonStyle(AppButton())
                Button(L("使用配置","Use profile")) { if let profile=model.profiles.first(where:{$0.id==selected}) { model.apply(profile);dismiss() } }.buttonStyle(AppButton(primary:true)).disabled(selected==nil).accessibilityIdentifier("useProfile") }
        }
        .overlay { if let deleting { ConfirmCard(title:L("删除配置？","Delete profile?"),message:deleting.name,actionTitle:L("确认删除","Delete"),cancel:{self.deleting=nil},action:{model.delete(deleting);selected=nil;self.deleting=nil}) } }
        .onAppear { selected=model.profiles.contains(where:{$0.id==model.profile.id}) ? model.profile.id : nil }
    }
}
