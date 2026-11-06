import SwiftUI

/// Subscription limits drawn at the end of the session row: a small black silhouette, like
/// a session mascot, with a dial split in two halves (top: 5 hours, bottom: week).
struct UsageGaugeView: View {
  let limits: ClaudeUsageLimits
  /// Screen edge the gauge sticks to; empty when it floats.
  let edges: MascotAttachmentEdges

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasAppeared = false

  private static let dialDiameter: CGFloat = 26
  private static let arcWidth: CGFloat = 3.5
  /// Trim fraction left empty on each side of a half, where the two halves meet.
  private static let arcGap: CGFloat = 0.035

  var body: some View {
    // Resets and the countdown move with time; a minute is fine-grained enough.
    TimelineView(.everyMinute) { context in
      content(at: context.date)
    }
    .onAppear {
      withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.15).delay(0.1)) {
        hasAppeared = true
      }
    }
  }

  private func content(at date: Date) -> some View {
    let frames = SessionMascotView.frames(for: edges, isAsleep: false)
    let dock = SessionMascotDock(edges)
    let fiveHour = Gauge(window: limits.fiveHour, duration: ClaudeUsageLimits.fiveHourDuration, at: date)
    let sevenDay = Gauge(window: limits.sevenDay, duration: ClaudeUsageLimits.sevenDayDuration, at: date)
    let summary = helpText(fiveHour: fiveHour, sevenDay: sevenDay)

    return ZStack(alignment: .topLeading) {
      silhouette(fiveHour: fiveHour, sevenDay: sevenDay)
        .position(inSessionWindow: frames.body)
      label(at: date)
        .frame(width: frames.label.width, height: frames.label.height, alignment: dock.labelAlignment)
        .position(inSessionWindow: frames.label)
    }
    .frame(width: SessionMascotView.windowSize.width, height: SessionMascotView.windowSize.height)
    .animation(reduceMotion ? nil : .spring(duration: 0.6), value: fiveHour)
    .animation(reduceMotion ? nil : .spring(duration: 0.6), value: sevenDay)
    .help(summary)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(summary)
  }

  private func silhouette(fiveHour: Gauge, sevenDay: Gauge) -> some View {
    let frame = SessionMascotView.silhouetteFrameSize
    let alert = max(fiveHour.level, sevenDay.level) == .critical

    return ZStack {
      SessionMascotView.silhouette(for: edges)
        .fill(.black)
        // Same signal as a session halo: the limit is about to stop Claude.
        .shadow(color: alert ? .red.opacity(0.75) : .clear, radius: alert ? 4 : 0)
      ZStack {
        halfArc(fiveHour, isTop: true, hue: .fiveHour)
        halfArc(sevenDay, isTop: false, hue: .sevenDay)
        eyes
      }
      .frame(width: Self.dialDiameter, height: Self.dialDiameter)
    }
    .frame(width: frame.width, height: frame.height)
  }

  /// One half of the dial, filled from the left: the top half runs clockwise and the bottom
  /// half counterclockwise, so both read left to right.
  private func halfArc(_ gauge: Gauge, isTop: Bool, hue: Hue) -> some View {
    let color = hue.color(for: gauge.level)
    let gap = Self.arcGap
    let fill = (0.5 - 2 * gap) * (hasAppeared ? CGFloat(gauge.used) : 0)
    // A circle's trim starts at 3 o'clock and runs clockwise on screen: 0.5 is 9 o'clock.
    let track: (CGFloat, CGFloat) = isTop ? (0.5 + gap, 1 - gap) : (gap, 0.5 - gap)
    let filled: (CGFloat, CGFloat) = isTop ? (0.5 + gap, 0.5 + gap + fill) : (0.5 - gap - fill, 0.5 - gap)
    let style = StrokeStyle(lineWidth: Self.arcWidth, lineCap: .round)

    return ZStack {
      Circle()
        .trim(from: track.0, to: track.1)
        .stroke(color.opacity(0.22), style: style)
      Circle()
        .trim(from: filled.0, to: filled.1)
        .stroke(color, style: style)
        .shadow(color: color.opacity(0.6), radius: 1.5)
        // A round cap would still draw a dot for an empty fill.
        .opacity(fill > 0 ? 1 : 0)
    }
  }

  /// Timi's eyes in the middle of the dial, so the gauge reads as one of the family.
  private var eyes: some View {
    HStack(spacing: 4) {
      Capsule().frame(width: 2.5, height: 7)
      Capsule().frame(width: 2.5, height: 7)
    }
    .foregroundStyle(.white.opacity(0.9))
    .shadow(color: .white.opacity(0.5), radius: 1.5)
  }

  private func label(at date: Date) -> some View {
    Group {
      if let resetsAt = limits.fiveHour?.resetsAt, resetsAt > date {
        Text("\(Image(systemName: "arrow.counterclockwise")) \(Self.countdown(until: resetsAt, from: date))")
      } else {
        Text("Limites")
      }
    }
    .font(.system(size: 10, weight: .semibold))
    .monospacedDigit()
    .sessionLabelCapsule()
  }

  private func helpText(fiveHour: Gauge, sevenDay: Gauge) -> String {
    [
      Self.describe(limits.fiveHour, gauge: fiveHour, title: "Limite de 5 h", resetFormat: .dateTime.hour().minute()),
      Self.describe(limits.sevenDay, gauge: sevenDay, title: "Limite hebdomadaire", resetFormat: .dateTime.weekday(.wide).hour().minute()),
    ].joined(separator: "\n")
  }

  private static func describe(
    _ window: ClaudeUsageLimits.Window?,
    gauge: Gauge,
    title: String,
    resetFormat: Date.FormatStyle
  ) -> String {
    guard let window else { return "\(title) : inconnue" }
    let used = "\(Int((gauge.used * 100).rounded())) % utilisés"
    guard gauge.elapsed != nil else { return "\(title) : \(used), réinitialisée" }
    return "\(title) : \(used), réinitialisation \(window.resetsAt.formatted(resetFormat))"
  }

  /// Short time left before `date`: "42 min", "2 h 05", "3 j".
  nonisolated static func countdown(until date: Date, from now: Date) -> String {
    let minutes = max(0, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    if minutes < 60 { return "\(minutes) min" }
    if minutes < 24 * 60 { return String(format: "%d h %02d", minutes / 60, minutes % 60) }
    return "\(minutes / (24 * 60)) j"
  }
}

/// What one ring shows at a given instant.
private struct Gauge: Equatable {
  let used: Double
  let elapsed: Double?
  let level: ClaudeUsageLimits.Level

  init(window: ClaudeUsageLimits.Window?, duration: TimeInterval, at date: Date) {
    used = window?.usedFraction(at: date) ?? 0
    elapsed = window?.elapsedFraction(at: date, duration: duration)
    level = ClaudeUsageLimits.Level(fraction: used)
  }
}

private enum Hue {
  case fiveHour, sevenDay

  func color(for level: ClaudeUsageLimits.Level) -> Color {
    switch level {
    case .critical: Color(red: 1, green: 0.32, blue: 0.3)
    case .warning: .orange
    case .normal:
      switch self {
      case .fiveHour: Color(red: 0.35, green: 0.92, blue: 0.55)
      case .sevenDay: Color(red: 0.3, green: 0.75, blue: 1)
      }
    }
  }
}

#Preview {
  let now = Date()
  let samples: [(Double, Double, MascotAttachmentEdges)] = [(18, 6, []), (62, 41, .bottom), (81, 55, .left), (96, 88, .top)]

  HStack(spacing: 8) {
    ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
      UsageGaugeView(
        limits: ClaudeUsageLimits(
          fiveHour: .init(usedPercentage: sample.0, resetsAt: now.addingTimeInterval(2 * 3600)),
          sevenDay: .init(usedPercentage: sample.1, resetsAt: now.addingTimeInterval(3 * 86_400))
        ),
        edges: sample.2
      )
      .border(.secondary.opacity(0.3))
    }
  }
  .padding()
}
