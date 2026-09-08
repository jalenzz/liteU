import CoreLocation

@Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var errorMessage: String?
    private(set) var fixID = 0

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        errorMessage = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
        default:
            errorMessage = "定位未授权，请改为手动填写坐标"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last!.coordinate
        fixID += 1
        manager.stopUpdatingLocation()
        errorMessage = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError _: Error) {
        manager.stopUpdatingLocation()
        errorMessage = "定位失败，请改为手动填写坐标"
    }
}
