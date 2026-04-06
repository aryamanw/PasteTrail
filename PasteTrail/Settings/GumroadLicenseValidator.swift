// PasteTrail/Settings/GumroadLicenseValidator.swift
import Foundation

enum GumroadError: Error {
    case invalidKey
    case networkError(Error)
}

struct GumroadLicenseValidator {

    static func validate(key: String, session: URLSession = .shared) async throws {
        var request = URLRequest(url: URL(string: "https://api.gumroad.com/v2/licenses/verify")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "product_id=\(formEncode(GumroadProductID))&license_key=\(formEncode(key))"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
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

private func formEncode(_ value: String) -> String {
    // application/x-www-form-urlencoded requires encoding +, &, =, and all non-alphanumeric
    // except unreserved chars (-._~). Using .urlQueryAllowed is insufficient as it permits +.
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}
