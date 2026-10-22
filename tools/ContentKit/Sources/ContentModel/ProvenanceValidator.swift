import Foundation

public struct ProvenanceTransform: Codable {
    public let ref: String
    public let input: JobRecord
    public let output: JobRecord
    public let method: DerivationMethod
    public let evidenceRef: String
    public let evidenceHash: String
    public init(ref: String, input: JobRecord, output: JobRecord, method: DerivationMethod, evidenceRef: String, evidenceHash: String) {
        self.ref = ref; self.input = input; self.output = output; self.method = method
        self.evidenceRef = evidenceRef; self.evidenceHash = evidenceHash
    }
}
public struct ProvenanceHistory {
    let url: URL
    let sha256: String
    let records: [String: ContractRecord]
    public init(at url: URL) throws {
        self.url = url
        let data = try Data(contentsOf: url)
        sha256 = CKHash.sha256Hex(of: data)
        var records: [String: ContractRecord] = [:]
        for line in try CKJSONL.readLines(at: url) {
            let record = try ContractJSON.decode(Data(line.utf8))
            guard records.updateValue(record, forKey: record.recordId) == nil else { throw JobFailure("duplicate_history_record") }
        }
        self.records = records
    }
}
public enum ProvenanceValidator {
    /// Local work artifacts are evidence of work only, not external verification.
    /// Unavailable references remain explicit and cannot satisfy evidence closure.
    public static func validateLocalEvidence(_ provenance: Provenance, base: URL, history: ProvenanceHistory? = nil) throws {
        for field in provenance.payload.fields {
            for evidence in field.internalEvidenceRefs ?? [] {
                let url = try JobLedger.localURL(evidence.ref, base: base)
                guard evidence.availability == .available else { throw JobFailure("unresolved_internal_evidence:\(evidence.ref)") }
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true,
                      try CKHash.sha256Hex(ofFileAt: url) == evidence.sha256 else { throw JobFailure("internal_evidence_mismatch:\(evidence.ref)") }
                if let line = evidence.line {
                    let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
                    guard line <= lines.count, !lines[line - 1].isEmpty else { throw JobFailure("internal_evidence_line_missing") }
                }
            }
        }
        if let evidence = provenance.payload.migrationEvidence {
            let url = try JobLedger.localURL(evidence.historyRef, base: base)
            let archive = try history ?? ProvenanceHistory(at: url)
            guard archive.url == url, archive.sha256 == evidence.historySha256 else { throw JobFailure("migration_history_mismatch") }
            guard let original = archive.records[provenance.recordId], original.document.kind == .provenance,
                  original.document.revision + 1 == provenance.revision else { throw JobFailure("missing_migration_original") }
        }
    }
    public static func validate(_ provenance: Provenance, subject: any ContractDocumentInfo,
                                requiredFields: Set<String>, sourceIds: Set<String>, jobs: JobSnapshot,
                                reviews: [String: Review], transforms: [String: ProvenanceTransform],
                                humanModificationRefs: Set<String>, base: URL, history: ProvenanceHistory? = nil) throws {
        let p = provenance.payload
        try p.validate(recordId: provenance.recordId, schema: provenance.schema)
        guard try provenance.revisionHash() == provenance.contentSha256,
              try subject.revisionHash() == subject.contentSha256,
              p.subjectId == subject.recordId, p.subjectKind == subject.kind,
              p.subjectRevision == subject.revision, p.subjectContentSha256 == subject.contentSha256 else { throw JobFailure("provenance_subject_mismatch") }
        guard Set(p.fields.map(\.field)) == requiredFields else { throw JobFailure("provenance_field_coverage") }
        for field in p.fields {
            for source in field.sourceRefs {
                guard sourceIds.contains(source.sourceId) else { throw JobFailure("dangling_source_ref") }
                let operation: SourceOperation?
                switch field.method {
                case .reference: operation = .reference
                case .extract: operation = .extract
                case .adapt: operation = .adapt
                case .humanAuthored, .aiGenerated: operation = nil
                }
                if let operation, !source.operations.contains(operation) { throw JobFailure("source_method_mismatch") }
            }
        }
        try validateLocalEvidence(provenance, base: base, history: history)
        guard !p.fields.contains(where: { !($0.unverifiedRefs ?? []).isEmpty }) else { throw JobFailure("unverified_origin") }
        guard let event = jobs.events[p.workUnitRef], [.received, .validated, .quarantined].contains(event.state),
              event.receiptRef == p.runReceiptRef, let receipt = jobs.receipts[p.workUnitRef] else { throw JobFailure("missing_provenance_receipt") }
        try JobLedger.validateReceipt(receipt, binding: event.binding, base: base)
        guard receipt.binding.model == p.model, receipt.binding.promptHash == p.promptHash else { throw JobFailure("provenance_model_prompt_mismatch") }
        let final = JobRecord(recordId: subject.recordId, kind: subject.kind, revision: subject.revision, contentHash: subject.contentSha256)
        var current: JobRecord?
        guard Set(p.transformChain).count == p.transformChain.count else { throw JobFailure("duplicate_transform") }
        for ref in p.transformChain {
            guard let transform = transforms[ref], transform.ref == ref else { throw JobFailure("dangling_transform_ref") }
            if let current {
                guard transform.input == current else { throw JobFailure("broken_transform_chain") }
            } else {
                guard receipt.resultRecords.contains(transform.input) else { throw JobFailure("broken_transform_chain") }
            }
            guard transform.output.recordId == transform.input.recordId, transform.output.kind == transform.input.kind,
                  transform.output.revision > transform.input.revision, CKIdentityJSON.hashValid(transform.output.contentHash) else { throw JobFailure("invalid_transform_revision") }
            let evidence = try JobLedger.localURL(transform.evidenceRef, base: base)
            guard try CKHash.sha256Hex(ofFileAt: evidence) == transform.evidenceHash else { throw JobFailure("transform_evidence_mismatch") }
            current = transform.output
        }
        guard current.map({ $0 == final }) ?? receipt.resultRecords.contains(final) else { throw JobFailure("provenance_result_mismatch") }
        for ref in p.reviewRefs {
            guard let review = reviews[ref], review.recordId == ref else { throw JobFailure("dangling_review_ref") }
            let r = review.payload
            guard try review.revisionHash() == review.contentSha256,
                  r.subjectId == subject.recordId, r.subjectKind == subject.kind,
                  r.subjectRevision == subject.revision, r.subjectContentSha256 == subject.contentSha256 else { throw JobFailure("stale_review_ref") }
            guard r.reviewerSession != receipt.sessionId else { throw JobFailure("reviewer_generator_session_collision") }
            for receiptRef in r.receiptRefs {
                guard let reviewEvent = jobs.events.values.first(where: { $0.receiptRef == receiptRef }),
                      let reviewReceipt = jobs.receipts[reviewEvent.binding.jobId], reviewEvent.binding.role.isReview,
                      reviewReceipt.sessionId == r.reviewerSession, reviewReceipt.binding.model == r.reviewerModel,
                      reviewReceipt.binding.promptHash == r.promptHash, reviewReceipt.binding.inputHash == r.inputHash,
                      reviewReceipt.binding.records.contains(final) else { throw JobFailure("missing_review_receipt") }
                try JobLedger.validateReceipt(reviewReceipt, binding: reviewEvent.binding, base: base)
            }
        }
        guard p.humanModificationRefs.allSatisfy(humanModificationRefs.contains) else { throw JobFailure("dangling_human_modification_ref") }
    }
}
