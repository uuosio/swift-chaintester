import XCTest
@testable import ChainTester

final class ChainTesterTests: XCTestCase {
    func testExample() throws {
        let tester = try ChainTester()
        let key = try tester.createKey()
        print(key)

        let ret = try tester.importKey(key["public"]!, key["private"]!)
        assert(ret, "import key")

        let pubKey = key["public"]!
        try tester.createAccount("hello", "helloworld33", pubKey, pubKey)
        try tester.produceBlock()
        let accountInfo = try tester.getAccount("helloworld33")
        print(accountInfo)

        let permissions = """
        {
            "helloworld33": "active"
        }
        """

        print(try tester.getInfo())

        let ret2 = try tester.pushAction("helloworld33", "sayhello", "{}", permissions)

        print(ret2)

        print("done!")
        // XCTAssertEqual(ChainTester().text, "Hello, World!")
    }
}
