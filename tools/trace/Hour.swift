import Foundation

// Test builds only: the spider's behaviour depends on the hour of the day
// (Spider.swift asks the calendar). tools/trace.sh rewrites those two calls to
// read this instead, so a trace does not depend on when it was recorded.
// TR_HOUR (0-23, default 14: broad daylight; use 23 for night behaviour).
let traceHour: Int = Int(ProcessInfo.processInfo.environment["TR_HOUR"] ?? "14") ?? 14
