; MARK: Comments
; ----------------------------
(comment) @comments
(documentation_comment) @comments


; MARK: Keywords
; ----------------------------
[
  (assert_builtin)
  (break_builtin)
  (const_builtin)
  (part_of_builtin)
  (rethrow_builtin)
  (void_type)
  "abstract"
  "as"
  "async"
  "async*"
  "await"
  "base"
  "case"
  "catch"
  "class"
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
  "Function"
  "hide"
  "if"
  "implements"
  "import"
  "in"
  "interface"
  "is"
  "late"
  "library"
  "mixin"
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
  "throw"
  "try"
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

(class_definition
  name: (identifier) @types)

(constructor_signature
  name: (identifier) @types)

(enum_declaration
  name: (identifier) @types)

(extension_type_declaration
  name: (identifier) @types)


; MARK: Strings
; ----------------------------
(string_literal) @strings
(escape_sequence) @strings


; MARK: Numbers
; ----------------------------
[
  (hex_integer_literal)
  (decimal_integer_literal)
  (decimal_floating_point_literal)
] @numbers


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


; MARK: Characters
; ----------------------------
(enum_constant
  name: (identifier) @characters)

(symbol_literal
  (identifier) @characters)


; MARK: Variables
; ----------------------------
(identifier) @variables
