; MARK: Comments
; ----------------------------
(Comment) @comments


; MARK: Keywords
; ----------------------------
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

(elementdecl
  "ELEMENT" @keywords
  (Name) @keywords)

(doctypedecl
  "DOCTYPE" @keywords)

(doctypedecl
  (Name) @keywords)


; MARK: Commands
; ----------------------------
(PI) @commands
(PI (PITarget) @commands)


; MARK: Attributes
; ----------------------------
(Attribute
  (Name) @attributes)

(AttDef
  (Name) @attributes)

(PseudoAtt
  (Name) @attributes)

[
  "version"
  "encoding"
  "standalone"
] @attributes


; MARK: Strings
; ----------------------------
(Attribute
  (AttValue) @strings)

(DefaultDecl
  (AttValue) @strings)

(GEDecl
  (EntityValue) @strings)

(PEDecl
  (EntityValue) @strings)

(PseudoAtt
  (PseudoAttValue) @strings)

(PubidLiteral) @strings

(SystemLiteral
  (URI) @strings)


; MARK: Characters
; ----------------------------
(EntityRef) @characters
(CharRef) @characters
(PEReference) @characters


; MARK: Types
; ----------------------------
(STag
  (Name) @types)

(ETag
  (Name) @types)

(EmptyElemTag
  (Name) @types)

(EncName) @types
(VersionNum) @types


; MARK: Numbers
; ----------------------------
[
  "yes"
  "no"
] @numbers
