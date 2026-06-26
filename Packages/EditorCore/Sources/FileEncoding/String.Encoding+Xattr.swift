import Foundation

extension String.Encoding {

  /// Encodes encoding to data for `com.apple.TextEncoding` extended file attribute.
  public var xattrEncodingData: Data? {

    let cfEncoding = CFStringConvertNSStringEncodingToEncoding(self.rawValue)

    guard
      cfEncoding != kCFStringEncodingInvalidId,
      let ianaCharSetName = CFStringConvertEncodingToIANACharSetName(cfEncoding)
    else { return nil }

    let string = "\(ianaCharSetName);\(cfEncoding)"

    return string.data(using: .ascii)
  }
}

extension Data {

  /// Decodes `com.apple.TextEncoding` extended file attribute to encoding.
  public var decodingXattrEncoding: String.Encoding? {

    guard let string = String(data: self, encoding: .ascii) else { return nil }

    let components = string.split(separator: ";")

    guard
      let cfEncoding: CFStringEncoding =
        if components.count >= 2 {
          UInt32(components[1])
        } else if let ianaCharSetName = components.first {
          CFStringConvertIANACharSetNameToEncoding(ianaCharSetName as CFString)
        } else {
          nil
        },
      cfEncoding != kCFStringEncodingInvalidId
    else { return nil }

    return String.Encoding(cfEncoding: cfEncoding)
  }
}
