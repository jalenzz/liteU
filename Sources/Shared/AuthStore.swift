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

    func save(_ token: String, mobile: String) throws {
        try TokenKeychain.save(token, account: "jwt")
        try TokenKeychain.save(mobile, account: "mobile")
        self.token = token
        self.mobile = mobile
    }

    func clear() {
        TokenKeychain.delete(account: "jwt")
        TokenKeychain.delete(account: "mobile")
        token = nil
        mobile = nil
    }

    /// 401 时退出登录；返回需要提示给用户的文案，取消或 401 时为 nil。
    func message(for error: Error) -> String? {
        switch error {
        case is CancellationError:
            return nil
        case let error as UjingError where error.isUnauthorized:
            clear()
            return nil
        default:
            return error.localizedDescription
        }
    }
}
