import XCTest
@testable import ChainTester

func Apply(_ receiver: UInt64, _ firstReceiver: UInt64, _ action: UInt64) -> Void {
    for i in 0...5 {
        try? GetApplyClient().printi(n: Int64(exactly: i)!)
        try? GetApplyClient().prints(cstr: "hello, world\n")
    }
}

func SetApplyFunc(_ fn: @escaping (Swift.UInt64, Swift.UInt64, Swift.UInt64) -> Void) {
    gApplyFunc = fn
}

final class ChainTesterTests: XCTestCase {
    override class func setUp() {
        SetApplyFunc(Apply)
    }

    func testBasic() throws {
        let tester = try ChainTester()
        try tester.enableDebugContract("helloworld33", true)

        let key = try tester.createKey()
        debugPrint(key)

        let ret = try tester.importKey(key["public"]!, key["private"]!)
        assert(ret, "import key")

        let pubKey = key["public"]!
        try tester.createAccount("hello", "helloworld33", pubKey, pubKey)
        try tester.produceBlock()
        let accountInfo = try tester.getAccount("helloworld33")
        debugPrint(accountInfo)

        let permissions = """
        {
            "helloworld33": "active"
        }
        """

        debugPrint(try tester.getInfo())

        _ = try tester.deployContract("helloworld33",
            "/Users/newworld/dev/as/ascdk/ts-packages/chaintester/tests/hello.wasm",
            "/Users/newworld/dev/as/ascdk/ts-packages/chaintester/tests/hello.abi"
        )
        
        let ret2 = try tester.pushAction("helloworld33", "sayhello", "{}", permissions)


        debugPrint(ret2)

        debugPrint("done!")
        // XCTAssertEqual(ChainTester().text, "Hello, World!")
    }
}
