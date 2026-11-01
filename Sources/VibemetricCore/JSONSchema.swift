import Foundation

/// Shared structured-output schema for Claude Code and Codex, mirroring `ScoreCard`.
enum JSONSchema {
    static var scoreCard: String { encode(cardProperties(dimensions: Dimension.allCases)) }

    /// A writing part's card fields: everything except `dimensions`.
    static var cardFrame: String {
        var props = cardProperties(dimensions: [])
        props.removeValue(forKey: "dimensions")
        return encode(props)
    }

    /// A writing part's card fields for one dimension: `dimensions` holding just that one.
    static func cardDimension(_ dimension: Dimension) -> String {
        encode(["dimensions": cardProperties(dimensions: [dimension])["dimensions"]!])
    }

    /// One format for Claude's reading run and every writing part: the reading note and all of the card's fields, none
    /// required, so each run fills only its own. Claude Code sends the format at the start of every request, and the
    /// prompt cache works only on an identical start, so with one format the writing copies reuse the reading's cache
    /// instead of each paying to load the whole session again. The app checks each part's fields (`CardPart.isComplete`).
    static var sharedParts: String {
        var props = cardProperties(dimensions: Dimension.allCases)
        var dimensions = props["dimensions"] as! [String: Any]
        dimensions["minItems"] = 0
        props["dimensions"] = dimensions
        props["note"] = ["type": "string"]
        let schema: [String: Any] = ["type": "object", "additionalProperties": false, "properties": props, "required": [String]()]
        let data = try! JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    /// What a rewrite of the card's long quick lines returns: each line's id with its shorter text.
    static let shorterLines = #"{"type":"object","additionalProperties":false,"properties":{"lines":{"type":"array","items":{"type":"object","additionalProperties":false,"properties":{"id":{"type":"string"},"text":{"type":"string"}},"required":["id","text"]}}},"required":["lines"]}"#

    /// What a reading run returns: a short note. The saved session carries everything it read.
    static let readingCheckpoint = #"{"type":"object","additionalProperties":false,"properties":{"note":{"type":"string"}},"required":["note"]}"#

    private static func encode(_ props: [String: Any]) -> String {
        let schema: [String: Any] = ["type": "object", "additionalProperties": false, "properties": props,
                                     "required": props.keys.sorted()]
        let data = try! JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    /// The card's top-level properties, with `dimensions` limited to `dimensions` (exactly that many entries).
    private static func cardProperties(dimensions: [Dimension]) -> [String: Any] {
        let str: [String: Any] = ["type": "string"]
        let int: [String: Any] = ["type": "integer"]
        func object(_ props: [String: Any], optional: Set<String> = []) -> [String: Any] {
            ["type": "object", "additionalProperties": false, "properties": props,
             "required": props.keys.filter { !optional.contains($0) }.sorted()]
        }
        func array(_ items: [String: Any], min: Int? = nil, max: Int? = nil) -> [String: Any] {
            var a: [String: Any] = ["type": "array", "items": items]
            if let min { a["minItems"] = min }
            if let max { a["maxItems"] = max }
            return a
        }

        let evidence = object(["tool": str, "sessionId": str, "date": str, "note": str, "project": str])
        let dimensionID: [String: Any] = ["type": "string", "enum": Dimension.allCases.map(\.rawValue)]
        let dimension = object([
            "dimension": ["type": "string", "enum": dimensions.map(\.rawValue)] as [String: Any],
            "score": ["type": ["integer", "null"], "minimum": 0, "maximum": 10],
            "status": ["type": "string", "enum": ["scored", "not_assessable", "not_reviewed"]],
            "headline": str,
            "problems": array(str, max: 3),
            "issueLine": str,
            "fixLine": str,
            "goodLine": str,
            "gapLine": str,
            "strengths": array(str, max: 3),
            "impact": str,
            "tryThis": ["type": ["string", "null"]],
            "solutionSteps": array(str, max: 4),
            "evidence": array(evidence, max: 3),
            "changeReason": ["type": ["string", "null"]],
            "levelNow": str,
            "nextLevel": ["type": ["string", "null"]],
            "checks": array(object([
                "id": ["type": "string", "enum": ScoreCheck.allIDs],
                "status": ["type": "string", "enum": ScoreCheck.Status.allCases.map(\.rawValue)],
                "note": str,
                "seen": ["type": ["integer", "null"], "minimum": 0],
                "of": ["type": ["integer", "null"], "minimum": 0],
                "sessions": array(str, max: 3),
            ]), max: 4),
        ])
        return [
            "language": str,
            "diagnosis": str,
            "summary": array(str, min: 2, max: 3),
            "highlights": array(str, min: 2, max: 4),
            "overview": array(object([
                "tone": ["type": "string", "enum": ScoreCard.SummaryPoint.Tone.allCases.map(\.rawValue)],
                "text": str,
            ]), min: 4, max: 6),
            "dimensions": array(dimension, min: dimensions.count, max: dimensions.count),
            "improvement": object([
                "title": str, "situation": str,
                "actions": array(str, min: 3, max: 4),
                "suggestedInstruction": ["type": ["string", "null"]],
                "signOfSuccess": str, "tryItOn": str,
                "dimension": dimensionID,
                "impact": str,
                "evidence": array(evidence, max: 3),
                "count": ["type": ["integer", "null"], "minimum": 1],
                "countLabel": ["type": ["string", "null"]],
            ]),
            "followUp": ["anyOf": [
                object([
                    "previousTitle": str,
                    "status": ["type": "string", "enum": ["not_started", "partly_done", "done", "applied"]],
                    "summary": str,
                    "evidence": array(evidence, max: 4),
                ]),
                ["type": "null"],
            ]],
            "roadmap": array(object(["stage": int, "change": str, "result": str]), min: 1, max: 3),
            "scope": object([
                "assessedAt": str, "timeZone": str,
                "recordDates": array(object(["tool": str, "from": str, "to": str, "sessions": int])),
                "sessionsExamined": int, "tasksCheckedInDetail": int,
                "elapsedMinutes": ["type": "number"],
                "limits": array(str),
            ]),
        ]
    }
}
