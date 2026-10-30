import SwiftUI

extension View {
    func zebraRowBackground(_ index: Int) -> some View {
        let color = index.isMultiple(of: 2)
            ? Color.clear
            : Color.primary.opacity(0.05)
        return listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
        )
    }

    func detailHeaderScrollTracking(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        } action: { _, offset in
            onChange(offset)
        }
    }

    func detailListSafeAreaHeader<Header: View>(
        isCollapsed: Bool,
        @ViewBuilder _ header: () -> Header
    ) -> some View {
        scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .top, alignment: .leading, spacing: 0) {
                if !isCollapsed {
                    header()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 10)
                }
            }
    }

    func editorSurface(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(.thinMaterial))
            .overlay(shape.stroke(.quaternary.opacity(0.5), lineWidth: 1))
            .clipShape(shape)
    }

    func detailCard(cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(.ultraThinMaterial))
            .overlay(shape.stroke(.quaternary.opacity(0.45), lineWidth: 1))
            .clipShape(shape)
    }
}
