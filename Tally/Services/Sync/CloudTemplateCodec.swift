import Foundation
import CloudKit

/// One private zone and stable UUID record names prevent duplicate records across devices and retries.
@MainActor
enum CloudTemplateCodec {
    static let containerID = "iCloud.gale-k.Tally"
    static let zoneID = CKRecordZone.ID(zoneName: "TallyLibrary")
    static let recordType = "TallyTemplate"
    static func recordID(_ id: UUID, zoneID: CKRecordZone.ID? = nil) -> CKRecord.ID { CKRecord.ID(recordName: id.uuidString, zoneID: zoneID ?? Self.zoneID) }

    static func systemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding()
        return coder.encodedData
    }
    static func record(for change: CloudTemplateChange, systemFields: Data?, assetDirectory: URL, zoneID: CKRecordZone.ID? = nil) throws -> CKRecord {
        try change.validate()
        let record: CKRecord
        if let systemFields {
            let coder = try NSKeyedUnarchiver(forReadingFrom: systemFields)
            coder.requiresSecureCoding = true
            defer { coder.finishDecoding() }
            guard let decoded = CKRecord(coder: coder), decoded.recordID == recordID(change.id, zoneID: zoneID), decoded.recordType == recordType else {
                throw LibrarySyncError.invalidRecord
            }
            record = decoded
        } else { record = CKRecord(recordType: recordType, recordID: recordID(change.id, zoneID: zoneID)) }
        record["version"] = 1
        record["editedAt"] = change.modifiedAt
        record["revision"] = change.revision
        record["deleted"] = change.isDeleted
        if let template = change.template {
            // CKAsset avoids truncating a valid long-text template to fit an inline record-data limit.
            let data = try JSONEncoder().encode(template)
            guard data.count <= DrinkExportService.maximumBytes else { throw LibraryTransferError.tooLarge }
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
            let url = assetDirectory.appendingPathComponent(change.revision).appendingPathExtension("json")
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            record["template"] = CKAsset(fileURL: url)
        } else { record["template"] = nil }
        return record
    }
    /// Acknowledgements need identity/revision only, so cached asset-file availability cannot block a successful upload.
    static func acknowledgedRevision(from record: CKRecord, zoneID: CKRecordZone.ID? = nil) throws -> (id: UUID, revision: String) {
        guard record.recordType == recordType, record.recordID.zoneID == (zoneID ?? Self.zoneID),
              let id = UUID(uuidString: record.recordID.recordName), record["version"] as? Int == 1,
              let revision = record["revision"] as? String, UUID(uuidString: revision) != nil else { throw LibrarySyncError.invalidRecord }
        return (id, revision)
    }

    static func change(from record: CKRecord, zoneID: CKRecordZone.ID? = nil) throws -> CloudTemplateChange {
        guard record.recordType == recordType, record.recordID.zoneID == (zoneID ?? Self.zoneID),
              let id = UUID(uuidString: record.recordID.recordName), let version = record["version"] as? Int, version == 1,
              let date = record["editedAt"] as? Date, let revision = record["revision"] as? String,
              let deleted = record["deleted"] as? Bool else { throw LibrarySyncError.invalidRecord }
        var template: SavedDrinkRecord?
        if !deleted {
            guard let asset = record["template"] as? CKAsset, let url = asset.fileURL else { throw LibrarySyncError.invalidRecord }
            template = try JSONDecoder().decode(SavedDrinkRecord.self, from: DrinkExportService.readFile(url))
        }
        let result = CloudTemplateChange(id: id, modifiedAt: date, revision: revision, template: template)
        try result.validate()
        return result
    }
}
