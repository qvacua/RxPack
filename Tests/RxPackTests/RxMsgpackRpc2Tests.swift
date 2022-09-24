/// Tae Won Ha - http://taewon.de - @hataewon
/// See LICENSE

import Foundation
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

  let uuid = UUID().uuidString

  override func setUp() {
    super.setUp()

    self.server = TestSocketServer()
    self.server.path = FileManager.default
      .temporaryDirectory
      .appendingPathComponent("\(self.uuid).sock")
      .path

    DispatchQueue.global(qos: .default).async {
      self.clientSocket = self.server.clientSocket()
      self.serverAcceptSemaphore.signal()
    }
  }

  override func tearDown() {
    _ = try! self.msgpackRpc.stop().toBlocking().first()
    self.server.shutdownServer()

    super.tearDown()
  }

  func assertMsgsFromClient(assertFn: @escaping TestSocketServer.DataReadCallback) {
    self.server.dataReadCallback = assertFn
  }

  func assertMsgsFromServer(assertFn: @escaping (RxMsgpackRpc.Message) -> Void) {
    self.msgpackRpc.stream
      .observe(on: self.scheduler)
      .subscribe(onNext: assertFn)
      .disposed(by: self.disposeBag)
  }

  func runClientAndSendRequests(readBufferSize: Int, requestFn: () -> Void) {
    usleep(500)
    _ = try! self.msgpackRpc
      .run(at: self.server.path, readBufferSize: readBufferSize)
      .toBlocking()
      .first()
    _ = self.serverAcceptSemaphore.wait(timeout: .now().advanced(by: .microseconds(500)))

    requestFn()

    self.waitForAssertions()
  }

  func signalEndOfTest() {
    self.testEndSemaphore.signal()
  }

  func waitForAssertions() {
    let timeoutResult = self.testEndSemaphore.wait(timeout: .now().advanced(by: .seconds(2 * 60)))
    expect(timeoutResult).to(equal(.success))
  }

  func testSomething() {
    self.server.readBufferSize = Socket.SOCKET_MINIMUM_READ_BUFFER_SIZE

    self.assertMsgsFromClient { data, _ in
      // Assert msgs from client here
      let value = try! unpackAll(data)
      print(value)
    }

    self.assertMsgsFromServer { msg in
      switch msg {
      case let .response(msgid, error, result):
        break
      case let .notification(method, params):
        if method == "notification-data-int" {
          print("got message: \(params)")
          _ = try? self.msgpackRpc.stop().toBlocking().first()
          self.server.shutdownServer()
          self.signalEndOfTest()
        }
      default:
        break
      }
    }

    self.runClientAndSendRequests(readBufferSize: Socket.SOCKET_MINIMUM_READ_BUFFER_SIZE) {
      // Send msgs to server
      _ = try? self.msgpackRpc
        .request(
          method: "first-method",
          params: [.uint(0), .uint(1)],
          expectsReturnValue: false
        )
        .toBlocking().first()

      // Send msgs to client
      try! self.clientSocket
        .write(from: pack(.array([
          .uint(RxMsgpackRpc.MessageType.notification.rawValue),
          .string("notification-data-int"),
          .array([.binary(Data.randomData(ofCount: 1024 * 1024)), .uint(17)]),
        ])))
    }
  }
}

/// Modified version of the example in the README of https://github.com/Kitura/BlueSocket.
/// Only supports one connection.
class TestSocketServer {
  typealias DataReadCallback = (Data, Int) -> Void

  private var listenSocket: Socket!

  var connectedSocket: Socket!

  var path: String = "/tmp/com.qvacua.RxMsgpackRpc.RxMsgpackRpcTest.sock"
  var readBufferSize: Int = Socket.SOCKET_MINIMUM_READ_BUFFER_SIZE
  var dataReadCallback: DataReadCallback = { _, _ in }

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
