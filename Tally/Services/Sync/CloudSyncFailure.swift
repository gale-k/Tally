import CloudKit

/// A rejected optimistic save is expected when another client edited the record. The delegate resolves its server copy.
enum CloudSyncFailure {
    static func isRecordConflict(_ error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        switch cloud.code {
        case .serverRecordChanged: return cloud.serverRecord != nil
        case .partialFailure:
            guard let failures = cloud.partialErrorsByItemID, !failures.isEmpty else { return false }
            // Never hide a quota, authentication, or transport failure mixed into a batch of conflicts.
            return failures.values.allSatisfy(isRecordConflict)
        default: return false
        }
    }
}
