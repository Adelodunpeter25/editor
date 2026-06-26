//
//  String+Escaping.swift
//  StringUtils
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-06-16.
//
//  ---------------------------------------------------------------------------
//
//  © 2016-2026 1024jp
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

extension String {

  /// Unescaped version of the string by unescaping the characters with backslashes.
  ///
  /// This method does not support Unicode scalar escape (`\u{n}`).
  public var unescaped: String {

    let regex = try! NSRegularExpression(pattern: "\\\\([0tnr\"'\\\\])")
    let range = NSRange(self.startIndex..<self.endIndex, in: self)
    let mutableString = NSMutableString(string: self)
    regex.replaceMatches(in: mutableString, options: [], range: range, withTemplate: "$1")
    // -> This doesn't work for unescaping, so do manual replacement
    var result = ""
    var i = self.startIndex
    while i < self.endIndex {
      if self[i] == "\\", self.index(after: i) < self.endIndex {
        let next = self[self.index(after: i)]
        switch next {
        case "0": result.append("\0")
        case "t": result.append("\t")
        case "n": result.append("\n")
        case "r": result.append("\r")
        case "\"": result.append("\"")
        case "'": result.append("'")
        case "\\": result.append("\\")
        default:
          result.append(self[i])
          result.append(next)
        }
        i = self.index(i, offsetBy: 2)
      } else {
        result.append(self[i])
        i = self.index(after: i)
      }
    }
    return result
  }
}

private let maxEscapesCheckLength = 8

extension StringProtocol {

  /// Checks if character at the index is escaped with the given character.
  ///
  /// - Parameters:
  ///   - index: The index of the character to check.
  ///   - character: The escape character.
  /// - Returns: `true` when the character at the given index is escaped.
  public func isEscaped(at index: Index, by character: Character = "\\") -> Bool {

    let count = self[..<index].suffix(maxEscapesCheckLength)
      .reversed()
      .prefix { $0 == character }
      .count

    return !count.isMultiple(of: 2)
  }
}

extension NSString {

  /// Checks if character at the location is escaped with the given character.
  ///
  /// - Parameters:
  ///   - location: The UTF16-based location of the character to check.
  ///   - escapeCharacter: The escape character.
  /// - Returns: `true` when the character at the given index is escaped.
  public final func isEscaped(at location: Int, by escapeCharacter: Character = "\\") -> Bool {

    assert(escapeCharacter.utf16.count == 1)

    guard let codeUnit = escapeCharacter.utf16.first else { return false }

    let lowerBound = max(location - maxEscapesCheckLength, 0)
    let count = (lowerBound..<location)
      .reversed()
      .prefix { self.character(at: $0) == codeUnit }
      .count

    return !count.isMultiple(of: 2)
  }
}
