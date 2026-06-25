import Cfff
import Foundation

class FffInstance {
  private let handle: UnsafeMutableRawPointer

  init?(basePath: String, watch: Bool = true, enableContentIndexing: Bool = true) {
    var options = FffCreateOptions()
    options.version = UInt32(FFF_CREATE_OPTIONS_VERSION)
    options.base_path = (basePath as NSString).utf8String
    options.frecency_db_path = nil
    options.history_db_path = nil
    options.enable_mmap_cache = true
    options.enable_content_indexing = enableContentIndexing
    options.watch = watch
    options.ai_mode = false
    options.log_file_path = nil
    options.log_level = nil
    options.cache_budget_max_files = 0
    options.cache_budget_max_bytes = 0
    options.cache_budget_max_file_size = 0
    options.enable_fs_root_scanning = false
    options.enable_home_dir_scanning = false

    guard let result = fff_create_instance_with(&options) else { return nil }
    defer { fff_free_result(result) }

    guard result.pointee.success, let h = result.pointee.handle else {
      if let err = result.pointee.error {
        print("FFF init error: \(String(cString: err))")
      }
      return nil
    }
    self.handle = h
  }

  deinit {
    fff_destroy(handle)
  }

  struct SearchResult {
    let relativePath: String
    let fileName: String
    let size: UInt64
    let score: Int
    let gitStatus: String
  }

  func search(query: String, maxResults: Int = 100) -> [SearchResult] {
    guard
      let result = fff_search(
        handle,
        query,
        nil,
        4,
        0,
        UInt32(maxResults),
        100,
        3
      )
    else { return [] }
    defer { fff_free_result(result) }

    guard result.pointee.success,
      let sResultPtr = result.pointee.handle?.assumingMemoryBound(to: FffSearchResult.self)
    else {
      return []
    }
    defer { fff_free_search_result(sResultPtr) }

    let count = Int(sResultPtr.pointee.count)
    guard count > 0, let items = sResultPtr.pointee.items else { return [] }

    var results: [SearchResult] = []
    for i in 0..<count {
      let item = items[i]
      let rel = item.relative_path != nil ? String(cString: item.relative_path!) : ""
      let name = item.file_name != nil ? String(cString: item.file_name!) : ""
      let gitStatus = item.git_status != nil ? String(cString: item.git_status!) : ""
      let score = sResultPtr.pointee.scores != nil ? Int(sResultPtr.pointee.scores![i].total) : 0
      results.append(
        SearchResult(
          relativePath: rel, fileName: name, size: item.size, score: score, gitStatus: gitStatus))
    }
    return results
  }

  struct GrepMatch {
    let relativePath: String
    let fileName: String
    let lineContent: String
    let lineNumber: Int
    let col: Int
  }

  func liveGrep(query: String, mode: UInt8 = 0, pageSize: Int = 100, fileOffset: Int = 0)
    -> [GrepMatch]
  {
    guard
      let result = fff_live_grep(
        handle,
        query,
        mode,
        10 * 1024 * 1024,
        100,
        true,
        UInt32(fileOffset),
        UInt32(pageSize),
        150,
        0,
        0,
        false
      )
    else { return [] }
    defer { fff_free_result(result) }

    guard result.pointee.success,
      let gResultPtr = result.pointee.handle?.assumingMemoryBound(to: FffGrepResult.self)
    else {
      return []
    }
    defer { fff_free_grep_result(gResultPtr) }

    let count = Int(gResultPtr.pointee.count)
    guard count > 0, let items = gResultPtr.pointee.items else { return [] }

    var matches: [GrepMatch] = []
    for i in 0..<count {
      let match = items[i]
      let rel = match.relative_path != nil ? String(cString: match.relative_path!) : ""
      let name = match.file_name != nil ? String(cString: match.file_name!) : ""
      let content = match.line_content != nil ? String(cString: match.line_content!) : ""
      matches.append(
        GrepMatch(
          relativePath: rel,
          fileName: name,
          lineContent: content,
          lineNumber: Int(match.line_number),
          col: Int(match.col)
        ))
    }
    return matches
  }
}
