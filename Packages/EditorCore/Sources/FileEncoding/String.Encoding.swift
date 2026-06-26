import Foundation

extension String.Encoding {

  /// Initializes String.Encoding most closely to a given Core Foundation encoding constant.
  ///
  /// - Parameter cfEncoding: The Core Foundation encoding constant.
  public init(cfEncoding: CFStringEncoding) {

    self.init(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
  }

  /// The `CFStringEncoding` constant that is the closest mapping to the receiver.
  public var cfEncoding: CFStringEncoding {

    CFStringConvertNSStringEncodingToEncoding(self.rawValue)
  }

  /// The name of the IANA registry “charset” that is the closest mapping to the encoding.
  public var ianaCharSetName: String? {

    CFStringConvertEncodingToIANACharSetName(self.cfEncoding) as String?
  }

  /// Whether the encoding is a Unicode encoding.
  public var isUnicodeEncoding: Bool {

    switch self {
    case .utf8, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian,
      .utf32LittleEndian:
      true
    default:
      false
    }
  }
}
