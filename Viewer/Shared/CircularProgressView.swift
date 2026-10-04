//
//  CircularProgressView.swift
//  Viewer
//
//  Created by Nick Lockwood on 28/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

import QuartzCore

@MainActor
final class CircularProgressView: OSView {
    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    var minValue: Double = 0
    var maxValue: Double = 1
    var color: OSColor = {
        #if os(macOS)
        .controlAccentColor
        #else
        .label
        #endif
    }() {
        didSet { updateColors() }
    }

    private(set) var doubleValue: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: 22, height: 22)
    }

    #if os(macOS)
    override func layout() {
        super.layout()
        updatePaths()
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        updatePaths()
    }
    #endif

    func setDoubleValue(_ value: Double, animated: Bool) {
        let value = min(max(value, minValue), maxValue)
        guard value != doubleValue else {
            if !animated {
                updateProgress(animated: false)
            }
            return
        }
        doubleValue = value
        updateProgress(animated: animated)
    }

    private func configureLayers() {
        progressLayer.strokeEnd = 0
        #if os(macOS)
        wantsLayer = true
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(progressLayer)
        #else
        isOpaque = false
        backgroundColor = .clear
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)
        #endif

        for item in [trackLayer, progressLayer] {
            item.fillColor = OSColor.clear.cgColor
            item.lineWidth = 2
        }
        progressLayer.lineCap = .round
        updateColors()
    }

    private func updateColors() {
        trackLayer.strokeColor = color.withAlphaComponent(0.2).cgColor
        progressLayer.strokeColor = color.cgColor
    }

    private func updatePaths() {
        let lineWidth: CGFloat = 2
        trackLayer.frame = bounds
        progressLayer.frame = bounds
        trackLayer.lineWidth = lineWidth
        progressLayer.lineWidth = lineWidth

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(0, min(bounds.width, bounds.height) / 2 - lineWidth / 2)
        #if os(macOS)
        let startAngle: CGFloat = .pi / 2
        let endAngle: CGFloat = -.pi * 1.5
        let clockwise = true
        #else
        let startAngle: CGFloat = -.pi / 2
        let endAngle: CGFloat = .pi * 1.5
        let clockwise = false
        #endif
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        trackLayer.path = path
        progressLayer.path = path
    }

    private func updateProgress(animated: Bool) {
        let range = maxValue - minValue
        let progress = range > 0 ? (doubleValue - minValue) / range : 0
        let strokeEnd = min(max(CGFloat(progress), 0), 1)
        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
            animation.toValue = strokeEnd
            animation.duration = 0.3
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressLayer.strokeEnd = strokeEnd
            progressLayer.add(animation, forKey: "strokeEnd")
        } else {
            progressLayer.removeAnimation(forKey: "strokeEnd")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = strokeEnd
            CATransaction.commit()
        }
    }
}
