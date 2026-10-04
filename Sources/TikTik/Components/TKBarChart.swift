import Charts
import SwiftUI
import TikTikCore

/// shadcn-style bar chart of active time per bucket, with a hover tooltip.
struct TKBarChart: View {
    @Environment(\.palette) private var palette
    @State private var hoveredIndex: Int?
    @State private var hoverX: CGFloat = 0

    let buckets: [UsageBucket]
    let title: String
    let unitLabel: String
    /// Indices of buckets that get an x-axis label.
    let tickIndices: [Int]
    var height: CGFloat = 64

    var body: some View {
        TKCard(padding: EdgeInsets(top: Space.s2_5, leading: Space.s3, bottom: Space.s2, trailing: Space.s3)) {
            VStack(alignment: .leading, spacing: Space.s1_5) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("per \(unitLabel)")
                }
                .textStyle(.label)
                chart
            }
        }
    }

    private var axis: ChartYScale { ChartYScale(maxSeconds: buckets.map(\.active).max() ?? 0) }

    private var chart: some View {
        let axis = self.axis
        let tickLabels = tickIndices.compactMap { buckets.indices.contains($0) ? buckets[$0].label : nil }
        let axisLabels = Dictionary(buckets.map { ($0.label, $0.axisLabel) }, uniquingKeysWith: { first, _ in first })
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("Bucket", bucket.label),
                y: .value("Minutes", min(bucket.active, axis.maxSeconds) / 60)
            )
            .foregroundStyle(hoveredIndex == bucket.index ? palette.primary.opacity(0.7) : palette.primary)
            .cornerRadius(buckets.count > 20 ? 1.5 : 3)
        }
        .chartYScale(domain: 0...(axis.maxSeconds / 60))
        .chartXScale(domain: buckets.map(\.label))
        .chartYAxis {
            AxisMarks(position: .leading, values: axis.tickMinutes) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: Size.border, dash: [3, 3]))
                    .foregroundStyle(palette.border)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(ChartYScale.label(minutes: minutes)).textStyle(.axis)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: tickLabels) { value in
                AxisValueLabel(centered: true) {
                    if let label = value.as(String.self) {
                        Text(axisLabels[label] ?? label).textStyle(.axis)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plotFrame = proxy.plotFrame else { return }
                            let origin = geometry[plotFrame].origin
                            if let label: String = proxy.value(atX: location.x - origin.x) {
                                hoveredIndex = buckets.first { $0.label == label }?.index
                                hoverX = location.x
                            }
                        case .ended:
                            hoveredIndex = nil
                        }
                    }
                if let index = hoveredIndex, buckets.indices.contains(index) {
                    let bucket = buckets[index]
                    TKTooltipBubble(text: "\(bucket.label) · \(DurationFormat.short(bucket.active))")
                        .position(x: min(max(hoverX, 60), geometry.size.width - 60), y: 6)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: height)
    }
}

/// A "nice" y-axis: maximum and three gridlines (0, half, max) in round units.
struct ChartYScale {
    let maxSeconds: TimeInterval
    let tickMinutes: [Double]

    init(maxSeconds raw: TimeInterval) {
        let minutes = raw / 60
        // Candidate maxima in minutes: 15m, 30m, 1h, 2h, 4h, 6h, 8h, 10h, 12h, 16h, 24h, then multiples of 10h.
        let steps: [Double] = [15, 30, 60, 120, 240, 360, 480, 600, 720, 960, 1440]
        let top = steps.first { $0 >= minutes } ?? (ceil(minutes / 600) * 600)
        maxSeconds = top * 60
        tickMinutes = top <= 15 ? [0, top] : [0, top / 2, top]
    }

    static func label(minutes: Double) -> String {
        if minutes == 0 { return "0" }
        if minutes >= 60, minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60))h" }
        if minutes >= 60 { return String(format: "%.1fh", minutes / 60) }
        return "\(Int(minutes))m"
    }
}
