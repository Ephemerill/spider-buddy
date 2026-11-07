// Open at login. Windows uses the Run registry key instead; filled in with the shell.
import Foundation
public final class SMAppService: @unchecked Sendable {
    public enum Status: Int, Sendable { case notRegistered, enabled, requiresApproval, notFound }
    public static let mainApp = SMAppService()
    public var status: Status = .notRegistered
    public func register() throws { status = .enabled }
    public func unregister() throws { status = .notRegistered }
}
