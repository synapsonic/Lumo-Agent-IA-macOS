import ServiceManagement

@MainActor
final class AutoLaunchService {
    static let shared = AutoLaunchService()
    func setEnabled(_ enabled:Bool) async throws {
        if enabled {
            if SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
    }
}
