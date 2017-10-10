// This is an copy of NSCache but in a more Swift friendly way
// Can store Any, with any Hashable key, so you are not limited
// to NSObjects as with NSCache
//
// Copyright (c) 2017 Fred Cox
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// Based on the NSCache code from the swift project
// https://github.com/apple/swift-corelibs-foundation/blob/master/Foundation/NSCache.swift
// https://gist.github.com/mcfedr/63df1f48be68e64d8d05f7e2d4ef13ee

import Foundation

private class CacheEntry<KeyType: Hashable, ObjectType : Any> {
    var key: KeyType
    var value: ObjectType
    var cost: Int
    var prevByCost: CacheEntry?
    var nextByCost: CacheEntry?
    init(key: KeyType, value: ObjectType, cost: Int) {
        self.key = key
        self.value = value
        self.cost = cost
    }
}

open class Cache<KeyType: Hashable, ObjectType : Any> {

    private var _entries = [KeyType: CacheEntry<KeyType, ObjectType>]()
    private let _lock = NSLock()
    private var _totalCost = 0
    private var _head: CacheEntry<KeyType, ObjectType>?

    open var name: String = ""
    open var totalCostLimit: Int = 0 // limits are imprecise/not strict
    open var countLimit: Int = 0 // limits are imprecise/not strict
    open var evictsObjectsWithDiscardedContent: Bool = false

    public init(name: String = "", totalCostLimit: Int = 0, countLimit: Int = 0, evictsObjectsWithDiscardedContent: Bool = false) {
        self.name = name
        self.totalCostLimit = totalCostLimit
        self.countLimit = countLimit
        self.evictsObjectsWithDiscardedContent = evictsObjectsWithDiscardedContent
    }

    open weak var delegate: CacheDelegate?

    open func object(forKey key: KeyType) -> ObjectType? {
        var object: ObjectType?

        _lock.lock()
        if let entry = _entries[key] {
            object = entry.value
        }
        _lock.unlock()

        return object
    }

    open func setObject(_ obj: ObjectType, forKey key: KeyType) {
        setObject(obj, forKey: key, cost: 0)
    }

    open subscript(key: KeyType) -> ObjectType? {
        get {
            return object(forKey: key)
        }
        set {
            if let newValue = newValue {
                setObject(newValue, forKey: key)
            } else {
                removeObject(forKey: key)
            }
        }
    }

    private func remove(_ entry: CacheEntry<KeyType, ObjectType>) {
        let oldPrev = entry.prevByCost
        let oldNext = entry.nextByCost

        oldPrev?.nextByCost = oldNext
        oldNext?.prevByCost = oldPrev

        if entry === _head {
            _head = oldNext
        }
    }

    private func insert(_ entry: CacheEntry<KeyType, ObjectType>) {
        guard var currentElement = _head else {
            // The cache is empty
            entry.prevByCost = nil
            entry.nextByCost = nil

            _head = entry
            return
        }

        guard entry.cost > currentElement.cost else {
            // Insert entry at the head
            entry.prevByCost = nil
            entry.nextByCost = currentElement
            currentElement.prevByCost = entry

            _head = entry
            return
        }

        while currentElement.nextByCost != nil && currentElement.nextByCost!.cost < entry.cost {
            currentElement = currentElement.nextByCost!
        }

        // Insert entry between currentElement and nextElement
        let nextElement = currentElement.nextByCost

        currentElement.nextByCost = entry
        entry.prevByCost = currentElement

        entry.nextByCost = nextElement
        nextElement?.prevByCost = entry
    }

    open func setObject(_ obj: ObjectType, forKey key: KeyType, cost: Int) {
        let cost = max(cost, 0)

        _lock.lock()

        let costDiff: Int

        if let entry = _entries[key] {
            costDiff = cost - entry.cost
            entry.cost = cost

            entry.value = obj

            if costDiff != 0 {
                remove(entry)
                insert(entry)
            }
        } else {
            let entry = CacheEntry(key: key, value: obj, cost: cost)
            _entries[key] = entry
            insert(entry)

            costDiff = cost
        }

        _totalCost += costDiff

        var purgeAmount = (totalCostLimit > 0) ? (_totalCost - totalCostLimit) : 0
        while purgeAmount > 0 {
            if let entry = _head {
                delegate?.cache(self, willEvictObject: entry.value)

                _totalCost -= entry.cost
                purgeAmount -= entry.cost

                remove(entry) // _head will be changed to next entry in remove(_:)
                _entries[entry.key] = nil
            } else {
                break
            }
        }

        var purgeCount = (countLimit > 0) ? (_entries.count - countLimit) : 0
        while purgeCount > 0 {
            if let entry = _head {
                delegate?.cache(self, willEvictObject: entry.value)

                _totalCost -= entry.cost
                purgeCount -= 1

                remove(entry) // _head will be changed to next entry in remove(_:)
                _entries[entry.key] = nil
            } else {
                break
            }
        }

        _lock.unlock()
    }

    open func removeObject(forKey key: KeyType) {
        _lock.lock()
        if let entry = _entries.removeValue(forKey: key) {
            _totalCost -= entry.cost
            remove(entry)
        }
        _lock.unlock()
    }

    open func removeAllObjects() {
        _lock.lock()
        _entries.removeAll()

        while let currentElement = _head {
            let nextElement = currentElement.nextByCost

            currentElement.prevByCost = nil
            currentElement.nextByCost = nil

            _head = nextElement
        }

        _totalCost = 0
        _lock.unlock()
    }
}

public protocol CacheDelegate: AnyObject {
    func cache<KeyType, ObjectType : Any>(_ cache: Cache<KeyType, ObjectType>, willEvictObject obj: ObjectType)
}

extension CacheDelegate {
    func cache<KeyType, ObjectType : Any>(_ cache: Cache<KeyType, ObjectType>, willEvictObject obj: ObjectType) {
        // Default implementation does nothing
    }
}
