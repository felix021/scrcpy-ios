import SwiftUI

private struct ScrollEndPosition: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The cue occupies the bottom of the scroll viewport, above the fixed actions.
/// It disappears only when the last setting has actually entered that viewport.
struct SettingsScroll<Content: View, Footer: View>: View {
    var cueID = "settingsScrollHint"
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer
    @State private var coordinate = UUID()
    @State private var bottom: CGFloat = 0
    var body: some View {
        ScrollViewReader { scroll in
            VStack(spacing:0) {
                GeometryReader { viewport in
                    ScrollView {
                        VStack(spacing:0) {
                            content()
                            Color.clear.frame(height:12).id("settings.end")
                                .background(GeometryReader { marker in Color.clear.preference(key:ScrollEndPosition.self,value:marker.frame(in:.named(coordinate)).maxY) })
                        }
                    }
                    .coordinateSpace(name:coordinate)
                    .scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(ScrollEndPosition.self) { bottom = $0 }
                    .overlay(alignment:.bottom) {
                        if bottom > viewport.size.height + 2 {
                            ZStack(alignment:.bottom) {
                                LinearGradient(colors:[Theme.background.opacity(0),Theme.background.opacity(0.94),Theme.background],startPoint:.top,endPoint:.bottom).allowsHitTesting(false)
                                Button { withAnimation(.easeInOut(duration:0.3)) { scroll.scrollTo("settings.end",anchor:.bottom) } } label: {
                                    Label(L("上滑查看更多设置","Swipe up for more settings"),systemImage:"chevron.down")
                                        .font(.system(size:11,weight:.medium)).foregroundStyle(Theme.accent)
                                        .padding(.horizontal,14).padding(.vertical,9).background(Theme.card.opacity(0.94)).clipShape(Capsule())
                                }.buttonStyle(.plain).padding(.bottom,6).accessibilityIdentifier(cueID)
                            }.frame(height:56)
                        }
                    }
                }
                footer().frame(maxWidth:650).frame(maxWidth:.infinity)
                    .padding(.top,10).padding(.bottom,10).background(.ultraThinMaterial)
            }
        }
    }
}
