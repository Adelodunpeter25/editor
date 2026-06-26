import Foundation

enum SkinToneModifier: UInt32, Sendable {

  case type12 = 0x1F3FB  // 🏻 Light
  case type3 = 0x1F3FC  // 🏼 Medium Light
  case type4 = 0x1F3FD  // 🏽 Medium
  case type5 = 0x1F3FE  // 🏾 Medium Dark
  case type6 = 0x1F3FF  // 🏿 Dark

  var label: String {

    switch self {
    case .type12:
      "Skin Tone I-II"
    case .type3:
      "Skin Tone III"
    case .type4:
      "Skin Tone IV"
    case .type5:
      "Skin Tone V"
    case .type6:
      "Skin Tone VI"
    }
  }
}
