import XCTest
@testable import ChainTester

final class ChainTesterTests: XCTestCase {
    func testGetFile() throws {
        print(getFile("/Users/newworld/dev/swift/ChainTester3/Sources/ChainTester/interfaces.swift")!)
    }

    func testBasic() throws {
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

        try tester.deployContract("helloworld33",
            "/Users/newworld/dev/as/ascdk/ts-packages/chaintester/tests/hello.wasm",
            "/Users/newworld/dev/as/ascdk/ts-packages/chaintester/tests/hello.abi"
        )
        
        let ret2 = try tester.pushAction("helloworld33", "sayhello", "{}", permissions)


        print(ret2)

        print("done!")
        // XCTAssertEqual(ChainTester().text, "Hello, World!")
    }
}
