//
//  chaintester.swift
//  ChainTester
//
//  Created by newworld on 8/19/22.
//

import Foundation
import Thrift

extension Data {
  var uint64: UInt64 {
        get {
            if count >= 8 {
                return self.withUnsafeBytes { $0.load(as: UInt64.self) }
            } else {
                return (self + Data(repeating: 0, count: 8 - count)).uint64
            }
        }
    }
}

var gApplyFunc: ((Swift.UInt64, Swift.UInt64, Swift.UInt64) -> Void)? = nil
var gApplyClient: ApplyClient? = nil


func SetApplyFunc(_ fn: @escaping (Swift.UInt64, Swift.UInt64, Swift.UInt64) -> Void) {
    gApplyFunc = fn
}

func RunApplyFunc(receiver: UInt64, firstReceiver: UInt64, action: UInt64) {
    if gApplyFunc == nil {
        return
    }
    gApplyFunc!(receiver, firstReceiver, action)
}

func InitApplyClient() throws {
    usleep(100000)
    _ = try GetApplyClient()
}

func GetApplyClient() throws -> ApplyClient {
    if gApplyClient != nil {
        return gApplyClient!;
    }
    let transport = try Thrift.TSocketTransport(hostname: "localhost", port: 9092)
    let proto = Thrift.TBinaryProtocol(on: transport)
    gApplyClient = ApplyClient(inoutProtocol: proto)
    return gApplyClient!
}

enum ApplyRequestError: Error {
    case applyEndError
}

enum ChainException: Error {
    case Exception(String)
}

class ApplyRequestService: ApplyRequest {

    func apply_request(receiver: Uint64, firstReceiver: Uint64, action: Uint64) throws -> Int32 {
        RunApplyFunc(receiver: receiver.rawValue.uint64, firstReceiver: firstReceiver.rawValue.uint64, action: action.rawValue.uint64)
        _ = try GetApplyClient().end_apply()
        return 0
    }

    func apply_end() throws -> Int32 {
        return 0;
    }
}

extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX" : "%02hhx"
        return self.map { String(format: format, $0) }.joined()
    }
}

public func getFile(_ path: String, _ hex: Bool = false) -> String? {
    let fileUrl = URL(fileURLWithPath: path)

    do {
        // Get the raw data from the file.
        let rawData: Data = try Data(contentsOf: fileUrl)
        if hex {
            return rawData.hexEncodedString()
        } else {
            return String(data: rawData, encoding: String.Encoding.utf8)
        }
    } catch {
        return nil
    }
}

var gChainClient: IPCChainTesterClient? = nil

func GetChainTesterClient() -> IPCChainTesterClient {
    if gChainClient == nil {
        let transport = try? Thrift.TSocketTransport(hostname: "localhost", port: 9090)
        let proto = Thrift.TBinaryProtocol(on: transport!)
        gChainClient = IPCChainTesterClient(inoutProtocol: proto)
    }
    return gChainClient!;
}

var applyRequestServer: SocketServer<Thrift.TBinaryProtocol, Thrift.TBinaryProtocol, ApplyRequestProcessor>? = nil

func GetApplyRequestServer() -> SocketServer<Thrift.TBinaryProtocol, Thrift.TBinaryProtocol, ApplyRequestProcessor> {
    if applyRequestServer == nil {
        let service: ApplyRequest = ApplyRequestService()
        let processor: ApplyRequestProcessor = ApplyRequestProcessor(service: service)
        applyRequestServer = try? SocketServer(port: 9091, inProtocol: Thrift.TBinaryProtocol.self, outProtocol: TBinaryProtocol.self, processor: processor)
    }
    return applyRequestServer!;
}

public class ChainTester {
    public let client: IPCChainTesterClient
    public var id: Int32
    public let applyRequestServer: SocketServer<Thrift.TBinaryProtocol, Thrift.TBinaryProtocol, ApplyRequestProcessor>

    required public init() throws {
        id = 0
        client = GetChainTesterClient()

        applyRequestServer = GetApplyRequestServer()
        
        try client.init_vm_api()
        try InitApplyClient()
        try client.init_apply_request()
        self.waitForApplyRequestClient()

        assert(applyRequestServer.clientFileHandle != nil, "bad clientFileHandle")
        id = try client.new_chain()
    }

    public func waitForApplyRequestClient() {
        CFRunLoopRun()
    }

    public func createKey(keyType: String = "K1") throws -> Dictionary<String,String> {
        let key = try client.create_key(key_type: keyType)
        let data = key.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data, options : .allowFragments) as! Dictionary<String, String>
    }

    public func enableDebugContract(_ contract: String, _ enable: Bool) throws {
        return try client.enable_debug_contract(id: self.id, contract: contract, enable: enable)
    }

    public func importKey(_ pubKey: String, _ privKey: String) throws -> Bool {
        return try client.import_key(id: self.id, pub_key: pubKey, priv_key: privKey)
    }

    public func createAccount(_ creator: String, _ account: String, _ owner_key: String, _ active_key: String, _ ram_bytes: Int64=10*1024*1024, _ stake_net: Int64=100000, _ stake_cpu: Int64=1000000) throws {

        let ret = try client.create_account(id: self.id, creator: creator, account: account, owner_key: owner_key, active_key: active_key, ram_bytes: ram_bytes, stake_net: stake_net, stake_cpu: stake_cpu)

        let data = ret.data(using: .utf8)!
        let js = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as! Dictionary<String, Any>
        if js["except"] != nil {
            throw ChainException.Exception(ret)
        }
    }

    public func produceBlock(_ nextBlockDelaySeconds: Int64 = 0) throws {
        try client.produce_block(id: self.id, next_block_skip_seconds: nextBlockDelaySeconds)
    }

    public func getAccount(_ account: String) throws -> Dictionary<String, Any> {
        let ret = try client.get_account(id: self.id, account: account)
        let data = ret.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data, options : .allowFragments) as! Dictionary<String, Any>
    }

    public func getInfo() throws -> Dictionary<String,Any> {
        let info = try client.get_info(id: self.id)
        let data = info.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: data, options : .allowFragments) as! Dictionary<String,Any>
    }

    public func push_action(id: Int32, account: String, action: String, arguments: String, permissions: String) throws -> Data {
        try client.send_push_action(id: id, account: account, action: action, arguments: arguments, permissions: permissions)
        try client.outProtocol.transport.flush()
        applyRequestServer.process()
        return try client.recv_push_action()
    }
    
    public func pushAction(_ account: String, _ action: String, _ arguments: String, _ permissions: String) throws -> Dictionary<String, Any> {
        let ret = try self.push_action(id: self.id, account: account, action: action, arguments: arguments, permissions: permissions)
        return try JSONSerialization.jsonObject(with: ret, options : .allowFragments) as! Dictionary<String, Any>
    }

    public func deployContract(_ account: String, _ wasmFile: String, _ abiFile: String) throws -> Dictionary<String,Any> {
        let wasm = getFile(wasmFile, true)!
        let abi = getFile(abiFile)!
        let ret = try client.deploy_contract(id: self.id, account: account, wasm: wasm, abi: abi)
        // let data = ret.data(using: .utf8)!
        return try JSONSerialization.jsonObject(with: ret, options : .allowFragments) as! Dictionary<String,Any>
    }
}



// import Thrift
// import PlayingCard
// public struct ChainTester {
//     public private(set) var text = "Hello, World!"

//     public init() {
//     }
// }
