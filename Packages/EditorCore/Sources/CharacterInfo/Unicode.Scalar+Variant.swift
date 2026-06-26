//
//  Unicode.Scalar+Variant.swift
//  CharacterInfo
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2015-11-19.
//
//  ---------------------------------------------------------------------------
//
//  © 2015-2025 1024jp
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

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
