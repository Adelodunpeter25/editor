//
//  SkinToneModifier.swift
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
