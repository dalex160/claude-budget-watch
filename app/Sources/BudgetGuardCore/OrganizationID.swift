import Foundation

public enum OrganizationID {
    /// Only letters, digits and dashes may be put in a URL path.
    public static func isSafe(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy {
            ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2D
        }
    }
}
