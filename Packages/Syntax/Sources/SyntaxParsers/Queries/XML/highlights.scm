; MARK: Keywords
; ----------------------------
(tag_name) @keywords
(erroneous_end_tag_name) @keywords

"xml" @keywords

[
  "ELEMENT"
  "ENTITY"
  "ATTLIST"
  "NOTATION"
  "DOCTYPE"
  "SYSTEM"
  "PUBLIC"
  "NDATA"
  "EMPTY"
  "ANY"
  "#PCDATA"
  "#REQUIRED"
  "#IMPLIED"
  "#FIXED"
] @keywords


; MARK: Commands
; ----------------------------
(PI) @commands
(PI (PITarget) @commands)
(doctype) @commands


; MARK: Attributes
; ----------------------------
(attribute_name) @attributes

[
  "version"
  "encoding"
  "standalone"
] @attributes


; MARK: Strings
; ----------------------------
(attribute
  (attribute_value) @strings)

(attribute
  (quoted_attribute_value) @strings)

(EntityValue) @strings

(SystemLiteral) @strings

(PubidLiteral) @strings


; MARK: Characters
; ----------------------------
(entity) @characters

(CHARREF) @characters


; MARK: Comments
; ----------------------------
(comment) @comments


; MARK: Types
; ----------------------------
(Name) @types

(EncName) @types

(VersionNum) @types


; MARK: Numbers
; ----------------------------
[
  "yes"
  "no"
] @numbers
