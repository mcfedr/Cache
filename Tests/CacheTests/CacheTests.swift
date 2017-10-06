import XCTest
@testable import Cache

class CacheTests: XCTestCase {
    func testStore() {
        let cache = Cache<Int, String>()
        cache[1] = "Hello"
        cache[2] = "World"
        
        XCTAssertEqual(cache[1], "Hello")
        XCTAssertEqual(cache[2], "World")
    }


    static var allTests = [
        ("testStore", testStore),
    ]
}
