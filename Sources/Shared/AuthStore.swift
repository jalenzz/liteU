import Foundation

@MainActor
@Observable
final class AuthStore {
    private(set) var token: String?

    init() {
        load()
    }

    func load() {
        token = TokenKeychain.load()
    }

    func save(_ token: String) {
        TokenKeychain.save(token)
        self.token = token
    }

    func clear() {
        TokenKeychain.delete()
        token = nil
    }
}
