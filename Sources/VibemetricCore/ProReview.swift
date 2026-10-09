import Foundation

/// One server-generated review associated with an immutable assessment.
public struct ProReview: Codable, Equatable, Sendable {
    public var reviewId: String
    public var assessmentId: String
    public var review: String
    public var generatedAt: String
}
