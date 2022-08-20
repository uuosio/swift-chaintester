//
//  main.swift
//  ChainTester
//
//  Created by newworld on 8/19/22.
//

import Foundation

let aa: Swift.Int32 = 0
let bb: Swift.UInt64 = 0

print("Hello, World!")

//let server = LocalServer(port: 9099);

//let handle = Task {
//
//}
//
//let result = await handle.value

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
