/// Version and identity for the native engine (S7 sidecar + stdio).
public enum EngineVersion: Sendable {
    public static let protocolVersion = "0.1"
    public static let packageVersion = "0.1.0-s7"
    public static let backendName = "swift"
    public static let oracleLabel = "s7-sidecar"
}
