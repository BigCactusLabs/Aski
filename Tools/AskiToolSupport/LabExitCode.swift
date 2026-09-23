public enum LabExitCode: Int32, Equatable, Sendable {
    case success = 0
    case usage = 64
    case ioError = 74
    case failure = 70
}
