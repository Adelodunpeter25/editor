import DocumentFile
import FileEncoding
import Foundation

extension String {

  /// Initializes a string by reading and decoding the contents of the file at the given URL.
  ///
  /// - Parameters:
  ///   - url: The file URL to read.
  ///   - decodingOptions: The decoding options.
  /// - Throws: A file read or decoding error.
  init(contentsOf url: URL, decodingOptions: String.DetectionOptions) throws {

    let data = try Data(contentsOf: url)
    let attributes = try FileManager.default.attributesOfItem(
      atPath: url.path(percentEncoded: false))
    let extendedAttributes = ExtendedFileAttributes(dictionary: attributes)
    var decodingOptions = decodingOptions
    decodingOptions.xattrEncoding = extendedAttributes.encoding

    (self, _) = try String.string(data: data, decodingStrategy: .automatic(decodingOptions))
  }
}
