import AppKit

@MainActor enum ClientRestart {
    static let bundleID = "com.openai.codex"

    // Separated from AppKit so ordering, cancellation and timeout can be tested.
    static func perform(requestQuit: () -> Bool, hasExited: () -> Bool,
                        wait: () async throws -> Void, launch: () async throws -> Void,
                        attempts: Int = 120) async throws {
        guard requestQuit() else {
            throw AppError(message: Copy("The account was switched, but Codex declined to quit. Finish any save or confirmation dialogs, then restart it manually.", "账号已切换，但 Codex 未接受退出请求。请完成保存或确认对话框后手动重启。"))
        }
        for _ in 0..<attempts {
            if hasExited() { try await launch(); return }
            try await wait()
        }
        if hasExited() { try await launch(); return }
        throw AppError(message: Copy("The account was switched, but Codex did not quit within 30 seconds. Finish pending tasks or dialogs and restart manually. No process was force-quit.", "账号已切换，但 Codex 未能在 30 秒内退出。请处理未完成的任务或对话框后手动重启；未强制结束进程。"))
    }

    static func restart() async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard let url = running.first?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AppError(message: Copy("The account was switched, but the Codex app could not be found. Install or open it manually.", "账号已切换，但找不到 Codex 客户端。请安装或手动打开客户端。"))
        }
        try await perform(requestQuit: {
            var accepted = true
            for application in running where !application.isTerminated {
                if !application.terminate() { accepted = false }
            }
            return accepted
        }, hasExited: {
            running.allSatisfy { $0.isTerminated }
        }, wait: {
            try await Task.sleep(nanoseconds: 250_000_000)
        }, launch: {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            do {
                let application = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
                guard application.bundleIdentifier == bundleID, !application.isTerminated else {
                    throw AppError(message: Copy("Codex startup could not be verified. Open the app manually.", "Codex 启动结果未能确认，请手动打开客户端。"))
                }
            } catch {
                throw AppError(message: Copy("The account was switched and Codex quit, but could not reopen. Start it from Applications.", "账号已切换，Codex 已退出，但重新打开失败。请从应用程序目录手动启动。"))
            }
        })
    }
}
