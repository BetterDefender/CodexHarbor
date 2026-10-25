import Foundation
@main struct RestartTests {
    @MainActor static func main() async throws {
        var events: [String] = []
        var polls = 0
        try await ClientRestart.perform(requestQuit: { events.append("quit"); return true }, hasExited: { polls >= 2 }, wait: { polls += 1 }, launch: { events.append("launch") })
        assert(events == ["quit", "launch"] && polls == 2)
        var launched = false
        do {
            try await ClientRestart.perform(requestQuit: { false }, hasExited: { true }, wait: {}, launch: { launched = true })
            fatalError("Rejected quit was accepted")
        } catch { assert(!launched) }
        do {
            try await ClientRestart.perform(requestQuit: { true }, hasExited: { false }, wait: {}, launch: { launched = true }, attempts: 2)
            fatalError("Timeout was accepted")
        } catch { assert(!launched) }
        try await ClientRestart.perform(requestQuit: { true }, hasExited: { true }, wait: {}, launch: { launched = true })
        assert(launched)
        print("PASS: quit before launch, rejected quit, timeout, already stopped client")
    }
}
