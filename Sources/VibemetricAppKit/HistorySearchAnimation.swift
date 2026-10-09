import AppKit
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

/// Illustrates discovery without implying progress or reading these example directories.
struct HistorySearchAnimation: View {
    var isCompact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.textScale) private var scale

    var body: some View {
        HistorySearchSurface(isCompact: isCompact, reduceMotion: reduceMotion, isActive: scenePhase == .active)
            .frame(maxWidth: (isCompact ? 22 : 340) * scale)
            .frame(height: (isCompact ? 18 : 174) * scale)
            .frame(maxWidth: isCompact ? 22 * scale : .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct HistorySearchSurface: NSViewRepresentable {
    let isCompact: Bool
    let reduceMotion: Bool
    let isActive: Bool

    func makeNSView(context: Context) -> HistorySearchLayerView {
        HistorySearchLayerView(isCompact: isCompact)
    }

    func updateNSView(_ view: HistorySearchLayerView, context: Context) {
        view.configure(reduceMotion: reduceMotion, isActive: isActive)
    }

    static func dismantleNSView(_ view: HistorySearchLayerView, coordinator: ()) {
        view.stop()
    }
}

/// Core Animation plays the fixed loop independently of history parsing and SwiftUI updates.
final class HistorySearchLayerView: NSView {
    let isCompact: Bool
    private static let itemDuration = 1.25
    private static let animationKey = "history-search"
    private let track = CALayer()
    private let edgeFade = CAGradientLayer()
    private let magnifier = CAShapeLayer()
    private var icons: [CALayer] = []
    private var lastSize = CGSize.zero
    private var reduceMotion = false
    private var isActive = true
    private var motionOrigin: CFTimeInterval?

    init(frame: NSRect = .zero, isCompact: Bool = false) {
        self.isCompact = isCompact
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(track)
        edgeFade.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor,
                           NSColor.black.cgColor, NSColor.clear.cgColor]
        edgeFade.locations = [0, 0.15, 0.85, 1]
        track.mask = isCompact ? nil : edgeFade
        for image in isCompact ? [Self.images[4]] : Self.images {
            let icon = CALayer()
            var rect = CGRect(x: 0, y: 0, width: 256, height: 256)
            icon.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            icon.contentsGravity = .resizeAspect
            icon.shadowColor = NSColor.black.cgColor
            icon.shadowOpacity = 0.08
            icon.shadowRadius = isCompact ? 0.75 : 4
            icon.shadowOffset = CGSize(width: 0, height: isCompact ? -1 : -3)
            track.addSublayer(icon)
            icons.append(icon)
        }
        magnifier.name = "search-lens"
        magnifier.fillColor = nil
        magnifier.lineCap = .round
        magnifier.lineJoin = .round
        magnifier.shadowOpacity = 0.8
        magnifier.shadowRadius = 2
        magnifier.shadowOffset = .zero
        track.addSublayer(magnifier)
        updateLensColor()
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Fetch icon artwork once; no directory enumeration or user file contents are involved.
    private static let images: [NSImage] = {
        let workspace = NSWorkspace.shared
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            workspace.icon(for: .plainText),
            workspace.icon(forFile: home.appendingPathComponent("Downloads").path),
            workspace.icon(forFile: home.path),
            workspace.icon(for: .sourceCode),
            workspace.icon(for: .folder),
            workspace.icon(for: .json),
        ]
    }()

    func configure(reduceMotion: Bool, isActive: Bool) {
        let changed = self.reduceMotion != reduceMotion
        self.reduceMotion = reduceMotion
        self.isActive = isActive
        if changed { rebuild() }
        updatePlayback()
    }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize else { return }
        lastSize = bounds.size
        rebuild()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else { rebuild() }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLensColor()
    }

    private func updateLensColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            magnifier.strokeColor = NSColor(Theme.accent).cgColor
            magnifier.shadowColor = NSColor(Theme.card).cgColor
        }
    }

    func stop() {
        icons.forEach { $0.removeAllAnimations() }
        magnifier.removeAllAnimations()
        motionOrigin = nil
    }

    private func rebuild() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.frame = bounds
        edgeFade.frame = track.bounds
        let size = isCompact ? min(bounds.height, bounds.width - 4)
            : min(88 * bounds.height / 174, bounds.width * 0.28)
        let spacing = bounds.width * 0.24
        let now = track.convertTime(CACurrentMediaTime(), from: nil)
        let origin = motionOrigin ?? now
        motionOrigin = origin
        for (index, icon) in icons.enumerated() {
            icon.removeAllAnimations()
            icon.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            icon.position = CGPoint(x: bounds.midX - (isCompact ? 3 : 0),
                                    y: bounds.midY + (isCompact ? 1 : 0))
            let slot = isCompact ? 0 : CGFloat(index - 2)
            icon.transform = CATransform3DMakeTranslation(slot * spacing, 0, 0)
            icon.transform = CATransform3DScale(icon.transform, depth(at: slot), depth(at: slot), 1)
            icon.opacity = Float(visibility(at: slot))
            if !isCompact, !reduceMotion, window != nil {
                let animation = movement(spacing: spacing)
                // The home folder starts at the inspection point; all six items share a clock.
                animation.beginTime = origin - Double(5 - index) * Self.itemDuration
                icon.add(animation, forKey: Self.animationKey)
            }
        }
        let lensScale = size / (isCompact ? 56 : 88)
        let lensPath = CGMutablePath()
        lensPath.addEllipse(in: CGRect(x: 3 * lensScale, y: 9 * lensScale,
                                      width: 20 * lensScale, height: 20 * lensScale))
        lensPath.move(to: CGPoint(x: 21 * lensScale, y: 11 * lensScale))
        lensPath.addLine(to: CGPoint(x: 30 * lensScale, y: 2 * lensScale))
        magnifier.removeAllAnimations()
        magnifier.bounds = CGRect(x: 0, y: 0, width: 32 * lensScale, height: 32 * lensScale)
        magnifier.path = lensPath
        magnifier.lineWidth = isCompact ? max(1.2, 3 * lensScale) : 3 * lensScale
        magnifier.position = CGPoint(x: bounds.midX + (isCompact ? 1 : 0), y: bounds.midY)
        magnifier.transform = CATransform3DMakeTranslation(
            (isCompact ? 8 : 24) * lensScale, (isCompact ? -9 : -22) * lensScale, 0)
        if !reduceMotion, window != nil {
            let inspection = lensMovement(scale: lensScale)
            inspection.beginTime = origin
            magnifier.add(inspection, forKey: Self.animationKey)
        }
        CATransaction.commit()
        updatePlayback()
    }

    private func lensMovement(scale: CGFloat) -> CAKeyframeAnimation {
        // A closed orbit has matching position AND velocity at the repeat boundary.
        // Interpolated samples avoid separate eased segments that brake at every waypoint.
        let animation = CAKeyframeAnimation(keyPath: "transform")
        let travel: CGFloat = isCompact ? 0.4 : 1
        animation.values = (0...120).map { frame in
            let angle = CGFloat(frame) / 120 * 2 * .pi
            let transform = CATransform3DMakeTranslation(
                (8 + 17 * cos(angle) * travel) * scale, (-9 + 11 * sin(angle) * travel) * scale, 0)
            return NSValue(caTransform3D: CATransform3DRotate(transform, 0.06 * sin(angle), 0, 0, 1))
        }
        animation.calculationMode = .linear
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = Self.itemDuration * 2
        animation.repeatCount = .infinity
        return animation
    }

    private func movement(spacing: CGFloat) -> CAAnimationGroup {
        let duration = Double(icons.count) * Self.itemDuration
        let slots = (0...180).map { 3 - CGFloat($0) / 180 * 6 }
        // This is a marquee, not a sequence of entrances: no holds or per-item easing.
        let transform = CAKeyframeAnimation(keyPath: "transform")
        transform.values = slots.map { slot in
            let translation = CATransform3DMakeTranslation(slot * spacing, 0, 0)
            return NSValue(caTransform3D: CATransform3DScale(translation, depth(at: slot), depth(at: slot), 1))
        }
        transform.duration = duration
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = slots.map { NSNumber(value: Double(visibility(at: $0))) }
        opacity.duration = duration
        let group = CAAnimationGroup()
        group.animations = [transform, opacity]
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        group.duration = duration
        group.repeatCount = .infinity
        return group
    }

    private func depth(at slot: CGFloat) -> CGFloat { 0.72 + 0.28 * visibility(at: slot) }
    private func visibility(at slot: CGFloat) -> CGFloat {
        let phase = min(abs(slot) / 3, 1)
        return (1 + cos(phase * .pi)) / 2
    }

    private func updatePlayback() {
        let shouldPlay = isActive && !reduceMotion && window != nil
        if shouldPlay, track.speed == 0 {
            let pausedTime = track.timeOffset
            track.speed = 1
            track.timeOffset = 0
            track.beginTime = 0
            track.beginTime = track.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        } else if !shouldPlay, track.speed != 0 {
            let pausedTime = track.convertTime(CACurrentMediaTime(), from: nil)
            track.speed = 0
            track.timeOffset = pausedTime
        }
    }
}
