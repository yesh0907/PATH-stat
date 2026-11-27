import Foundation

public enum PATHError: Error, Equatable, Sendable {
    case offline
    case timedOut
    case httpStatus(Int)
    case invalidResponse(String)

    /// Maps transport errors to `PATHError`.
    public static func from(_ error: any Error) -> PATHError {
        if let pathError = error as? PATHError { return pathError }
        guard let urlError = error as? URLError else {
            return .invalidResponse(String(describing: error))
        }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .internationalRoamingOff, .callIsActive:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .invalidResponse("URLError \(urlError.code.rawValue): \(urlError.localizedDescription)")
        }
    }
}

extension PATHError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline: "You appear to be offline."
        case .timedOut: "The PATH feed timed out."
        case .httpStatus(let code): "The PATH feed returned HTTP \(code)."
        case .invalidResponse(let detail): "Unexpected response from the PATH feed: \(detail)"
        }
    }
}
