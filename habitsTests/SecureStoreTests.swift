import Foundation
import Security
import Testing
@testable import habits

@Suite("Secure Store")
struct SecureStoreTests {
    @Test("Saving a duplicate key updates the existing value")
    func duplicateSaveUpdatesExistingValue() throws {
        let recorder = KeychainRecorder(addStatus: errSecDuplicateItem)
        let store = SecureStore(
            service: "tests.secure-store",
            client: recorder.client
        )

        try store.save("token-2", for: "auth-token")

        #expect(recorder.addQueries.count == 1)
        #expect(recorder.updateQueries.count == 1)
        #expect(recorder.addQueries[0][kSecAttrService as String] as? String == "tests.secure-store")
        #expect(recorder.updateQueries[0].query[kSecAttrAccount as String] as? String == "auth-token")
    }

    @Test("Missing values return nil instead of throwing")
    func missingValueReturnsNil() throws {
        let recorder = KeychainRecorder(copyStatus: errSecItemNotFound)
        let store = SecureStore(
            service: "tests.secure-store",
            client: recorder.client
        )

        let value = try store.string(for: "missing")

        #expect(value == nil)
    }
}

private final class KeychainRecorder: @unchecked Sendable {
    struct UpdateCall {
        let query: [String: Any]
        let attributes: [String: Any]
    }

    private(set) var addQueries: [[String: Any]] = []
    private(set) var updateQueries: [UpdateCall] = []

    let addStatus: OSStatus
    let copyStatus: OSStatus
    let copyResult: Any?
    let updateStatus: OSStatus
    let deleteStatus: OSStatus

    init(
        addStatus: OSStatus = errSecSuccess,
        copyStatus: OSStatus = errSecSuccess,
        copyResult: Any? = Data("value".utf8),
        updateStatus: OSStatus = errSecSuccess,
        deleteStatus: OSStatus = errSecSuccess
    ) {
        self.addStatus = addStatus
        self.copyStatus = copyStatus
        self.copyResult = copyResult
        self.updateStatus = updateStatus
        self.deleteStatus = deleteStatus
    }

    var client: KeychainClient {
        KeychainClient(
            add: { [self] query in
                addQueries.append(query)
                return addStatus
            },
            copyMatching: { [self] _ in
                (self.copyStatus, self.copyResult)
            },
            update: { [self] query, attributes in
                updateQueries.append(.init(query: query, attributes: attributes))
                return updateStatus
            },
            delete: { [self] _ in
                self.deleteStatus
            }
        )
    }
}
