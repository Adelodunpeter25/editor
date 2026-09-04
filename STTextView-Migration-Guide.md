# STTextView Migration Guide

> **Status: migration attempted (untested).** `Package.swift` now depends on STTextView and targets
> macOS 14, and `CodeTextView`/`EditorViewController`/the find/format/highlighting extensions have been
> ported to STTextView's TextKit 2 API. This was written and reviewed in an environment with no macOS/
> Xcode/Swift toolchain, so **none of it has been compiled or run**. Build it locally, work through the
> Verification checklist below, and report back anything broken — see the inline `MIGRATION NOTE`
> comments in `CodeTextView.swift`, `EditorViewController.swift`, `EditorFind.swift`, and
> `STTextViewRangeUtil.swift` for the specific TextKit 1 → TextKit 2 API translations and their known
> risk areas (block-cursor rendering, find/replace highlighting via `addAttributes` instead of temporary
> attributes, and the git-gutter overlay repainting from `enumerateTextLayoutFragments`).

## Purpose

This guide describes how to evaluate and, if appropriate, migrate the Editor application's custom text editor to [STTextView](https://github.com/krzyzanowskim/STTextView).

The goal is to reduce custom text-layout maintenance while preserving the application's existing sessions, tabs, file handling, syntax highlighting, formatting, Git integration, Markdown preview, and user workflows.

## Important: work from a local copy

Do **not** migrate directly in the live Git checkout or against the shared repository.

Before starting:

1. Close the Editor application and any local development instance.
2. Make a complete local copy of the project directory.
3. Perform the STTextView evaluation and migration only in that local copy.
4. Keep the original checkout untouched as the fallback/reference implementation.
5. Do not push migration work to the shared Git repository until the local copy has been tested and reviewed.

Example:

```bash
# From the directory containing the project
cp -R editor editor-sttextview-local
cd editor-sttextview-local
```

The copy should include the source tree, SwiftPM files, local packages, bundled grammar resources, and any required native libraries. Avoid copying `.build` if a clean dependency/build evaluation is desired.

## Current editor architecture

The current editor is built with AppKit and TextKit 1:

```text
EditorViewController
├── CodeTextView
├── NSTextStorage
├── NSLayoutManager
├── NSTextContainer
├── syntax highlighting
├── find/replace
├── file watching
├── formatting
├── line-ending and indentation controls
├── Git gutter
└── status-bar integration
```

The surrounding application architecture should remain unchanged during the first migration attempt:

- `AppModel` and `Session` continue to own application/session state.
- `Tab` continues to represent open files and editor tabs.
- `CenterViewController` continues to create and cache tab content.
- `MarkdownViewController` continues to own the Source/Preview relationship.
- `ImageViewController`, diff views, terminals, search, and Git views remain unchanged.
- Existing file watchers, formatters, persistence, and dirty-state callbacks remain the source of truth.

## Compatibility checks before migration

### macOS deployment target

The application currently targets macOS 13. The current STTextView project documentation lists macOS 14 as its macOS requirement.

Resolve this before adopting it:

- Decide whether the application can raise its minimum supported macOS version to 14; or
- Identify an older compatible STTextView release and evaluate its limitations.

Do not change the deployment target permanently during the first prototype unless that decision has been approved.

### License review

Review STTextView's current license and determine whether it is compatible with the application's distribution model. If the license does not fit, investigate the available commercial licensing option before integrating the dependency.

### Dependency and package review

Add STTextView only in the local copy first. Confirm the exact package version, supported platforms, transitive dependencies, and release behavior before changing the primary `Package.swift`.

## Recommended migration strategy

Use a staged migration rather than replacing the editor in one pass.

### Phase 1: Build a local prototype

In the local copy:

1. Add STTextView as a temporary SwiftPM dependency.
2. Create a small AppKit prototype or temporary editor path.
3. Load a representative file into STTextView.
4. Verify basic typing, selection, copy/paste, undo/redo, scrolling, and saving.
5. Confirm the app still builds with the existing macOS target decision.

Keep the prototype isolated from the production editor controller.

### Phase 2: Compare core editor behavior

Test STTextView against the current `CodeTextView` with:

- Small and large files
- Long lines and wrapped lines
- Empty files
- Unicode and emoji
- Mixed line endings
- Tabs and spaces
- Very large selections
- Undo after formatter replacements
- External file changes
- Read-only content
- Keyboard shortcuts
- Search and replace
- Jump-to-line behavior

Record regressions instead of immediately adding workarounds.

### Phase 3: Introduce an editor abstraction

Create a narrow internal abstraction around the operations used by `EditorViewController`, such as:

- Read and replace text
- Read and set selection
- Focus the editor
- Scroll to a line
- Apply attributes/highlighting
- Observe text changes
- Replace text while preserving the cursor

The abstraction should allow the existing TextKit 1 editor and an STTextView-backed editor to coexist temporarily. Avoid spreading STTextView-specific APIs throughout the application.

### Phase 4: Port the editor controller incrementally

Move the existing responsibilities one at a time:

1. Text loading and display
2. Text-change and dirty-state callbacks
3. Saving and Save As
4. Focus and selection handling
5. Find/replace
6. Jump-to-line and centering
7. External file reloads
8. Formatting and cursor preservation
9. Line-ending conversion
10. Indentation conversion
11. Font and theme updates
12. Syntax highlighting
13. Git gutter

After each step, build and manually verify the related workflow.

### Phase 5: Evaluate native STTextView features

Only after the basic integration works, evaluate whether STTextView can replace custom code for:

- Line numbers and gutter rendering
- Current-line highlighting
- Incremental search
- Multi-cursor editing
- Completion support
- Annotations and diagnostics
- Long-document scrolling

Do not remove existing implementations until the replacement behavior is verified in the application.

### Phase 6: Markdown and wrapped editors

Markdown and SVG files embed an editable source editor behind a preview/image toggle. Verify that the STTextView-backed editor can be hosted by `MarkdownViewController` without changing:

- Preview as the default Markdown mode
- Source/Preview switching
- Live preview refreshes
- Unsaved source edits
- Relative image resolution
- Search-result line reveals
- Rename/retarget behavior
- Dirty-state propagation

The rendered Markdown preview does not need STTextView; only the source editor is a migration candidate.

### Phase 7: Performance and stability validation

Compare the old and new editors using realistic project files. Measure or manually evaluate:

- Initial file-open latency
- Syntax-highlight latency
- Typing responsiveness
- Scrolling responsiveness
- Memory usage
- Large-file behavior
- Selection and caret stability after attribute updates
- CPU usage during editing

Test on every macOS version the application intends to support.

### Phase 8: Decide whether to adopt

Adopt STTextView only if it provides a clear improvement without unacceptable regressions in compatibility, licensing, performance, or maintenance complexity.

If the result is inconclusive, retain the current editor and document the findings. The prototype should remain disposable.

## Risk areas

### TextKit 1 versus TextKit 2

STTextView uses a TextKit 2-based implementation, while the current editor uses TextKit 1. Selection ranges, layout timing, text replacement, glyph measurement, and scrolling may behave differently.

### Syntax highlighting

The application already has Tree-sitter and TextMate highlighting. Test whether attributes can be applied efficiently without breaking STTextView's layout or undo behavior. Do not assume the STTextView Tree-sitter plugins are a drop-in replacement for the existing grammar/theme pipeline.

### Git gutter

The current Git gutter is coupled to the existing scroll view and text view. Determine whether it can use STTextView's gutter APIs or needs an adapter. Preserve added, modified, and deleted line markers.

### Find and replace

The current find UI is integrated with the editor controller and uses custom state. Compare it with STTextView's text-finder support before deciding whether to migrate or retain the existing UI.

### External changes and dirty state

The existing editor intentionally keeps local unsaved edits when an external file changes. Preserve this behavior exactly during migration.

### Formatter replacements

Formatting can replace the entire document while preserving the cursor and dirty state. Test this carefully because TextKit 2 document replacement may have different selection and undo semantics.

## Verification checklist

Before considering an STTextView migration successful:

- [ ] The app builds cleanly from the local copy.
- [ ] The original checkout remains available and unchanged as fallback.
- [ ] macOS deployment requirements are resolved.
- [ ] Licensing has been reviewed and approved.
- [ ] Files open and save correctly.
- [ ] Dirty indicators remain correct.
- [ ] Undo and redo work after normal edits and formatting.
- [ ] Find and replace work.
- [ ] Jump-to-line works and centers correctly.
- [ ] Syntax highlighting remains correct and responsive.
- [ ] Git gutter markers remain correct.
- [ ] External file-change behavior is preserved.
- [ ] Markdown opens in Preview mode by default.
- [ ] Markdown Source mode remains editable.
- [ ] Markdown live preview reflects unsaved edits.
- [ ] Rename and retarget behavior preserves unsaved edits.
- [ ] Large files remain responsive.
- [ ] Terminal, diff, search, image, and session workflows are unaffected.
- [ ] The migration has been reviewed before any shared-repository change.

## Suggested outcome

Treat STTextView as a promising prototype candidate, not an immediate replacement. Its source-editor features and TextKit 2 implementation could eliminate substantial custom text-layout work, but the macOS 14 requirement, TextKit migration, Git gutter integration, existing highlighting pipeline, and licensing need to be resolved first.
