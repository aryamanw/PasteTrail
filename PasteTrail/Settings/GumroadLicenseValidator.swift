// PasteTrail/Settings/GumroadLicenseValidator.swift
import Foundation

enum GumroadError: Error {
    case invalidKey
    case networkError(Error)
}

struct GumroadLicenseValidator {

    static func validate(key: String) async throws {
        var request = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "product_id=\(GumroadProductID)&license_key=\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)"
        request.httpBody = body.data(using: .utf8)

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw GumroadError.networkError(error)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let success = json["success"] as? Bool,
            success
        else {
            throw GumroadError.invalidKey
        }
    }
}

// Replace with your actual Gumroad product permalink/ID before shipping
private let GumroadProductID = "pastetrail"
