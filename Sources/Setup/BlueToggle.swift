import SwiftUI

struct BlueToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill(isOn ? Theme.accent : Color.secondary.opacity(0.25))
                    .frame(width: 86, height: 38)
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    .frame(width: 30, height: 30)
                    .offset(x: isOn ? 24 : -24)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
            }
        }
        .buttonStyle(.plain)
    }
}
