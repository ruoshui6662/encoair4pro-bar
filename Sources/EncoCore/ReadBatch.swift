import Foundation

public enum StatusField: Hashable { case product, battery, mode }

public struct ReadBatch {
    private let required: Set<StatusField>
    private let deadline: Date
    private var expected: [StatusField: UInt8] = [:]
    private var received: Set<StatusField> = []
    public init(required: Set<StatusField>, deadline: Date) { self.required = required; self.deadline = deadline }
    public mutating func expect(_ field: StatusField, sequence: UInt8) {
        expected[field] = sequence
        received.remove(field)
    }
    public mutating func receive(_ field: StatusField, sequence: UInt8) {
        if expected[field] == sequence { received.insert(field) }
    }
    public var isComplete: Bool { required.isSubset(of: received) }
    public func hasExpired(at now: Date) -> Bool { !isComplete && now >= deadline }
}
