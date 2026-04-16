import SwiftUI

struct TabBarView: View {
    @ObservedObject var tabState: TabState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabState.visibleTabs) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        tabState.activeTab = tab
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(tabState.activeTab == tab ? 1.0 : 0.35))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }
}
