/// The app's view of when-in-use location permission.
public enum LocationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    /// Denied, restricted, or Location Services turned off.
    case denied
}
