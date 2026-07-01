; MARK: Comments
; ----------------------------
(comment) @comments


; MARK: Keywords
; ----------------------------
[
  (yaml_directive)
  (tag_directive)
  (reserved_directive)
] @keywords

(tag) @keywords


; MARK: Strings
; ----------------------------
[
  (double_quote_scalar)
  (single_quote_scalar)
  (block_scalar)
  (string_scalar)
] @strings


; MARK: Numbers
; ----------------------------
[
  (integer_scalar)
  (float_scalar)
] @numbers


; MARK: Values
; ----------------------------
[
  (boolean_scalar)
  (null_scalar)
] @values


; MARK: Attributes
; ----------------------------
(block_mapping_pair
  key: (flow_node
    [
      (double_quote_scalar)
      (single_quote_scalar)
    ] @attributes))

(block_mapping_pair
  key: (flow_node
    (plain_scalar
      (string_scalar) @attributes)))

(flow_mapping
  (_
    key: (flow_node
      [
        (double_quote_scalar)
        (single_quote_scalar)
      ] @attributes)))

(flow_mapping
  (_
    key: (flow_node
      (plain_scalar
        (string_scalar) @attributes))))


; MARK: Characters
; ----------------------------
[
  (anchor_name)
  (alias_name)
] @characters
