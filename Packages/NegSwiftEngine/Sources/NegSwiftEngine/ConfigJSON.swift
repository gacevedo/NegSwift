import Foundation

/// JSON helpers for flat `WorkspaceConfig` dicts.
enum ConfigJSON {
    static func loadResource(_ name: String) -> [String: Any] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            preconditionFailure("Missing NegSwiftEngine resource \(name).json")
        }
        return loadDictionary(from: url)
    }

    static func loadDictionary(from url: URL) -> [String: Any] {
        let data = try! Data(contentsOf: url)
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any]
        else {
            preconditionFailure("Invalid JSON object at \(url.path)")
        }
        return dict
    }

    static func clone(_ dict: [String: Any]) -> [String: Any] {
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let copy = obj as? [String: Any]
        else {
            return dict
        }
        return copy
    }

    static func merge(_ base: [String: Any], _ overrides: [String: Any]) -> [String: Any] {
        var out = base
        for (key, value) in overrides {
            out[key] = value
        }
        return out
    }

    static func jsonData(_ object: Any, pretty: Bool = false) throws -> Data {
        var options: JSONSerialization.WritingOptions = []
        if pretty {
            options.insert(.prettyPrinted)
            options.insert(.sortedKeys)
        }
        return try JSONSerialization.data(withJSONObject: object, options: options)
    }

    static func isJSONBool(_ value: Any) -> Bool {
        if value is Bool { return true }
        return CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID()
    }

    static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: b
        case let n as NSNumber where isJSONBool(n): n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "true", "1", "yes": true
            case "false", "0", "no": false
            default: nil
            }
        default: nil
        }
    }

    static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: d
        case let f as Float: Double(f)
        case let i as Int: Double(i)
        case let n as NSNumber: n.doubleValue
        case let s as String: Double(s)
        default: nil
        }
    }

    static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let i as Int:
            return i
        case let n as NSNumber:
            guard abs(n.doubleValue - n.doubleValue.rounded()) < 1e-9 else { return nil }
            return n.intValue
        case let d as Double:
            guard abs(d - d.rounded()) < 1e-9 else { return nil }
            return Int(d)
        case let s as String:
            return Int(s)
        default:
            return nil
        }
    }

    static func stringValue(_ value: Any?) -> String? {
        value as? String
    }
}
