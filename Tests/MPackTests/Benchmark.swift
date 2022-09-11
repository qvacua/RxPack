import MessagePack
import MPack
import XCTest

struct Item: Comparable {
  static func < (lhs: Item, rhs: Item) -> Bool {
    lhs.url.lastPathComponent < rhs.url.lastPathComponent
  }

  static func == (lhs: Item, rhs: Item) -> Bool {
    lhs.url == rhs.url
  }

  var url: URL
  var data: Data
}

final class Benchmark: XCTestCase {
  var msgpackData = [Item]()
  let folder = URL(
    fileURLWithPath: "/Users/hat/Downloads/msgpack-nvim-flush-examples",
    isDirectory: true
  )

  override func setUp() {
    super.setUp()

    self.msgpackData = try! FileManager.default
      .contentsOfDirectory(atPath: self.folder.path)
      .filter { $0 != ".DS_Store" }
      .map { self.folder.appendingPathComponent($0) }
      .map { Item(url: $0, data: try! Data(contentsOf: $0)) }
      .sorted()
  }

  func xtestMpackC() throws {
    let url =
      URL(
        fileURLWithPath: "/Users/hat/Downloads/msgpack-nvim-flush-examples/89.mp"
      )
    let data = try! Data(contentsOf: url)
    try! Swift.print(MPackUnpacker.unpackAll(from: data))
  }

  func xtestA2() throws {
    let url =
      URL(
        fileURLWithPath: "/Users/hat/Downloads/msgpack-nvim-flush-examples/89.mp"
      )
    let data = try! Data(contentsOf: url)
    Swift.print(try! MessagePack.unpackAll(data))
  }

  func testMeasure_1_MPack() throws {
    measure {
      var nilFileCount = 0
      self.msgpackData.forEach { item in
        if (try? MPackUnpacker.unpackAll(from: item.data)) == nil {
          nilFileCount += 1
        }
      }
      Swift.print("\(nilFileCount) files could not be parsed")
    }
  }

  func testMeasure_2_A2() throws {
    measure {
      var nilFileCount = 0
      self.msgpackData.forEach { item in
        if (try? MessagePack.unpackAll(item.data)) == nil {
          nilFileCount += 1
        }
      }
      Swift.print("\(nilFileCount) files could not be parsed")
    }
  }
}
