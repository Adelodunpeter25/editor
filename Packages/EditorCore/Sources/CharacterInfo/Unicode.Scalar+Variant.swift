import Foundation

extension Unicode.Scalar {

  /// The description about the Unicode variant selector if the scalar is a variant selector.
  public var variantDescription: String? {

    if let selector = EmojiVariationSelector(rawValue: self.value) {
      selector.label

    } else if let modifier = SkinToneModifier(rawValue: self.value) {
      modifier.label

    } else if self.properties.isVariationSelector {
      "Variant"

    } else {
      nil
    }
  }
}

private enum EmojiVariationSelector: UInt32 {

  case text = 0xFE0E
  case emoji = 0xFE0F

  var label: String {

    switch self {
    case .emoji:
      "Emoji Style"
    case .text:
      "Text Style"
    }
  }
}
