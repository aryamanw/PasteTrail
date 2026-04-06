import XCTest
@testable import PasteTrail

final class KeychainHelperTests: XCTestCase {

    private let testKey = "test.key.\(UUID().uuidString)"
    private var keychain: KeychainHelper { .shared }

    override func tearDown() {
        try? keychain.delete(forKey: testKey)
        super.tearDown()
    }

    func testSaveAndReadString() throws {
        let testValue = "TEST-KEY-1234"
        try keychain.save(testValue, forKey: testKey)
        let readValue = try keychain.readString(forKey: testKey)
        XCTAssertEqual(readValue, testValue)
    }

    func testSaveAndReadData() throws {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        try keychain.save(testData, forKey: testKey)
        let readData = try keychain.read(forKey: testKey)
        XCTAssertEqual(readData, testData)
    }

    func testReadNonExistentThrows() {
        XCTAssertThrowsError(try keychain.readString(forKey: "non.existent.key")) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }

    func testDeleteRemovesItem() throws {
        try keychain.save("test value", forKey: testKey)
        try keychain.delete(forKey: testKey)
        XCTAssertThrowsError(try keychain.readString(forKey: testKey)) { error in
            guard let ke = error as? KeychainError else {
                XCTFail("Expected KeychainError")
                return
            }
            if case .itemNotFound = ke { } else {
                XCTFail("Expected itemNotFound")
            }
        }
    }

    func testUpdateExistingItem() throws {
        try keychain.save("first value", forKey: testKey)
        try keychain.save("updated value", forKey: testKey)
        let readValue = try keychain.readString(forKey: testKey)
        XCTAssertEqual(readValue, "updated value")
    }

    func testDeleteNonExistentDoesNotThrow() {
        try? keychain.delete(forKey: "non.existent.key")
    }
}