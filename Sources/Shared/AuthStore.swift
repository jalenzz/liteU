import Foundation

@MainActor
@Observable
final class AuthStore {
    private(set) var token: String?
    private(set) var mobile: String?

    init() {
        load()
    }

    func load() {
        token = TokenKeychain.load(account: "jwt")
        mobile = TokenKeychain.load(account: "mobile")
    }

    func save(_ token: String, mobile: String) {
        TokenKeychain.save(token, account: "jwt")
        TokenKeychain.save(mobile, account: "mobile")
        self.token = token
        self.mobile = mobile
    }

    func clear() {
        TokenKeychain.delete(account: "jwt")
        TokenKeychain.delete(account: "mobile")
        token = nil
        mobile = nil
    }
}
