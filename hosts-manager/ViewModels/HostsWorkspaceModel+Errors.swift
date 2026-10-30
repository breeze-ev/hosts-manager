import Foundation

extension HostsWorkspaceModel {
    func handleWriteFailure(_ error: Error, profileID: UUID?) {
        if error is HostsStateRecoveryRequiredError {
            showStateRecoveryWarning = true
            return
        }
        if error is HostsWriteStateReconciliationError {
            stateCommitFailed = true
            persistReconciliationBaseline()
            showStateRecoveryWarning = true
            return
        }
        if let conflict = error as? HostsWriteConflictError {
            if conflict.profileID == profileID {
                selection = .profiles
                selectedProfileID = conflict.profileID
                applyDraftText = sourceDrafts[conflict.profileID]
                showApply = true
            }
            return
        }
        if error is HostsWriteAbortedError {
            return
        }
        if error is HostsWriteCommitError {
            stateCommitFailed = true
            hasPendingAppliedProfileSelection = true
            if let managedHostnames = HostsReconciliationBaselineStore.load()?.managedHostnames {
                managedHostnamesBaseline = Set(managedHostnames)
            }
            if let content = try? HostsWriter.readContent() {
                lastKnownHostsFingerprint = HostsReconciliation.canonical(content)
            }
            persistReconciliationBaseline()
            showStateRecoveryWarning = true
            return
        }
        operationError = localizedError(error)
    }

    func localizedError(_ error: Error) -> String {
        if error is HostsStateRecoveryRequiredError {
            return l10n.s(
                "配置状态尚未恢复，写入已暂停。",
                "Profile state recovery is pending; writes are paused."
            )
        }
        if error is HostsWriteStateReconciliationError {
            return l10n.s(
                "/etc/hosts 已写入，但配置状态未能完整同步。请先恢复配置状态。",
                "/etc/hosts was written, but the profile state is not fully synchronized. Recover the profile state first."
            )
        }
        if error is HostsWriteConflictError {
            return l10n.s(
                "配置与其它已启用配置存在主机名冲突，未写入系统。",
                "The profile conflicts with another active profile; nothing was written."
            )
        }
        if error is HostsWriteAbortedError {
            return l10n.s(
                "写入已取消，配置状态未变更。",
                "The write was cancelled; profile state was not changed."
            )
        }
        if let commitError = error as? HostsWriteCommitError {
            return l10n.s(
                "/etc/hosts 已写入，但配置状态保存失败。请检查磁盘空间后重试同步。\n\(commitError.underlying.localizedDescription)",
                "/etc/hosts was written, but the profile state could not be saved. Check available disk space and resync.\n\(commitError.underlying.localizedDescription)"
            )
        }
        if let writeError = error as? HostsWriteError {
            switch writeError {
            case .invalidContent:
                return l10n.s(
                    "内容包含无效的 IP、主机名或控制字符。",
                    "The content contains an invalid IP address, hostname, or control character."
                )
            case .authorizationFailed:
                return l10n.s(
                    "无法通过后台写入助手授权。",
                    "The background writer helper rejected the request."
                )
            case .helperUnavailable:
                return l10n.s(
                    "后台写入助手不可用。请在设置中启用，并在“系统设置 → 通用 → 登录项与扩展”中批准后重试。",
                    "The background writer helper is unavailable. Enable it in Settings and approve it in System Settings > General > Login Items & Extensions."
                )
            case .writeFailed:
                return l10n.s("写入 /etc/hosts 失败。", "Failed to write /etc/hosts.")
            case .readFailed:
                return l10n.s("无法读取 /etc/hosts。", "Unable to read /etc/hosts.")
            case .verificationFailed:
                return l10n.s(
                    "写入后校验失败，请检查 hosts 文件。",
                    "Verification failed after writing /etc/hosts."
                )
            case .timedOut:
                return l10n.s(
                    "后台写入助手响应超时。",
                    "The background writer helper timed out."
                )
            }
        }
        return error.localizedDescription
    }
}
