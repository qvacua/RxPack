/// Tae Won Ha - http://taewon.de - @hataewon
/// See LICENSE

import MessagePack
import Nimble
import RxBlocking
import RxPack
import RxSwift
import Socket
import XCTest

extension Data {
  static func randomData(ofCount count: Int) -> Data {
    Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
  }
}

class RxMsgpackRpcr2Tests: XCTestCase {
  let testEndSemaphore = DispatchSemaphore(value: 0)
  let serverAcceptSemaphore = DispatchSemaphore(value: 0)

  var server: TestSocketServer!
  var clientSocket: Socket!
  let msgpackRpc = RxMsgpackRpc(queueQos: .default)

  let scheduler = ConcurrentDispatchQueueScheduler(qos: .default)
  let disposeBag = DisposeBag()

  override func setUp() {
    super.setUp()
  }

  override func tearDown() {
    super.tearDown()
  }

  func testExample() {
    self.server = TestSocketServer(
      path: "/tmp/echo.sock",
      readBufferSize: Socket.SOCKET_MINIMUM_READ_BUFFER_SIZE
    ) { data, _ in
      // Assert msgs from client here
      let value = try! unpackAll(data)
      print(value)
    }

    self.msgpackRpc.stream
      .observe(on: self.scheduler)
      .subscribe { msg in
        // Assert msgs from server here
        switch msg.element {
        case let .response(msgid, error, result):
          break
        case let .notification(method, params):
          if method == "some_method" {
            print("got message: \(params)")
            _ = try? self.msgpackRpc.stop().toBlocking().first()
            self.server.shutdownServer()
            self.testEndSemaphore.signal()
          }
        default:
          break
        }
      }
      .disposed(by: self.disposeBag)

    DispatchQueue.global(qos: .default).async {
      self.clientSocket = self.server.clientSocket()
      self.serverAcceptSemaphore.signal()
    }

    DispatchQueue.global(qos: .default).async {
      usleep(500)
      _ = try! self.msgpackRpc.run(at: "/tmp/echo.sock", readBufferSize: 1024).toBlocking().first()
      _ = self.serverAcceptSemaphore.wait(timeout: .now().advanced(by: .microseconds(500)))

      // Send msgs to server
      _ = try? self.msgpackRpc.request(method: "test", params: [], expectsReturnValue: false)
        .toBlocking().first()

      // Send msgs to client
      try! self.clientSocket
        .write(from: pack(.array([
          .uint(2),
          .string("some_method"),
          .array([.binary(Data.randomData(ofCount: 1024 * 1024)), .uint(12)]),
        ])))
    }

    let timeoutResult = self.testEndSemaphore.wait(timeout: .now().advanced(by: .seconds(2 * 60)))
    expect(timeoutResult).to(equal(.success))

    _ = try! self.msgpackRpc.stop().toBlocking().first()
    self.server.shutdownServer()
  }
}

/// Modified version of the example in the README of https://github.com/Kitura/BlueSocket.
/// Only supports one connection.
class TestSocketServer {
  typealias DataReadCallback = (Data, Int) -> Void

  private var listenSocket: Socket!

  let path: String
  let readBufferSize: Int
  var connectedSocket: Socket!

  let dataReadCallback: DataReadCallback

  init(path: String, readBufferSize: Int, dataReadCallback: @escaping DataReadCallback) {
    self.path = path
    self.readBufferSize = readBufferSize
    self.dataReadCallback = dataReadCallback
  }

  deinit { self.shutdownServer() }

  func clientSocket() -> Socket? {
    self.listenSocket = try! Socket.create(family: .unix)

    try! self.listenSocket.listen(on: self.path)
    let newSocket = try! self.listenSocket.acceptClientConnection()
    self.connectedSocket = newSocket

    self.readData(from: newSocket)
    return newSocket
  }

  func readData(from socket: Socket) {
    DispatchQueue.global(qos: .default).async { [unowned self] in
      var shouldKeepRunning = true

      var readData = Data(capacity: self.readBufferSize)
      repeat {
        let bytesRead = try! socket.read(into: &readData)

        if bytesRead > 0 {
          self.dataReadCallback(readData, bytesRead)
        }

        if bytesRead == 0 {
          shouldKeepRunning = false
          break
        }

        readData.count = 0
      } while shouldKeepRunning

      socket.close()
    }
  }

  func shutdownServer() {
    self.connectedSocket?.close()
    self.listenSocket?.close()
  }
}
