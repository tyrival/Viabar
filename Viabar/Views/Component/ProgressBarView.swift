import SwiftUI

struct ProgressBarView: View {
    let progress: Double // 0.0 ... 1.0
    var showLabel: Bool = true
    var height: CGFloat = 6

    private var fillColor: Color {
        if progress >= 1.0 {
            return ViabarColor.success
        } else if progress > 0 {
            return ViabarColor.primary
        } else {
            return .gray.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(.quaternary)
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(fillColor)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * progress)))
                }
            }
            .frame(height: height)

            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ProgressBarView(progress: 0.0)
        ProgressBarView(progress: 0.25)
        ProgressBarView(progress: 0.50)
        ProgressBarView(progress: 0.675)
        ProgressBarView(progress: 1.0)
        ProgressBarView(progress: 0.675, showLabel: false, height: 4)
    }
    .padding()
    .frame(width: 260)
}
