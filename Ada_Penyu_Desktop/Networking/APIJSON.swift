import Foundation

/// Share the repository codecs, including fractional and whole ISO-8601 dates.
enum APIJSON {
    static var decoder: JSONDecoder { JSONDecoder.api }
    static var encoder: JSONEncoder { JSONEncoder.api }
}
