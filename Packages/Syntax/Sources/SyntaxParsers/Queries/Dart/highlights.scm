; MARK: Comments
; ----------------------------
(comment) @comments
(block_comment) @comments
(documentation_block_comment) @comments


; MARK: Keywords
; ----------------------------
[
  "abstract"
  "as"
  "assert"
  "async"
  "async*"
  "augment"
  "await"
  "base"
  "break"
  "case"
  "catch"
  "class"
  "const"
  "continue"
  "covariant"
  "default"
  "deferred"
  "do"
  "else"
  "enum"
  "export"
  "extends"
  "extension"
  "external"
  "factory"
  "final"
  "finally"
  "for"
  "get"
  "hide"
  "if"
  "implements"
  "import"
  "in"
  "inline"
  "interface"
  "is"
  "late"
  "library"
  "mixin"
  "native"
  "new"
  "on"
  "operator"
  "part"
  "required"
  "return"
  "sealed"
  "set"
  "show"
  "static"
  "super"
  "switch"
  "sync*"
  "this"
  "throw"
  "try"
  "type"
  "typedef"
  "var"
  "when"
  "while"
  "with"
  "yield"
] @keywords


; MARK: Types
; ----------------------------
(type_identifier) @types
(void_type) @types
"Function" @types

(class_declaration
  name: (identifier) @types)

(mixin_declaration
  (identifier) @types)

(extension_declaration
  name: (identifier) @types)

(extension_type_declaration
  name: (extension_type_name
    (identifier) @types))

(enum_declaration
  name: (identifier) @types)

(type_alias
  (type_identifier) @types)


; MARK: Strings
; ----------------------------
(string_literal) @strings
(template_chars_single) @strings
(template_chars_double) @strings
(template_chars_single_single) @strings
(template_chars_double_single) @strings
(template_chars_raw_slash) @strings
(escape_sequence) @strings
(symbol_literal) @strings


; MARK: Numbers
; ----------------------------
(decimal_integer_literal) @numbers
(hex_integer_literal) @numbers
(decimal_floating_point_literal) @numbers


; MARK: Values
; ----------------------------
[
  (true)
  (false)
  (null_literal)
] @values


; MARK: Attributes
; ----------------------------
(annotation
  name: (identifier) @attributes)


; MARK: Variables
; ----------------------------
(identifier) @variables


; MARK: Characters
; ----------------------------
(enum_constant
  name: (identifier) @characters)
