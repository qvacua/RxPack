/// Tae Won Ha - http://taewon.de - @hataewon
/// See LICENSE

import Foundation
import MessagePack
import MPackC

public enum MPackUnpacker {
  public static func unpackAll(from data: Data) throws -> [MessagePackValue] {
    try data.withUnsafeBytes { bufferPointer -> [MessagePackValue] in
      guard let startPointer = bufferPointer.baseAddress else { throw MessagePackError.invalidData }
      var remainingDataCount = data.count
      var result = [MessagePackValue]()

      var pointer = startPointer
      while remainingDataCount > 0 {
        var tree = mpack_tree_t()
        mpack_tree_init_data(&tree, pointer, remainingDataCount)
        defer {
          remainingDataCount -= tree.size
          pointer += tree.size
          mpack_tree_destroy(&tree)
        }

        mpack_tree_parse(&tree)
        guard mpack_tree_error(&tree) == mpack_ok else { throw MessagePackError.invalidData }

        try result.append(mpackNodeToMessagePackValue(node: mpack_tree_root(&tree)))
      }

      return result
    }
  }
}

private func mpackNodeToMessagePackValue(node: mpack_node_t) throws -> MessagePackValue {
  let type = mpack_node_type(node)
  switch type {
  case mpack_type_missing: return .nil
  case mpack_type_nil: return .nil
  case mpack_type_bool: return .bool(mpack_node_bool(node))
  case mpack_type_int: return .int(mpack_node_i64(node))
  case mpack_type_uint: return .uint(mpack_node_u64(node))
  case mpack_type_float: return .float(mpack_node_float(node))
  case mpack_type_double: return .double(mpack_node_double(node))

  case mpack_type_str:
    let strLength = mpack_node_strlen(node)

    guard let cstr = mpack_node_utf8_cstr_alloc(node, strLength + 1),
          let str = String(cString: cstr, encoding: .utf8) else { return .nil }
    free(cstr)

    // The following is slower than above.
    // guard let strPointer = mpack_node_str(node),
    //       let str = String(
    //         bytes: UnsafeRawBufferPointer(start: UnsafeRawPointer(strPointer), count: strLength),
    //         encoding: .utf8
    //       ) else { throw MessagePackError.invalidData }

    return .string(str)

  case mpack_type_bin:
    let count = mpack_node_bin_size(node)
    guard let pointer = mpack_node_bin_data(node) else { throw MessagePackError.invalidData }
    return .binary(Data(bytes: pointer, count: count))

  case mpack_type_array:
    let count = mpack_node_array_length(node)
    let values = try (0..<count)
      .map { mpack_node_array_at(node, $0) }
      .map { try mpackNodeToMessagePackValue(node: $0) }
    return .array(values)

  case mpack_type_map:
    let count = mpack_node_map_count(node)
    let dict = try (0..<count)
      .map { idx -> (MessagePackValue, MessagePackValue) in
        let keyNode = mpack_node_map_key_at(node, idx)
        let valueNode = mpack_node_map_value_at(node, idx)
        let key = try mpackNodeToMessagePackValue(node: keyNode)
        let value = try mpackNodeToMessagePackValue(node: valueNode)
        return (key, value)
      }
      .reduce(into: [:]) { dict, item in dict[item.0] = item.1 }
    return .map(dict)

  case mpack_type_ext:
    let extType = mpack_node_exttype(node)
    let count = mpack_node_data_len(node)
    guard let pointer = mpack_node_data(node) else { throw MessagePackError.invalidData }
    return .extended(extType, Data(bytes: pointer, count: Int(count)))

  default:
    return .nil
  }
}
