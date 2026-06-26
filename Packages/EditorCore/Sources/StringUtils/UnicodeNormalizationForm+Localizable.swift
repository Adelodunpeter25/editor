//
//  UnicodeNormalizationForm+Localizable.swift
//  StringUtils
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-06-13.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2025 1024jp
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

public extension UnicodeNormalizationForm {
    
    /// The localized name.
    var localizedName: String {
        
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
    var localizedDescription: String {
        
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
