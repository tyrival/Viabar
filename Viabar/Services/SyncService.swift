import Foundation
import CloudKit

// MARK: - Sync Status

enum SyncStatus: String {
    case idle
    case importing
    case exporting
    case paused
    case resolving
    case error
}

// MARK: - Conflict Resolution

enum ConflictResolution {
    /// 最后写入覆盖
    case lastWriterWins
    /// 保留本地版本，等待手动处理
    case manual
}

// MARK: - Cloud Sync Configuration

struct CloudSyncConfig {
    let containerIdentifier: String
    let enableSilentPush: Bool
    let conflictResolution: ConflictResolution

    static let `default` = CloudSyncConfig(
        containerIdentifier: "iCloud.com.viabar",
        enableSilentPush: true,
        conflictResolution: .lastWriterWins
    )
}

// MARK: - Sync Event

struct SyncEvent: Identifiable {
    let id: UUID
    let status: SyncStatus
    let timestamp: Date
    let affectedEntityCount: Int
    let errorDescription: String?

    init(
        status: SyncStatus,
        affectedEntityCount: Int = 0,
        error: Error? = nil
    ) {
        self.id = UUID()
        self.status = status
        self.timestamp = Date()
        self.affectedEntityCount = affectedEntityCount
        self.errorDescription = error?.localizedDescription
    }
}

// MARK: - CloudSyncService Protocol

/// iCloud 同步服务协议 —— Phase 2/3 实现
protocol CloudSyncServiceProtocol: AnyObject {
    var status: SyncStatus { get }
    var lastSyncDate: Date? { get }
    var config: CloudSyncConfig? { get }

    func configure(_ config: CloudSyncConfig)
    func requestSync()
    func handleRemoteChange(_ notification: CKNotification?)
    func handlePersistentStoreRemoteChange(_ notification: Notification)
    func resetSync()
}
