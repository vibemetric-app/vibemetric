import Foundation

/// The bundled definitions used by the assessor, schema, and competency explanations.
public struct RubricGuide: Codable, Sendable {
    public struct Competency: Codable, Sendable, Identifiable {
        public var id: String
        public var title: String
        public var meaning: String
        public var evidence: String
        public var high: String
        public var medium: String
        public var low: String
        public var whyItHelps: String
        public var applicability: String
        public var sources: [PlanningAssessment.Source]

        public var criteria: PlanningAssessment.Criteria {
            .init(high: high, medium: medium, low: low)
        }
    }

    public struct Example: Codable, Sendable {
        public var notice: String
        public var summary: String
        public var expanded: String
    }

    public struct DimensionGuide: Codable, Sendable, Identifiable {
        public var dimension: Dimension
        public var competencies: [Competency]
        public var boundaries: [String]
        public var example: Example

        public var id: String { dimension.rawValue }
    }

    public enum LoadError: Error, LocalizedError {
        case missingResource
        case invalidDimensions
        case invalidCompetencies(Dimension)
        case invalidSources(Dimension, String)

        public var errorDescription: String? {
            switch self {
            case .missingResource:
                "The bundled competency-guides.json resource is missing."
            case .invalidDimensions:
                "The competency guide must contain each non-Planning dimension exactly once."
            case let .invalidCompetencies(dimension):
                "The competency guide for \(dimension.rawValue) has empty or duplicate competency definitions."
            case let .invalidSources(dimension, id):
                "The competency guide for \(dimension.rawValue)/\(id) has missing or invalid source URLs."
            }
        }
    }

    public var dimensions: [DimensionGuide]

    public func guide(for dimension: Dimension) -> DimensionGuide? {
        dimensions.first { $0.dimension == dimension }
    }

    public static func load() throws -> RubricGuide {
        guard let url = Bundle.module.url(forResource: "competency-guides", withExtension: "json") else {
            throw LoadError.missingResource
        }
        let guide = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try guide.validate()
        return guide
    }

    public func validate() throws {
        let expected = Dimension.allCases.filter { $0 != .planningSpecs }
        guard dimensions.count == expected.count,
              Set(dimensions.map(\.dimension)) == Set(expected) else {
            throw LoadError.invalidDimensions
        }
        for guide in dimensions {
            let ids = guide.competencies.map(\.id)
            guard !ids.isEmpty, ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count,
                  guide.competencies.allSatisfy({ !$0.title.isEmpty }) else {
                throw LoadError.invalidCompetencies(guide.dimension)
            }
            for competency in guide.competencies {
                guard !competency.sources.isEmpty, competency.sources.allSatisfy({ source in
                    guard let url = URL(string: source.url) else { return false }
                    return url.scheme == "https" && url.host != nil && !source.title.isEmpty
                }) else {
                    throw LoadError.invalidSources(guide.dimension, competency.id)
                }
            }
        }
    }
}
