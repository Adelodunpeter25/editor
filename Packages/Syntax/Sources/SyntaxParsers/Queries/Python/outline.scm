; Containers
(class_definition
  name: (identifier) @outline.container)

; Values
(assignment
  left: (identifier) @outline.value)

; Functions
(function_definition
  name: (identifier) @outline.function
  parameters: (parameters) @outline.signature.parameters)
