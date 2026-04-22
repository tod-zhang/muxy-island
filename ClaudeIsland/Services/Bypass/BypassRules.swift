//
//  BypassRules.swift
//  ClaudeIsland
//
//  Per-project persistent bypass list. When the user taps Bypass on a tool
//  approval request, we remember the tool name keyed by the session's cwd
//  so every future Claude/Codex session running in the same project skips
//  the approval UI for that tool.
//
//  Persistence is UserDefaults (single JSON blob) — small enough to fit,
//  no schema migrations needed. Rules survive app restarts. Scope is
//  strictly per-cwd (not global) so trusting `Bash` in ~/my-project
//  never leaks into a different project.
//

import Combine
import Foundation

final class BypassRules: @unchecked Sendable {
    static let shared = BypassRules()

    /// Published snapshot — UI subscribes to redraw the management list
    /// whenever rules change. Keyed by cwd, values are tool-name sets.
    let changes = CurrentValueSubject<[String: Set<String>], Never>([:])

    private let lock = NSLock()
    private var rulesMap: [String: Set<String>] = [:]

    private static let defaultsKey = "muxyIsland.bypassRules"

    private init() {
        load()
    }

    // MARK: - Read

    /// Total number of (cwd, tool) pairs — shown as a badge on the menu row.
    var totalCount: Int {
        lock.lock(); defer { lock.unlock() }
        return rulesMap.values.reduce(0) { $0 + $1.count }
    }

    /// Snapshot of the whole map. Used by the management UI.
    var snapshot: [String: Set<String>] {
        lock.lock(); defer { lock.unlock() }
        return rulesMap
    }

    /// Whether `tool` is bypassed for sessions rooted at `cwd`.
    func allows(cwd: String, tool: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return rulesMap[cwd]?.contains(tool) ?? false
    }

    /// Set of bypassed tool names for a given cwd. Returns empty set if
    /// the project has no rules. Used to seed new SessionStates.
    func tools(forCwd cwd: String) -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return rulesMap[cwd] ?? []
    }

    // MARK: - Write

    /// Add `tool` to the bypass set for `cwd`. Idempotent.
    func record(cwd: String, tool: String) {
        lock.lock()
        var tools = rulesMap[cwd] ?? []
        tools.insert(tool)
        rulesMap[cwd] = tools
        let snapshot = rulesMap
        saveLocked()
        lock.unlock()
        changes.send(snapshot)
    }

    /// Drop a specific (cwd, tool) rule — called from the management UI.
    func remove(cwd: String, tool: String) {
        lock.lock()
        guard var tools = rulesMap[cwd] else {
            lock.unlock(); return
        }
        tools.remove(tool)
        if tools.isEmpty {
            rulesMap.removeValue(forKey: cwd)
        } else {
            rulesMap[cwd] = tools
        }
        let snapshot = rulesMap
        saveLocked()
        lock.unlock()
        changes.send(snapshot)
    }

    /// Wipe all rules for a single project.
    func clearProject(cwd: String) {
        lock.lock()
        rulesMap.removeValue(forKey: cwd)
        let snapshot = rulesMap
        saveLocked()
        lock.unlock()
        changes.send(snapshot)
    }

    /// Wipe every rule — "reset all".
    func clearAll() {
        lock.lock()
        rulesMap.removeAll()
        saveLocked()
        lock.unlock()
        changes.send([:])
    }

    // MARK: - Persistence

    private func saveLocked() {
        // Set isn't Codable directly; serialize as [String: [String]].
        let encodable = rulesMap.mapValues { Array($0).sorted() }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }
        lock.lock()
        rulesMap = decoded.mapValues { Set($0) }
        let snapshot = rulesMap
        lock.unlock()
        changes.send(snapshot)
    }
}
