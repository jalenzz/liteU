import CoreLocation

@MainActor
@Observable
final class LocationProvider: NSObject {
    var coordinate: CLLocationCoordinate2D?
    var errorMessage: String?
    private(set) var fixID = 0

    private let manager = CLLocationManager()
    private var wantsFix = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        errorMessage = nil
        wantsFix = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            wantsFix = false
            errorMessage = "未授权使用位置，请手动输入坐标"
        }
    }
}

extension LocationProvider: @MainActor CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantsFix else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            wantsFix = false
            errorMessage = "未授权使用位置，请手动输入坐标"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        wantsFix = false
        coordinate = locations.last!.coordinate
        fixID += 1
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError _: Error) {
        wantsFix = false
        errorMessage = "无法获取当前位置，请手动输入坐标"
    }
}
