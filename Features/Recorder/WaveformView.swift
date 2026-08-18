import SwiftUI

/// 电平波形：按当前电平渲染竖条，时间驱动的确定性动画。
struct WaveformView: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<24, id: \.self) { index in
                    Capsule()
                        .fill(AppTheme.accent)
                        .frame(width: 3, height: barHeight(index: index, time: context.date))
                }
            }
            .frame(height: 52)
        }
    }

    private func barHeight(index: Int, time: Date) -> CGFloat {
        let base = 6 + CGFloat((index * 7) % 13)
        let pulse = CGFloat(level) * 34
        let phase = CGFloat((Int(time.timeIntervalSinceReferenceDate * 12) + index * 3) % 8) / 8
        return base + pulse * phase
    }
}
