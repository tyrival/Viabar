import SwiftUI

struct SearchTargetHighlight: ViewModifier {
    let triggerID: UUID?
    let isActive: Bool
    let cornerRadius: CGFloat

    @State private var opacity = 0.0

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.orange.opacity(opacity), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .task(id: triggerID) {
                guard isActive, triggerID != nil else {
                    opacity = 0
                    return
                }

                opacity = 1
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    opacity = 0.2
                }

                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }

                withAnimation(.easeOut(duration: 0.2)) {
                    opacity = 0
                }
            }
    }
}

extension View {
    func searchTargetHighlight(
        triggerID: UUID?,
        isActive: Bool,
        cornerRadius: CGFloat = 8
    ) -> some View {
        modifier(
            SearchTargetHighlight(
                triggerID: triggerID,
                isActive: isActive,
                cornerRadius: cornerRadius
            )
        )
    }
}
