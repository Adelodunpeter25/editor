import Foundation

extension UnicodeNormalizationForm {

  /// The localized name.
  public var localizedName: String {

    switch self {
    case .nfd:
      "NFD"
    case .nfc:
      "NFC"
    case .nfkd:
      "NFKD"
    case .nfkc:
      "NFKC"
    case .nfkcCaseFold:
      "NFKC Case-Fold"
    case .modifiedNFD:
      "Modified NFD"
    case .modifiedNFC:
      "Modified NFC"
    }
  }

  /// The localized description.
  public var localizedDescription: String {

    switch self {
    case .nfd:
      "Canonical Decomposition"
    case .nfc:
      "Canonical Decomposition, followed by Canonical Composition"
    case .nfkd:
      "Compatibility Decomposition"
    case .nfkc:
      "Compatibility Decomposition, followed by Canonical Composition"
    case .nfkcCaseFold:
      "Applying NFKC, case folding, and removal of default-ignorable code points"
    case .modifiedNFD:
      "Unofficial NFD-based normalization form used in HFS+"
    case .modifiedNFC:
      "Unofficial NFC-based normalization form corresponding to Modified NFD"
    }
  }
}
