//
//  SplitView.swift
//  iOS Viewer
//
//  Created by Nick Lockwood on 19/01/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import UIKit

final class SplitView: UIView {
    private(set) var arrangedSubviews: [UIView] = []
    var heights: [CGFloat?] = [] {
        didSet {
            setNeedsLayout()
        }
    }

    func addArrangedSubview(_ view: UIView, height: CGFloat?) {
        removeArrangedSubview(view)
        arrangedSubviews.append(view)
        heights.append(height)
        addSubview(view)
        setNeedsLayout()
    }

    func removeArrangedSubview(_ view: UIView) {
        while let index = arrangedSubviews.firstIndex(where: {
            $0 === view
        }) {
            arrangedSubviews.remove(at: index)
            heights.remove(at: index)
        }
        view.removeFromSuperview()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var total: CGFloat = 0
        for height in heights {
            total += height ?? 0
        }
        let remaining = bounds.height - total
        let flexibleCount = heights.filter { $0 == nil }.count
        var offset: CGFloat = 0
        for (view, height) in zip(arrangedSubviews, heights) {
            let height = height ?? remaining / CGFloat(flexibleCount)
            view.frame = CGRect(
                x: 0,
                y: offset,
                width: bounds.width,
                height: height
            )
            offset += height
        }
    }
}
