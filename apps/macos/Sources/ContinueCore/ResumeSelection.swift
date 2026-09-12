public struct ResumeSelection: Equatable, Sendable {
    public private(set) var selectedIDs: Set<String>
    private let availableIDs: Set<String>

    public init(targets: [ResumeTarget], selectsAll: Bool = true) {
        availableIDs = Set(targets.map(\.id))
        selectedIDs = selectsAll ? availableIDs : []
    }

    public func contains(_ targetID: String) -> Bool {
        selectedIDs.contains(targetID)
    }

    public mutating func toggle(_ targetID: String) {
        guard availableIDs.contains(targetID) else { return }

        if selectedIDs.contains(targetID) {
            selectedIDs.remove(targetID)
        } else {
            selectedIDs.insert(targetID)
        }
    }
}
