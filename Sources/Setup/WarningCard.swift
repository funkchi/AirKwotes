import SwiftUI

struct WarningCard: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.white)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.95))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.warning)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
