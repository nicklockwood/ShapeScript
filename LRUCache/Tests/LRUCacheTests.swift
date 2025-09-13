//
//  LRUCacheTests.swift
//  LRUCacheTests
//
//  Created by Nick Lockwood on 05/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import LRUCache
import XCTest

class LRUCacheTests: XCTestCase {
    func testCountLimit() {
        let cache = LRUCache<Int, Int>(countLimit: 2)
        cache.setValue(0, forKey: 0)
        XCTAssertNotNil(cache.value(forKey: 0))
        cache.setValue(1, forKey: 1)
        cache.setValue(2, forKey: 2)
        XCTAssertNil(cache.value(forKey: 0))
        XCTAssertNotNil(cache.value(forKey: 1))
        XCTAssertNotNil(cache.value(forKey: 2))
        XCTAssertEqual(cache.count, 2)
    }

    func testCostLimit() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 3)
        cache.setValue(0, forKey: 0, cost: 1)
        cache.setValue(1, forKey: 1, cost: 1)
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.totalCost, 2)
        cache.setValue(2, forKey: 2, cost: 2)
        XCTAssertNil(cache.value(forKey: 0))
        XCTAssertNotNil(cache.value(forKey: 1))
        XCTAssertNotNil(cache.value(forKey: 2))
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.totalCost, 3)
    }

    func testAdjustCountLimit() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 2)
        cache.setValue(0, forKey: 0, cost: 1)
        cache.setValue(1, forKey: 1, cost: 1)
        cache.countLimit = 1
        XCTAssertNil(cache.value(forKey: 0))
        XCTAssertEqual(cache.count, 1)
    }

    func testAdjustCostLimit() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 3)
        cache.setValue(0, forKey: 0, cost: 1)
        cache.setValue(1, forKey: 1, cost: 1)
        cache.setValue(2, forKey: 2, cost: 1)
        cache.totalCostLimit = 2
        XCTAssertNil(cache.value(forKey: 0))
        XCTAssertEqual(cache.count, 2)
        cache.totalCostLimit = 0
        XCTAssert(cache.isEmpty)
    }

    func testRemoveValue() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 2)
        cache.setValue(0, forKey: 0)
        cache.setValue(1, forKey: 1)
        XCTAssertEqual(cache.removeValue(forKey: 0), 0)
        XCTAssertEqual(cache.count, 1)
        XCTAssertNil(cache.removeValue(forKey: 0))
        cache.setValue(nil, forKey: 1)
        XCTAssert(cache.isEmpty)
    }

    func testRemoveAllValues() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 2)
        cache.setValue(0, forKey: 0, cost: 1)
        cache.setValue(1, forKey: 1, cost: 1)
        cache.removeAll()
        XCTAssert(cache.isEmpty)
        XCTAssertEqual(cache.totalCost, 0)
        cache.setValue(0, forKey: 0, cost: 1)
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.totalCost, 1)
    }

    func testOrderedKeys() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 2)
        cache.setValue(0, forKey: 0)
        cache.setValue(1, forKey: 1)
        XCTAssertEqual(cache.orderedKeys, [0, 1])
        cache.setValue(0, forKey: 0)
        XCTAssertEqual(cache.orderedKeys, [1, 0])
        cache.removeAll()
        XCTAssert(cache.orderedKeys.isEmpty)
    }

    func testOrderedValues() {
        let cache = LRUCache<Int, Int>(totalCostLimit: 2)
        cache.setValue(0, forKey: 0)
        cache.setValue(1, forKey: 1)
        XCTAssertEqual(cache.orderedValues, [0, 1])
        cache.setValue(0, forKey: 0)
        XCTAssertEqual(cache.orderedValues, [1, 0])
        cache.removeAll()
        XCTAssert(cache.orderedValues.isEmpty)
    }

    func testReplaceValue() {
        let cache = LRUCache<Int, Int>()
        cache.setValue(0, forKey: 0, cost: 5)
        XCTAssertEqual(cache.value(forKey: 0), 0)
        XCTAssertEqual(cache.totalCost, 5)
        cache.setValue(1, forKey: 0, cost: 3)
        XCTAssertEqual(cache.value(forKey: 0), 1)
        XCTAssertEqual(cache.totalCost, 3)
        cache.setValue(2, forKey: 0, cost: 7)
        XCTAssertEqual(cache.value(forKey: 0), 2)
        XCTAssertEqual(cache.totalCost, 7)
    }

    #if !os(WASI)

    func testConcurrentAccess() {
        let cache = LRUCache<String, Int>()
        let queue = DispatchQueue(label: "stress.test", attributes: .concurrent)
        let group = DispatchGroup()

        let keys = (0 ..< 1000).map { "key\($0)" }
        for _ in 0 ..< 10000 {
            group.enter()
            queue.async {
                let key = keys.randomElement()!
                if Bool.random() {
                    cache.setValue(.random(in: 0 ... 1000), forKey: key)
                } else {
                    _ = cache.value(forKey: key)
                }
                group.leave()
            }
        }

        group.wait()
    }

    func testMemoryWarning() {
        let cache = LRUCache<Int, Int>()
        for i in 0 ..< 100 {
            cache.setValue(i, forKey: i)
        }
        XCTAssertEqual(cache.count, 100)
        NotificationCenter.default.post(
            name: LRUCacheMemoryWarningNotification,
            object: nil
        )
        XCTAssert(cache.isEmpty)
    }

    func testNotificationObserverIsRemoved() {
        final class TestNotificationCenter: NotificationCenter, @unchecked Sendable {
            private(set) var observersCount = 0

            #if os(Linux)
            typealias NotificationBlock = (Notification) -> Void
            #else
            typealias NotificationBlock = @Sendable (Notification) -> Void
            #endif

            override func addObserver(
                forName name: NSNotification.Name?,
                object obj: Any?,
                queue: OperationQueue?,
                using block: @escaping NotificationBlock
            ) -> NSObjectProtocol {
                defer { observersCount += 1 }
                return super.addObserver(
                    forName: name,
                    object: obj,
                    queue: queue,
                    using: block
                )
            }

            override func removeObserver(_ observer: Any) {
                super.removeObserver(observer)
                observersCount -= 1
            }
        }

        let notificationCenter = TestNotificationCenter()
        var cache: LRUCache<Int, Int>? =
            .init(notificationCenter: notificationCenter)
        weak var weakCache = cache
        XCTAssertEqual(1, notificationCenter.observersCount)
        cache = nil
        XCTAssertNil(weakCache)
        XCTAssertEqual(0, notificationCenter.observersCount)
    }

    #endif

    func testNoStackOverflowForlargeCache() {
        let cache = LRUCache<Int, Int>()
        for i in 0 ..< 100000 {
            cache.setValue(i, forKey: i)
        }
    }
}
