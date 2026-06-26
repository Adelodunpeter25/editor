; MARK: Keywords
; ----------------------------
(tag_name) @keywords
(erroneous_end_tag_name) @keywords.error


; MARK: Commands
; ----------------------------

(doctype) @commands


; MARK: Attributes
; ----------------------------

(attribute_name) @attributes


; MARK: Strings
; ----------------------------

(attribute
  (attribute_value) @strings)

(attribute
  (quoted_attribute_value) @strings)


; MARK: Characters
; ----------------------------

(entity) @characters


; MARK: Comments
; ----------------------------

(comment) @comments
