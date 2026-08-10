//
//  AgentHookInstaller.swift
//  boringNotch
//
//  Deploys the status bridge scripts and registers them with
//  Claude Code (~/.claude/settings.json), Codex (~/.codex/hooks.json), and
//  opencode (~/.config/opencode/plugins/).
//

import Foundation

enum AgentHookInstaller {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static let supportDirectory = home.appendingPathComponent(".boringnotch", isDirectory: true)
    static let hookScriptURL = supportDirectory.appendingPathComponent("agent_hook.py")
    static let claudeSettingsURL = home.appendingPathComponent(".claude/settings.json")
    static let codexHooksURL = home.appendingPathComponent(".codex/hooks.json")
    static let openCodePluginURL = home.appendingPathComponent(
        ".config/opencode/plugins/boringnotch.js")

    // MARK: - Status

    static func isClaudeInstalled() -> Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
            let text = String(data: data, encoding: .utf8)
        else { return false }
        return text.contains("agent_hook.py")
    }

    static func isOpenCodeInstalled() -> Bool {
        FileManager.default.fileExists(atPath: openCodePluginURL.path)
    }

    static func isCodexInstalled() -> Bool {
        guard let data = try? Data(contentsOf: codexHooksURL),
            let text = String(data: data, encoding: .utf8)
        else { return false }
        return text.contains("agent_hook.py codex")
    }

    // MARK: - Claude Code

    private static let claudeEvents: [(event: String, usesMatcher: Bool)] = [
        ("SessionStart", false),
        ("UserPromptSubmit", false),
        ("PreToolUse", true),
        ("PostToolUse", true),
        ("Notification", false),
        ("Stop", false),
        ("SessionEnd", false),
    ]

    private static func claudeHookCommand(for event: String) -> String {
        "/usr/bin/python3 \(hookScriptURL.path) claude \(event)"
    }

    private static func codexHookCommand(for event: String) -> String {
        "/usr/bin/python3 \(hookScriptURL.path) codex \(event)"
    }

    private static func hookEntryContainsBridge(_ entry: [String: Any], tool: String) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains {
            ($0["command"] as? String)?.contains("agent_hook.py \(tool)") == true
        }
    }

    static func installClaude() throws {
        try writeHookScript()

        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: claudeSettingsURL.path),
            let data = try? Data(contentsOf: claudeSettingsURL),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = parsed
            let backup = claudeSettingsURL.appendingPathExtension("boringnotch-backup")
            if !fm.fileExists(atPath: backup.path) {
                try? fm.copyItem(at: claudeSettingsURL, to: backup)
            }
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, usesMatcher) in claudeEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if entries.contains(where: { hookEntryContainsBridge($0, tool: "claude") }) { continue }
            var entry: [String: Any] = [
                "hooks": [
                    ["type": "command", "command": claudeHookCommand(for: event)]
                ]
            ]
            if usesMatcher { entry["matcher"] = "" }
            entries.append(entry)
            hooks[event] = entries
        }
        settings["hooks"] = hooks

        try fm.createDirectory(
            at: claudeSettingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: claudeSettingsURL, options: .atomic)
    }

    static func uninstallClaude() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeSettingsURL.path),
            let data = try? Data(contentsOf: claudeSettingsURL),
            var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var hooks = settings["hooks"] as? [String: Any]
        else { return }

        for (event, entries) in hooks {
            guard var list = entries as? [[String: Any]] else { continue }
            list.removeAll(where: { hookEntryContainsBridge($0, tool: "claude") })
            if list.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = list
            }
        }
        settings["hooks"] = hooks

        let newData = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: claudeSettingsURL, options: .atomic)
    }

    private static let codexEvents = [
        "SessionStart",
        "UserPromptSubmit",
        "PreToolUse",
        "PostToolUse",
        "PermissionRequest",
        "Stop",
        "SubagentStart",
        "SubagentStop",
        "SessionEnd",
    ]

    static func installCodex() throws {
        try writeHookScript()

        let fm = FileManager.default
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: codexHooksURL.path),
            let data = try? Data(contentsOf: codexHooksURL),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            settings = parsed
            let backup = codexHooksURL.appendingPathExtension("boringnotch-backup")
            if !fm.fileExists(atPath: backup.path) {
                try? fm.copyItem(at: codexHooksURL, to: backup)
            }
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in codexEvents {
            var entries = hooks[event] as? [[String: Any]] ?? []
            if entries.contains(where: { hookEntryContainsBridge($0, tool: "codex") }) { continue }
            entries.append([
                "hooks": [
                    ["type": "command", "command": codexHookCommand(for: event)]
                ]
            ])
            hooks[event] = entries
        }
        settings["hooks"] = hooks

        try fm.createDirectory(
            at: codexHooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: codexHooksURL, options: .atomic)
    }

    static func uninstallCodex() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: codexHooksURL.path),
            let data = try? Data(contentsOf: codexHooksURL),
            var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var hooks = settings["hooks"] as? [String: Any]
        else { return }

        for (event, entries) in hooks {
            guard var list = entries as? [[String: Any]] else { continue }
            list.removeAll(where: { hookEntryContainsBridge($0, tool: "codex") })
            if list.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = list
            }
        }
        settings["hooks"] = hooks

        let newData = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: codexHooksURL, options: .atomic)
    }

    // MARK: - opencode

    static func installOpenCode() throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: openCodePluginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try openCodePluginSource.write(to: openCodePluginURL, atomically: true, encoding: .utf8)
    }

    static func uninstallOpenCode() throws {
        try? FileManager.default.removeItem(at: openCodePluginURL)
    }

    // MARK: - Shared hook script

    private static func writeHookScript() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: AgentStatusManager.statusDirectory, withIntermediateDirectories: true)
        try hookScriptSource.write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)
    }

    private static let hookScriptSource = #"""
#!/usr/bin/env python3
"""boring.notch agent status bridge (Claude Code and Codex hooks)."""
import json
import fcntl
import os
import re
import sys
import time

STATUS_DIR = os.path.expanduser("~/.boringnotch/agents")

STATE_MAP = {
    "SessionStart": "running",
    "UserPromptSubmit": "running",
    "PreToolUse": "running",
    "PostToolUse": "running",
    "Notification": "waiting",
    "Stop": "done",
    "SubagentStart": "running",
    "SubagentStop": "done",
}

TERMINAL_EVENTS = {"Stop", "SubagentStop", "SessionEnd"}


def sanitize(value):
    return re.sub(r"[^A-Za-z0-9_-]", "_", str(value))[:64] or "unknown"


def main():
    tool = sys.argv[1] if len(sys.argv) > 1 else "claude"
    event = sys.argv[2] if len(sys.argv) > 2 else ""

    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    session_id = sanitize(
        payload.get("session_id")
        or payload.get("thread_id")
        or payload.get("conversation_id")
        or "unknown"
    )
    agent_id = payload.get("agent_id") if event in ("SubagentStart", "SubagentStop") else ""
    if agent_id:
        session_id = "%s-%s" % (session_id, sanitize(agent_id))
    path = os.path.join(STATUS_DIR, "%s-%s.json" % (tool, session_id))
    lock_path = path + ".lock"

    state = STATE_MAP.get(event, "running")
    if event == "PermissionRequest":
        state = "waiting"
    if event == "SessionEnd" and tool == "codex":
        state = "done"
    label = (
        payload.get("message")
        or payload.get("tool_name")
        or payload.get("tool")
        or ""
    )
    if event == "SessionEnd" and tool == "codex" and not label:
        label = "Session ended"
    if not isinstance(label, str):
        label = str(label)

    os.makedirs(STATUS_DIR, exist_ok=True)
    turn_id = str(payload.get("turn_id") or "")
    with open(lock_path, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if event == "SessionEnd" and tool != "codex":
                try:
                    os.remove(path)
                except OSError:
                    pass
                return

            existing = {}
            try:
                with open(path) as existing_file:
                    existing = json.load(existing_file)
            except Exception:
                pass

            if (
                event not in TERMINAL_EVENTS
                and state != "done"
                and existing.get("state") == "done"
                and turn_id
                and existing.get("turnID") == turn_id
            ):
                return

            started_at = existing.get("startedAt", time.time())
            data = {
                "id": "%s-%s" % (tool, session_id),
                "tool": tool,
                "state": state,
                "label": label,
                "cwd": payload.get("cwd") or os.getcwd(),
                "startedAt": started_at,
                "updatedAt": time.time(),
                "turnID": turn_id,
            }

            tmp_path = "%s.%s.tmp" % (path, os.getpid())
            with open(tmp_path, "w") as tmp:
                json.dump(data, tmp)
            os.replace(tmp_path, path)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


if __name__ == "__main__":
    main()
"""#

    private static let openCodePluginSource = #"""
// boring.notch agent status bridge (opencode plugin)
import { mkdirSync, readFileSync, renameSync, unlinkSync, writeFileSync } from "node:fs"
import { join } from "node:path"

const STATUS_DIR = join(process.env.HOME || "~", ".boringnotch", "agents")

function sanitize(value) {
  return String(value).replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 64) || "unknown"
}

function sessionFile(sessionID) {
  return join(STATUS_DIR, `opencode-${sanitize(sessionID)}.json`)
}

function write(sessionID, state, label, cwd) {
  try {
    mkdirSync(STATUS_DIR, { recursive: true })
    const path = sessionFile(sessionID)
    let startedAt = Date.now() / 1000
    try {
      startedAt = JSON.parse(readFileSync(path, "utf8")).startedAt || startedAt
    } catch {}
    const tmp = `${path}.tmp`
    writeFileSync(
      tmp,
      JSON.stringify({
        id: `opencode-${sanitize(sessionID)}`,
        tool: "opencode",
        state,
        label: label || "",
        cwd: cwd || "",
        startedAt,
        updatedAt: Date.now() / 1000,
      })
    )
    renameSync(tmp, path)
  } catch {}
}

function remove(sessionID) {
  try {
    unlinkSync(sessionFile(sessionID))
  } catch {}
}

export const BoringNotchPlugin = async ({ directory }) => {
  let lastSessionID = "unknown"
  return {
    event: async ({ event }) => {
      const props = event.properties || {}
      const sessionID =
        props.sessionID ||
        (props.info && props.info.id) ||
        (props.status && props.status.sessionID) ||
        "unknown"
      if (sessionID !== "unknown") lastSessionID = sessionID
      switch (event.type) {
        case "session.status": {
          const status = props.status && props.status.type
          if (status === "busy" || status === "retry") {
            write(sessionID, "running", "", directory)
          } else if (status === "idle") {
            write(sessionID, "done", "", directory)
          }
          break
        }
        case "permission.asked":
          write(sessionID, "waiting", "Permission requested", directory)
          break
        case "permission.replied":
          write(sessionID, "running", "", directory)
          break
        case "session.idle":
          write(sessionID, "done", "", directory)
          break
        case "session.error":
          write(sessionID, "waiting", "Session error", directory)
          break
        case "session.deleted":
          remove(sessionID)
          break
      }
    },
    "tool.execute.before": async (input) => {
      const sid = (input && input.sessionID) || lastSessionID
      const tool = input && input.tool ? String(input.tool) : ""
      write(sid, "running", tool, directory)
    },
  }
}
"""#
}
