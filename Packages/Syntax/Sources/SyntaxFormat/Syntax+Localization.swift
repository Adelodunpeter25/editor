//
//  Syntax+Localization.swift
//  Syntax
//
//  CotEditor
//  https://coteditor.com
//
//  Created by 1024jp on 2024-03-02.
//
//  ---------------------------------------------------------------------------
//
//  © 2024-2026 1024jp
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

public extension Syntax.Kind {
    
    var label: String {
        
        switch self {
            case .general: "General"
            case .code: "Code"
        }
    }
}


public extension SyntaxType {
    
    var label: String {
        
        switch self {
            case .keywords: "Keywords"
            case .commands: "Commands"
            case .types: "Types"
            case .attributes: "Attributes"
            case .variables: "Variables"
            case .values: "Values"
            case .numbers: "Numbers"
            case .strings: "Strings"
            case .characters: "Characters"
            case .comments: "Comments"
        }
    }
}


public extension Syntax.Outline.Kind {
    
    var label: String {
        
        switch self {
            case .container: "Container"
            case .value: "Value"
            case .function: "Function"
            case .title: "Title"
            case .heading(let level?):
                "Heading \(level)"
            case .heading(nil):
                "Heading"
            case .mark: "Mark"
            case .separator: "Separator"
        }
    }
}
