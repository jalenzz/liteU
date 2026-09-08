import CryptoKit
import Foundation

enum CaptchaSignature {
    private static let keyUTF8: String = {
        guard
            let url = Bundle.main.url(forResource: "captcha-hmac-key", withExtension: "txt"),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("缺少 Secrets/captcha-hmac-key.txt")
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static func sign(nonce: String, timestamp: Int) -> String {
        let key = SymmetricKey(data: Data(keyUTF8.utf8))
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data("\(nonce)\(timestamp)".utf8),
            using: key
        )
        return Data(mac).base64EncodedString()
    }
}
