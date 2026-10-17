import Foundation

public enum NoiseMode: String, CaseIterable, Identifiable {
    case cancellation, transparency, off
    public var id: String { rawValue }
    public var commandValue: UInt8 {
        switch self { case .off: return 1; case .cancellation: return 2; case .transparency: return 4 }
    }
    public var reportedBitmaps: Set<UInt16> {
        switch self {
        case .off: return [1, 8]
        case .cancellation: return [2, 16, 32, 64, 128]
        case .transparency: return [4, 256]
        }
    }
    public func matches(_ bitmap: UInt16) -> Bool { reportedBitmaps.contains(bitmap) }
}
