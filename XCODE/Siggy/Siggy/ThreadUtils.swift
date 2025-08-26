//
//  ThreadUtils.swift
//  Siggy
//
//  Created by MS on 2023-02-21.
//

import Foundation

let tickScale = Int(MSClock.shared.gmt_Scale)


class SimpleMutex {
    var semaphore = DispatchSemaphore(value: 1)
    var lastOwner: Thread!

    func acquire(waitFor ticks: Int = 0) -> Bool {
        if (.success == semaphore.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.nanoseconds(ticks * tickScale)))) {
            lastOwner = Thread.current
            return true
        }
        return false
    }
    
    func acquire() {
        semaphore.wait()
        lastOwner = Thread.current
    }
    
    func release() {
        semaphore.signal()
    }
}

class NoMutex {
    func acquire() {
    }
    
    func release() {
    }

}


class ListItem: NSObject {
    private var itemPriority: Int64
    private var itemObject: Any
    
    var flink: ListItem!
    var blink: ListItem!
    
    var priority: Int64 { return itemPriority }
    var object: Any { return itemObject }
    
    init (_ object: Any,_ priority: Int64) {
        itemObject = object
        itemPriority = priority
    }
}


class Queue: NSObject {
    private var access = SimpleMutex()
    var name: String = ""

    private(set) var count: Int = 0
    private var first: ListItem!
    private var last: ListItem!
    private var current: ListItem!

    // Waiting thread information
    private var waiting: Int = 0
    private var waiter: DispatchSemaphore
    
    init(name: String) {
        self.name = name
        waiter = DispatchSemaphore(value: 0)
    }
    
    var isEmpty: Bool {
        access.acquire()
        let e = (count == 0)
        access.release()
        return e
    }
    
    func verify() {
        var p: ListItem? = nil
        var i = first
        while (i != nil) {
            if (i!.blink != p) { siggyApp.panic (message: "Verify blinked")}
            p = i
            if (i!.flink == i) { siggyApp.panic (message: "Verify cirrcular")}
            i = i!.flink
        }
    }
    
    func firstObject () -> Any? {
        access.acquire()
        if (count == 0) {
            access.release()
            return nil
        }
        
        // save position
        current = first
        
        // return first item.
        let object = first.object
        access.release()
        return object
    }
    
    func nextObject () -> Any? {
        var object: Any?
        
        object = nil
        access.acquire()
        if let item = current {
            current = item.flink
            if (current != nil) {
                if (current == item) { siggyApp.panic(message: "NextObject circular")}
                object = current.object
            }
        }
        access.release()
        return object
    }
    
    func enqueue (object: Any, priority: Int64) {
        access.acquire()
        current = nil
        
        let item = ListItem(object, priority)
        if (count == 0) {
            first = item
            last = item
        }
        else if (priority < first.priority) {
            //MARK: IT GOES AT THE HEAD
            item.flink = first
            first.blink = item
            first = item
        }
        else if (priority >= last.priority) {
            //MARK: IT GOES AT THE TAIL
            item.blink = last
            last.flink = item
            last = item
        }
        else {
            //MARK: SEARCH FOR THE PROPER LOCATION
            var i = first
            while (i != nil) && (priority >= i!.priority) {
                i = i!.flink
            }
            
            if (i != nil) {
                //MARK: IT GOES IN FRONT OF THE ITEM 'I'
                let p = i!.blink
                item.flink = i
                item.blink = p
                i!.blink = item
                p!.flink = item
            }
            else {
                //MARK: NOT POSSIBLE
                siggyApp.panic(message: "ENQUEUE ORDER ERROR")
            }
        }
        
        count += 1
        //verify()
        
        
        if (waiting > 0) {
            waiting -= 1
            waiter.signal()
        }
        access.release()
    }

    private func dequeue_first() -> ListItem? {
        // return first item. Must be called with acquired access
        let item = first
        first = item!.flink
        if (first == nil) {
            last = nil
        }
        else {
            first.blink = nil
            if (first.flink == nil) {
                last = first
            }
        }
        count -= 1
        return item
    }
    
    
    func dequeue() -> Any? {
        access.acquire()
        current = nil
        
        if (count == 0) {
            access.release()
            return nil
        }
        
        let item = dequeue_first()
        access.release()
        return item!.object
    }
    
    
    func dequeue(waitFor ticks: Int) -> Any? {
        access.acquire()
        current = nil
        
        while (count == 0) {
            waiting += 1
            access.release()
            if (waiter.wait(timeout: DispatchTime.now().advanced(by: DispatchTimeInterval.nanoseconds(ticks * tickScale))) == .timedOut) {
                access.acquire()
                waiting -= 1
                access.release()
                return nil
            }
            access.acquire()
            waiting -= 1
        }
        
        let item = dequeue_first()
        access.release()
        return item!.object

    }
    
}

