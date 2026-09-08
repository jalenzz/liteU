import Foundation

enum UjingError: Error, Equatable, LocalizedError {
    case invalidPhone
    case invalidCaptcha
    case unauthorized
    case api(code: Int, message: String)
    case transport(String)

    var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .invalidPhone:
            "手机号须为 1 开头的 11 位数字"
        case .invalidCaptcha:
            "验证码须为 4 到 8 位数字"
        case .unauthorized:
            "登录已失效，请重新登录"
        case .api(_, let message):
            message.isEmpty ? "请求失败" : message
        case .transport(let message):
            message
        }
    }
}

enum PhoneNumber {
    static func isValid(_ raw: String) -> Bool {
        raw.wholeMatch(of: /1\d{10}/) != nil
    }
}

enum CaptchaCode {
    static func isValid(_ raw: String) -> Bool {
        raw.wholeMatch(of: /\d{4,8}/) != nil
    }
}

enum GeoCoordinate {
    static func parse(latitude: String, longitude: String) -> (Double, Double)? {
        guard let lat = Double(latitude), let longitude = Double(longitude) else { return nil }
        guard (-90 ... 90).contains(lat), (-180 ... 180).contains(longitude) else { return nil }
        return (lat, longitude)
    }

    static func errorMessage(latitude: String, longitude: String) -> String? {
        guard let lat = Double(latitude), let longitude = Double(longitude) else {
            return "请填写数字坐标"
        }
        if !(-90 ... 90).contains(lat) {
            return "第一格是纬度（-90～90）。成都大约是纬度 30.68、经度 104.09，104 应填在第二格。"
        }
        if !(-180 ... 180).contains(longitude) {
            return "经度应在 -180～180"
        }
        return nil
    }
}
