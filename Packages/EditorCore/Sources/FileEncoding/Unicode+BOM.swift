import Foundation

extension Unicode {

  /// Byte order mark.
  public enum BOM: Sendable, CaseIterable {

    case utf8
    case utf32BigEndian
    case utf32LittleEndian
    case utf16BigEndian
    case utf16LittleEndian

    /// The byte sequence.
    public var sequence: [UInt8] {

      switch self {
      case .utf8: [0xEF, 0xBB, 0xBF]
      case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
      case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
      case .utf16BigEndian: [0xFE, 0xFF]
      case .utf16LittleEndian: [0xFF, 0xFE]
      }
    }

    /// The corresponding string encoding.
    var encoding: String.Encoding {

      switch self {
      case .utf8: .utf8
      case .utf32BigEndian, .utf32LittleEndian: .utf32
      case .utf16BigEndian, .utf16LittleEndian: .utf16
      }
    }

    /// The string encodings that allow the byte order mark in encoding detection.
    var candidateEncodings: [String.Encoding] {

      switch self {
      case .utf8: [.utf8]
      case .utf32BigEndian: [.utf32, .utf32BigEndian]
      case .utf32LittleEndian: [.utf32, .utf32LittleEndian]
      case .utf16BigEndian: [.utf16, .utf16BigEndian]
      case .utf16LittleEndian: [.utf16, .utf16LittleEndian]
      }
    }
  }
}
