import Core
import SwiftUI

public struct StatusDot: View {
    let status: NodeStatus
    let palette: AgentTracePalette
    let size: CGFloat

    public init(status: NodeStatus, palette: AgentTracePalette, size: CGFloat = 8) {
        self.status = status
        self.palette = palette
        self.size = size
    }

    public var body: some View {
        Circle()
            .fill(palette.color(for: status))
            .overlay(
                Circle()
                    .stroke(palette.color(for: status).opacity(0.35), lineWidth: max(1, size / 6))
                    .blur(radius: max(0.6, size / 10))
            )
            .frame(width: size, height: size)
    }
}

public struct DividerLine: View {
    let palette: AgentTracePalette

    public init(palette: AgentTracePalette) {
        self.palette = palette
    }

    public var body: some View {
        DottedDivider(palette: palette, vertical: true)
            .frame(width: 1)
    }
}

public struct HorizontalDividerLine: View {
    let palette: AgentTracePalette

    public init(palette: AgentTracePalette) {
        self.palette = palette
    }

    public var body: some View {
        DottedDivider(palette: palette, vertical: false)
            .frame(height: 1)
    }
}

private struct DottedDivider: View {
    let palette: AgentTracePalette
    let vertical: Bool

    var body: some View {
        Canvas { context, size in
            var path = Path()

            if vertical {
                path.move(to: CGPoint(x: size.width / 2, y: 0))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            } else {
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            }

            context.stroke(
                path,
                with: .color(palette.borderStrong.opacity(0.82)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 6])
            )
        }
    }
}

public struct StageBackground: View {
    let palette: AgentTracePalette

    public init(palette: AgentTracePalette) {
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            palette.stage

            BlueprintGrid(lineColor: palette.gridLine)
        }
        .ignoresSafeArea()
    }
}

private struct BlueprintGrid: View {
    let lineColor: Color

    var body: some View {
        Canvas { context, size in
            let horizontalStep: CGFloat = 96
            let verticalStep: CGFloat = 64
            var path = Path()

            stride(from: CGFloat.zero, through: size.width, by: horizontalStep).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }

            stride(from: CGFloat.zero, through: size.height, by: verticalStep).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            context.stroke(path, with: .color(lineColor), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
