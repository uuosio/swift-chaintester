//https://gist.github.com/matt-curtis/3183ee5dd072dc7a2d8c3a5d5433fa21

import Foundation
//import Cocoa

private enum Constants {
    
    static let crlf: Character = "\r\n"
    
}

/*
    Derived from a number of literature online, but primarily:
    https://dev-notes.eu/2018/06/http-server-in-c/
*/

class LocalServer {
    
    //    MARK: - Subtypes
    
    struct Request {
        
        enum Method: String {
            
            case get = "GET", post = "POST"
            
        }
        
        let method: Method
        
        let body: Data
        
    }
    
    
    //    MARK: - Properties
    
    private let serverSocketFd: Int32
    
    private var serverSocket: CFSocket!
    
    private let runLoop: CFRunLoop
    
    
    var onRequest: ((Request) -> String?)?
    
    
    //    MARK: - Init
    
    init(port: Int) {
        //    Socket setup: creates an endpoint for communication, returns a file descriptor
        
        serverSocketFd = socket(
            AF_INET,      // Domain: specifies protocol family; set to TCP
            SOCK_STREAM,  // Type: specifies communication semantics; set to IPv4
            0             // Protocol: 0 because there is a single protocol for the specified family
        )
        
        guard serverSocketFd != -1 else {
            fatalError("Failed to create socket for server.")
        }
        
        //    Tell OS we want to bypass socket reuse wait time, and use it right now:
        
        var enable = 1
        let enableFlagByteSize = MemoryLayout.size(ofValue: enable)
        
        if setsockopt(serverSocketFd, SOL_SOCKET, SO_REUSEADDR, &enable, socklen_t(enableFlagByteSize)) < 0 {
            fatalError("Setting socket reuse (setsockopt(SO_REUSEADDR)) failed")
        }
        
        //    Construct local address structure
        
        var serverAddress = sockaddr_in()
        
        serverAddress.sin_family = .init(AF_INET)
        serverAddress.sin_port = in_port_t(port).bigEndian // htons is not availble in Swift; google: 'htons in swift'
        serverAddress.sin_addr.s_addr = in_addr_t(INADDR_ANY).bigEndian // same as: inet_addr("127.0.0.1")
        
        //    Bind socket to local address.
        //    bind() assigns the address specified by serverAddress to the socket
        //    referred to by the file descriptor serverSocketFd.
        
        let bindResult = withUnsafePointer(to: &serverAddress) {
            [serverSocketFd] in
            
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(
                    serverSocketFd,
                    $0,
                    .init(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        
        guard bindResult != -1 else {
            fatalError("Failed to bind socket to local address.")
        }
        
        //    Start listening for incoming requests
        
        let maxPendingConnections = 10
        let listenResult = listen(serverSocketFd, .init(maxPendingConnections))
        
        if listenResult == -1 {
            fatalError("Failed to start listening for incoming connections")
        }
        
        //    Lastly, have the runloop notify us when there's an incoming connection:
        
        runLoop = CFRunLoopGetCurrent()
        
        var ctx = CFSocketContext()
        
        class WeakReference {
            
            weak var value: LocalServer?
            
            init(_ value: LocalServer) { self.value = value }
            
        }
        
        ctx.info = Unmanaged.passRetained(WeakReference(self)).toOpaque()
        
        ctx.release = {
            info in
            
            guard let info = info else { return }
            
            Unmanaged<WeakReference>.fromOpaque(info).release()
        }
        
        let optionalCFSocket = CFSocketCreateWithNative(
            nil,            // allocator
            serverSocketFd, // socket fd
            CFSocketCallBackType.readCallBack.rawValue,
            {
                cfSocket, callbackType, addressData, data, info in
                
                guard let info = info else { return }
                
                let server = Unmanaged<WeakReference>.fromOpaque(info).takeUnretainedValue()
                
                server.value?.handleIncomingRequests()
            },
            &ctx
        )
        
        guard let cfSocket = optionalCFSocket else {
            fatalError("Failed to create CFSocket.")
        }
        
        serverSocket = cfSocket
        
        let serverSocketSource = CFSocketCreateRunLoopSource(nil, cfSocket, 0)
        
        CFRunLoopAddSource(runLoop, serverSocketSource, .commonModes)
    }
    
    deinit {
        CFSocketInvalidate(serverSocket)
        
        Darwin.close(serverSocketFd)
    }
    
    private func handleIncomingRequests() {
        //    Open socket for incoming request
        
        let clientSocketFd = accept(serverSocketFd, nil, nil)
        
        guard clientSocketFd != -1 else { return }
        
        defer { Darwin.close(clientSocketFd) }
        
        //    Respond:
        
        if
            let request = parseStreamIntoRequest(socket: clientSocketFd),
            let responseBody = onRequest?(request)
        {
            let response = constructResponse(with: responseBody)
            
            send(clientSocketFd, response, response.utf8.count, 0)
        } else {
            send(clientSocketFd, "", 0, 0)
        }
    }
    
    private func constructResponse(with body: String) -> String {
        let crlf = String(Constants.crlf)
        
        let header = [
            "HTTP/1.1 200 OK",
            "Server: Mirror",
            "Access-Control-Allow-Origin: *",
            "Content-Length: \(body.utf8.count)",
        ].joined(separator: crlf)
        
        return "\(header)\(crlf)\(crlf)\(body)"
    }
    
    private func parseStreamIntoRequest(socket: Int32) -> Request? {
        var isFirstLine = true
        
        var possibleMethod: Request.Method?
        var possibleContentLength: Int?
        
        //    Parse stream line-by-line
        
        var bytesReadSoFar = 0
        
        let byteIterator = AnyIterator<UInt8> {
            var byte: UInt8 = 0
            
            if read(socket, &byte, 1) == 1 {
                bytesReadSoFar += 1
                
                return byte
            }
            
            return nil
        }
        
        let crlfBytes = Array(Constants.crlf.utf8)
        var bytesMatchingSoFar = 0
        
        while true {
            let currentLineBytes = byteIterator.prefix(while: {
                if $0 == crlfBytes[bytesMatchingSoFar] {
                    bytesMatchingSoFar += 1
                    
                    if bytesMatchingSoFar == crlfBytes.count {
                        bytesMatchingSoFar = 0
                        
                        return false
                    }
                } else {
                    bytesMatchingSoFar = 0
                }
                
                return true
            })
            
            guard
                let line = String(bytes: currentLineBytes, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else { return nil }
            
            if isFirstLine {
                isFirstLine = false
                
                //    Status line
                
                let parts = line.components(separatedBy: " ") // [ method, path, status? ]
                
                guard parts.count == 3 else { return nil }
                
                possibleMethod = Request.Method(rawValue: parts[0])
            } else if line.isEmpty {
                //    After this is where request data begins
                
                break
            } else {
                //    Header
                
                let keyAndValue = line.split(separator: ":", maxSplits: 1)
                
                guard keyAndValue.count == 2 else {
                    return nil
                }
                
                let key = keyAndValue[0], value = keyAndValue[1].trimmingCharacters(in: .whitespaces)
                
                if key.lowercased() == "content-length" {
                    possibleContentLength = Int(value)
                }
            }
            
            if line.isEmpty { break }
        }
        
        guard let method = possibleMethod else { return nil }
        
        if
            method == .post,
            let contentLength = possibleContentLength
        {
            var data = Data(count: contentLength)
            var bytesRemaining = contentLength
            
            while bytesRemaining > 0 {
                let offset = contentLength - bytesRemaining
                let bytesRead = data.withUnsafeMutableBytes {
                    read(socket, $0.baseAddress! + offset, bytesRemaining)
                }
                
                if bytesRead <= 0 { return nil }
                
                bytesRemaining -= bytesRead
            }
            
            return Request(method: method, body: data)
        }
        
        return Request(method: method, body: .init())
    }
    
}
