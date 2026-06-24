import AppKit

func computeDiff(old: String, new: String) -> [DiffRow] {
  GitDiff.rows(old: old, new: new)
}
