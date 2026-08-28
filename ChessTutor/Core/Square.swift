struct Square: Codable, Equatable, Hashable, Sendable {
    enum File: Int, CaseIterable, Codable, Sendable {
        case a = 1, b, c, d, e, f, g, h
    }

    let file: File
    let rank: Int

    init(file: File, rank: Int) {
        precondition((1...8).contains(rank), "Rank must be between 1 and 8")
        self.file = file
        self.rank = rank
    }

    var isLightSquare: Bool {
        !(file.rawValue + rank).isMultiple(of: 2)
    }

    func offset(fileDelta: Int, rankDelta: Int) -> Square? {
        let nextFileValue = file.rawValue + fileDelta
        let nextRank = rank + rankDelta
        guard let nextFile = File(rawValue: nextFileValue), (1...8).contains(nextRank) else {
            return nil
        }
        return Square(file: nextFile, rank: nextRank)
    }
}
