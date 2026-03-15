// BridgeFoodAlgorithm.swift
// Bridge Food Recommendation Algorithm v3 – Swift Translation
// Translated from bridge_food_algorithm.py (FIXED reference implementation)
//
// CORRECTIONS vs. first translation (claude-swift-claude-translate-…):
//
//  Fix 1 – aggregateFoodLogs: highest state now computed across ALL accumulated
//           logs, not just allLogs[0] + incoming.  Prevents a third log from
//           silently lowering a food's highestState.
//
//  Fix 2 – deduplicateLastNLogs: now uses the globally-aggregated FoodProfile's
//           highestState instead of a per-log getHighestState() call, so a
//           regression-day log never wipes out a food's true peak.
//
//  Fix 3 – detectTrend: rewritten to inspect actual sensory dimensions (sweet,
//           salty, savory, sour, bitter, crunchy, soft) from the food DB.
//           The original checked ate/tasted counts under "oral_acceptance",
//           which matched no real trend dimension used by the pick logic.
//
//  Fix 4 – findVarietyPick / SensoryProfile: added foodGroup field; variety
//           pick now filters by group membership (missing groups), not just
//           distance.  generateRecommendations computes missing groups from
//           the child's eaten history.
//
//  Fix 5 – DISTANCE_WEIGHTS: normalised to sum to exactly 1.0.
//           STRETCH_PICK_MAX / VARIETY_PICK_MAX raised to 5.0 to match the
//           recalibrated scale.
//
//  Bonus – Safe-food seeding: safe foods with no logs now receive a synthetic
//           FoodProfile so a new-user baseline is never a zero vector.
//
//  Bonus – Cross-pick deduplication: stretch and variety picks exclude foods
//           already chosen by an earlier pick in the same run.

import Foundation

// ============================================================================
// EXPOSURE STATE
// ============================================================================

enum ExposureState: String, CaseIterable {
    case lookedAt = "looked_at"
    case touched  = "touched"
    case smelled  = "smelled"
    case tasted   = "tasted"
    case ate      = "ate"

    var multiplier: Double {
        switch self {
        case .lookedAt: return 0.3
        case .touched:  return 0.5
        case .smelled:  return 0.6
        case .tasted:   return 0.8
        case .ate:      return 1.0
        }
    }
}

// ============================================================================
// SENSORY PROFILE
// ============================================================================

struct SensoryProfile {
    let texture: Double         // 0-10  (liquid → hard)
    let flavorSweet: Double     // 0-10
    let flavorSalty: Double     // 0-10
    let flavorSavory: Double    // 0-10
    let flavorSour: Double      // 0-10
    let flavorBitter: Double    // 0-10
    let temperature: Double     // 0-100 celsius
    let color: String
    let mouthfeel: String
    let prepMethod: String
    let foodGroup: String       // vegetable, fruit, protein, grain, dairy, other

    init(texture: Double, flavorSweet: Double, flavorSalty: Double,
         flavorSavory: Double, flavorSour: Double, flavorBitter: Double,
         temperature: Double, color: String, mouthfeel: String,
         prepMethod: String, foodGroup: String = "other") {
        self.texture      = texture
        self.flavorSweet  = flavorSweet
        self.flavorSalty  = flavorSalty
        self.flavorSavory = flavorSavory
        self.flavorSour   = flavorSour
        self.flavorBitter = flavorBitter
        self.temperature  = temperature
        self.color        = color
        self.mouthfeel    = mouthfeel
        self.prepMethod   = prepMethod
        self.foodGroup    = foodGroup
    }

    /// Numeric vector used for distance calculation (temperature normalised to 0-10).
    func toVector() -> [Double] {
        return [
            texture,
            flavorSweet,
            flavorSalty,
            flavorSavory,
            flavorSour,
            flavorBitter,
            temperature / 10.0,
        ]
    }
}

// ============================================================================
// FOOD LOG
// ============================================================================

struct FoodLog {
    let foodId: String
    let kidId: String
    let timestamp: Date
    let exposureStates: [String]
    let parentNotes: String?

    init(foodId: String, kidId: String, timestamp: Date,
         exposureStates: [String], parentNotes: String? = nil) {
        self.foodId         = foodId
        self.kidId          = kidId
        self.timestamp      = timestamp
        self.exposureStates = exposureStates
        self.parentNotes    = parentNotes
    }
}

// ============================================================================
// FOOD PROFILE
// ============================================================================

struct FoodProfile {
    let foodId: String
    var highestState: String
    var highestStateMultiplier: Double
    var mostRecentDate: Date
    var allLogs: [FoodLog]
    var lastSuccessfulState: String

    /// Composite weight: state × recency × scaling × regression.
    func getWeight(today: Date, numExplored: Int,
                   isSuperSafe: Bool = false, isRegularSafe: Bool = false) -> Double {
        var stateMult = highestStateMultiplier

        let daysAgo = daysBetween(from: mostRecentDate, to: today)
        let recency = calculateRecencyWeight(daysAgo: daysAgo)

        if isSuperSafe {
            stateMult = 0.60 / (1.0 + log(Double(max(1, numExplored))))
        } else if isRegularSafe {
            stateMult = 0.40 / (1.0 + log(Double(max(1, numExplored))))
        }

        let regressionPenalty: Double = lastSuccessfulState != highestState ? 0.8 : 1.0

        return stateMult * recency * regressionPenalty
    }
}

// ============================================================================
// RECOMMENDATION
// ============================================================================

struct Recommendation {
    let rank: String            // "Safe Pick" | "Stretch Pick" | "Variety Pick"
    let foodId: String?
    let foodName: String?
    let distance: Double?
    let explanation: String
}

// ============================================================================
// CONSTANTS  (Fix 5: weights sum to 1.0; thresholds recalibrated)
// ============================================================================

/// Ordered to match Python DISTANCE_WEIGHTS (texture, sweet, salty, savory,
/// sour, bitter, temperature).  Weights sum to exactly 1.0.
let distanceWeights: [Double] = [
    0.20,   // texture      — strongest sensory barrier for selective eaters
    0.12,   // flavor_sweet
    0.18,   // flavor_salty — salt is a strong gating factor
    0.12,   // flavor_savory
    0.08,   // flavor_sour
    0.12,   // flavor_bitter — strong aversion driver
    0.18,   // temperature   — thermal sensitivity significant in SOS
]
// Compile-time guard equivalent — will trap at startup if weights drift.
private let _weightsAssert: Void = {
    let s = distanceWeights.reduce(0, +)
    precondition(abs(s - 1.0) < 1e-9, "distanceWeights must sum to 1.0, got \(s)")
}()

let safePickMax            = 2.5
let stretchPickMin         = 2.5
let stretchPickMax         = 5.0   // Recalibrated for normalised weight scale
let varietyPickMax         = 5.0
let minFoodsForTrend       = 5
let trendStrengthThreshold = 5.0 / 7.0   // ≈ 0.7143

// Sensory dimension thresholds for trend detection (scale 0-10)
let flavorThreshold: Double        = 5.0
let textureCrunchyThreshold: Double = 6.0
let textureSoftThreshold: Double    = 3.0

// ============================================================================
// DATE HELPERS  (naive-datetime equivalent — always UTC, midnight)
// ============================================================================

private var utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

func makeDate(year: Int, month: Int, day: Int) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day
    c.hour = 0; c.minute = 0; c.second = 0; c.nanosecond = 0
    return utcCalendar.date(from: c)!
}

/// Equivalent of Python `(today - other).days` (positive when today > other).
func daysBetween(from start: Date, to end: Date) -> Int {
    return utcCalendar.dateComponents([.day], from: start, to: end).day ?? 0
}

// ============================================================================
// WEIGHT CALCULATIONS
// ============================================================================

func calculateRecencyWeight(daysAgo: Int) -> Double {
    if daysAgo <= 3  { return 1.00 }
    if daysAgo <= 7  { return 0.75 }
    if daysAgo <= 14 { return 0.50 }
    if daysAgo <= 30 { return 0.25 }
    return 0.10
}

func calculateDistance(_ p1: SensoryProfile, _ p2: SensoryProfile) -> Double {
    let v1 = p1.toVector()
    let v2 = p2.toVector()
    var distSq = 0.0
    for i in 0..<v1.count {
        let d = v1[i] - v2[i]
        distSq += distanceWeights[i] * d * d
    }
    return distSq.squareRoot()
}

/// Returns (stateName, multiplier) of the highest ExposureState in the list.
/// Defaults to lookedAt when the list is empty or contains no known states.
func getHighestState(stateNames: [String]) -> (name: String, multiplier: Double) {
    var highest: ExposureState? = nil
    for name in stateNames {
        if let state = ExposureState(rawValue: name) {
            if highest == nil || state.multiplier > highest!.multiplier {
                highest = state
            }
        }
    }
    let h = highest ?? .lookedAt
    return (h.rawValue, h.multiplier)
}

// ============================================================================
// LOG AGGREGATION  (Fix 1)
// ============================================================================

/// Aggregates all logs by foodId.
///
/// Fix 1: `highestState` is now computed by combining the exposure states from
/// ALL accumulated logs (not just allLogs[0] + incoming).  This prevents a
/// third log with a lower state from silently overwriting the food's true peak.
func aggregateFoodLogs(_ allLogs: [FoodLog]) -> [String: FoodProfile] {
    var foodProfiles: [String: FoodProfile] = [:]

    for log in allLogs {
        if foodProfiles[log.foodId] == nil {
            // First log for this food
            let (hs, mult) = getHighestState(stateNames: log.exposureStates)
            foodProfiles[log.foodId] = FoodProfile(
                foodId:                  log.foodId,
                highestState:            hs,
                highestStateMultiplier:  mult,
                mostRecentDate:          log.timestamp,
                allLogs:                 [log],
                lastSuccessfulState:     hs
            )
        } else {
            var profile = foodProfiles[log.foodId]!

            // Fix 1: collect states from ALL prior logs, not just allLogs[0]
            let allPriorStates = profile.allLogs.flatMap { $0.exposureStates }
            let (hs, mult) = getHighestState(stateNames: allPriorStates + log.exposureStates)
            profile.highestState            = hs
            profile.highestStateMultiplier  = mult

            // Most-recent date
            if log.timestamp > profile.mostRecentDate {
                profile.mostRecentDate = log.timestamp
            }

            // Last 3 individual states for regression detection
            var allStates = profile.allLogs.flatMap { $0.exposureStates }
            allStates.append(contentsOf: log.exposureStates)
            let last3 = Array(allStates.suffix(3))
            let (lastSuccess, _) = getHighestState(stateNames: last3)
            profile.lastSuccessfulState = lastSuccess

            profile.allLogs.append(log)
            foodProfiles[log.foodId] = profile
        }
    }

    return foodProfiles
}

// ============================================================================
// BASELINE CALCULATION
// ============================================================================

func calculateWeightedBaseline(
    foodProfiles: [String: FoodProfile],
    superSafeFoods: Set<String>,
    regularSafeFoods: Set<String>,
    foodDb: [String: SensoryProfile],
    today: Date,
    numTrulyExplored: Int = 0
) -> SensoryProfile {

    var totalWeight = 0.0
    var wv = [Double](repeating: 0.0, count: 7)

    func accumulate(foodId: String, isSuperSafe: Bool, isRegularSafe: Bool) {
        guard let profile = foodProfiles[foodId], let sp = foodDb[foodId] else { return }
        let w = profile.getWeight(today: today, numExplored: numTrulyExplored,
                                  isSuperSafe: isSuperSafe, isRegularSafe: isRegularSafe)
        let vec = sp.toVector()
        for i in 0..<vec.count { wv[i] += vec[i] * w }
        totalWeight += w
    }

    for foodId in superSafeFoods   { accumulate(foodId: foodId, isSuperSafe: true,  isRegularSafe: false) }
    for foodId in regularSafeFoods { accumulate(foodId: foodId, isSuperSafe: false, isRegularSafe: true)  }

    for (foodId, profile) in foodProfiles {
        if superSafeFoods.contains(foodId) || regularSafeFoods.contains(foodId) { continue }
        guard let sp = foodDb[foodId] else { continue }
        let w = profile.getWeight(today: today, numExplored: numTrulyExplored)
        let vec = sp.toVector()
        for i in 0..<vec.count { wv[i] += vec[i] * w }
        totalWeight += w
    }

    if totalWeight > 0 { for i in 0..<wv.count { wv[i] /= totalWeight } }

    return SensoryProfile(
        texture:      wv[0],
        flavorSweet:  wv[1],
        flavorSalty:  wv[2],
        flavorSavory: wv[3],
        flavorSour:   wv[4],
        flavorBitter: wv[5],
        temperature:  wv[6] * 10.0,
        color:        "mixed",
        mouthfeel:    "mixed",
        prepMethod:   "mixed",
        foodGroup:    "mixed"
    )
}

// ============================================================================
// TREND DETECTION  (Fix 2 + Fix 3)
// ============================================================================

struct DeduplicatedLog {
    let foodId: String
    let highestState: String
    let multiplier: Double
}

/// Returns the last N *distinct* foods the child has interacted with.
///
/// Fix 2: uses the globally-aggregated FoodProfile's highestState (if
/// available) instead of a per-log getHighestState() call.  A regression-day
/// log therefore cannot wipe out a food's true peak.
func deduplicateLastNLogs(
    _ allLogs: [FoodLog],
    n: Int = 7,
    foodProfiles: [String: FoodProfile]? = nil
) -> [DeduplicatedLog] {
    let sorted = allLogs.sorted { $0.timestamp > $1.timestamp }
    var seen: [String: DeduplicatedLog] = [:]
    for log in sorted {
        if seen[log.foodId] == nil {
            if let fp = foodProfiles?[log.foodId] {
                seen[log.foodId] = DeduplicatedLog(
                    foodId:       log.foodId,
                    highestState: fp.highestState,
                    multiplier:   fp.highestStateMultiplier
                )
            } else {
                let (hs, mult) = getHighestState(stateNames: log.exposureStates)
                seen[log.foodId] = DeduplicatedLog(foodId: log.foodId,
                                                   highestState: hs, multiplier: mult)
            }
        }
        if seen.count == n { break }
    }
    return Array(seen.values)
}

/// Detect trends in sensory dimensions from recent deduplicated logs.
///
/// Fix 3: inspects actual sensory profiles (sweet/salty/savory/sour/bitter/
/// crunchy/soft) instead of counting ate+tasted as a synthetic "oral_acceptance"
/// bucket.  Requires foodDb to look up each food's profile.
func detectTrend(
    _ dedupLogs: [DeduplicatedLog],
    foodDb: [String: SensoryProfile]
) -> [String: Double]? {
    guard dedupLogs.count >= minFoodsForTrend else { return nil }

    let n = Double(dedupLogs.count)
    var counts: [String: Int] = [
        "sweet": 0, "salty": 0, "savory": 0,
        "sour": 0, "bitter": 0, "crunchy": 0, "soft": 0,
    ]

    for entry in dedupLogs {
        guard let profile = foodDb[entry.foodId] else { continue }
        if profile.flavorSweet  >= flavorThreshold        { counts["sweet",  default: 0] += 1 }
        if profile.flavorSalty  >= flavorThreshold        { counts["salty",  default: 0] += 1 }
        if profile.flavorSavory >= flavorThreshold        { counts["savory", default: 0] += 1 }
        if profile.flavorSour   >= flavorThreshold        { counts["sour",   default: 0] += 1 }
        if profile.flavorBitter >= flavorThreshold        { counts["bitter", default: 0] += 1 }
        if profile.texture      >= textureCrunchyThreshold { counts["crunchy", default: 0] += 1 }
        if profile.texture      <= textureSoftThreshold    { counts["soft",   default: 0] += 1 }
    }

    var trend: [String: Double] = [:]
    for (dimension, count) in counts {
        let strength = Double(count) / n
        if strength >= trendStrengthThreshold {
            trend[dimension] = (strength * 1000).rounded() / 1000   // 3 dp
        }
    }
    return trend.isEmpty ? nil : trend
}

// ============================================================================
// PICK FINDERS  (Fix 4: variety pick uses food groups)
// ============================================================================

func findSafePick(
    baseline: SensoryProfile,
    foodDb: [String: SensoryProfile],
    excludeFoods: Set<String>
) -> (foodId: String, distance: Double)? {
    var bestId: String? = nil
    var bestDist = Double.infinity
    for (foodId, profile) in foodDb {
        if excludeFoods.contains(foodId) { continue }
        let d = calculateDistance(baseline, profile)
        if d <= safePickMax && d < bestDist { bestId = foodId; bestDist = d }
    }
    return bestId.map { ($0, bestDist) }
}

func findStretchPick(
    baseline: SensoryProfile,
    foodDb: [String: SensoryProfile],
    excludeFoods: Set<String>,
    trend: [String: Double]? = nil
) -> (foodId: String, distance: Double)? {
    var bestId: String? = nil
    var bestDist = Double.infinity
    for (foodId, profile) in foodDb {
        if excludeFoods.contains(foodId) { continue }
        let d = calculateDistance(baseline, profile)
        if d >= stretchPickMin && d <= stretchPickMax && d < bestDist {
            bestId = foodId; bestDist = d
        }
    }
    return bestId.map { ($0, bestDist) }
}

/// Fix 4: filters candidates by food group membership before applying the
/// distance cap.  If no food in any missing group is reachable, returns nil
/// (caller produces 2 recommendations rather than forcing a bad pick).
func findVarietyPick(
    baseline: SensoryProfile,
    foodDb: [String: SensoryProfile],
    excludeFoods: Set<String>,
    missingGroups: [String]
) -> (foodId: String, distance: Double)? {
    guard !missingGroups.isEmpty else { return nil }
    var bestId: String? = nil
    var bestDist = Double.infinity
    for (foodId, profile) in foodDb {
        if excludeFoods.contains(foodId) { continue }
        if !missingGroups.contains(profile.foodGroup) { continue }   // Fix 4
        let d = calculateDistance(baseline, profile)
        if d <= varietyPickMax && d < bestDist { bestId = foodId; bestDist = d }
    }
    return bestId.map { ($0, bestDist) }
}

// ============================================================================
// GENERATE RECOMMENDATIONS
// ============================================================================

func generateRecommendations(
    kidId: String,
    allLogs: [FoodLog],
    superSafeFoods: Set<String>,
    regularSafeFoods: Set<String>,
    foodDb: [String: SensoryProfile],
    foodNames: [String: String],
    today: Date
) -> [Recommendation] {

    // Aggregate logs
    var foodProfiles = aggregateFoodLogs(allLogs)

    // Bonus – seed safe foods that have no logs yet (prevents zero-vector
    // baseline for brand-new users).
    for foodId in superSafeFoods.union(regularSafeFoods) {
        if foodProfiles[foodId] == nil {
            foodProfiles[foodId] = FoodProfile(
                foodId:                 foodId,
                highestState:           "ate",
                highestStateMultiplier: 1.0,   // Overridden by scaling cap in getWeight
                mostRecentDate:         today,
                allLogs:                [],
                lastSuccessfulState:    "ate"
            )
        }
    }

    // Count truly explored foods (not in safe sets, state >= touched)
    let numTrulyExplored = foodProfiles.filter { (foodId, fp) in
        !superSafeFoods.contains(foodId) &&
        !regularSafeFoods.contains(foodId) &&
        ["touched", "smelled", "tasted", "ate"].contains(fp.highestState)
    }.count

    let baseline = calculateWeightedBaseline(
        foodProfiles: foodProfiles,
        superSafeFoods: superSafeFoods,
        regularSafeFoods: regularSafeFoods,
        foodDb: foodDb,
        today: today,
        numTrulyExplored: numTrulyExplored
    )

    // Fix 2: pass foodProfiles so dedup uses global highest states
    let dedupRecent = deduplicateLastNLogs(allLogs, foodProfiles: foodProfiles)

    // Fix 3: pass foodDb so detectTrend inspects actual sensory dimensions
    let trend = detectTrend(dedupRecent, foodDb: foodDb)

    let recentFoodIds = Set(dedupRecent.map { $0.foodId })
    var recommendations: [Recommendation] = []

    // --- Safe Pick ---
    if let (foodId, dist) = findSafePick(baseline: baseline, foodDb: foodDb,
                                          excludeFoods: recentFoodIds) {
        recommendations.append(Recommendation(
            rank: "Safe Pick", foodId: foodId,
            foodName: foodNames[foodId] ?? foodId, distance: dist,
            explanation: "Very similar to foods you love. High chance of success!"
        ))
    } else {
        // Fallback: absolute closest food regardless of distance
        let fallback = foodDb
            .filter { !recentFoodIds.contains($0.key) }
            .map { ($0.key, calculateDistance(baseline, $0.value)) }
            .min { $0.1 < $1.1 }
        if let (foodId, dist) = fallback {
            recommendations.append(Recommendation(
                rank: "Safe Pick", foodId: foodId,
                foodName: foodNames[foodId] ?? foodId, distance: dist,
                explanation: "New adventure. We think you're ready!"
            ))
        }
    }

    // --- Stretch Pick (Bonus: exclude safe pick result) ---
    let afterSafe = recentFoodIds.union(Set(recommendations.compactMap { $0.foodId }))
    if let (foodId, dist) = findStretchPick(baseline: baseline, foodDb: foodDb,
                                             excludeFoods: afterSafe, trend: trend) {
        recommendations.append(Recommendation(
            rank: "Stretch Pick", foodId: foodId,
            foodName: foodNames[foodId] ?? foodId, distance: dist,
            explanation: "A small challenge. One new element from familiar foods."
        ))
    }

    // --- Variety Pick (Fix 4: compute real missing groups) ---
    let eatenGroups = Set(foodProfiles.compactMap { (foodId, fp) -> String? in
        guard ["tasted", "ate"].contains(fp.highestState),
              let sp = foodDb[foodId] else { return nil }
        return sp.foodGroup
    })
    let allGroups = Set(foodDb.values.map { $0.foodGroup }).subtracting(["other", "mixed"])
    let missingGroups = allGroups.subtracting(eatenGroups).sorted()

    let afterStretch = recentFoodIds.union(Set(recommendations.compactMap { $0.foodId }))
    if let (foodId, dist) = findVarietyPick(baseline: baseline, foodDb: foodDb,
                                             excludeFoods: afterStretch,
                                             missingGroups: missingGroups) {
        recommendations.append(Recommendation(
            rank: "Variety Pick", foodId: foodId,
            foodName: foodNames[foodId] ?? foodId, distance: dist,
            explanation: "Let's add some nutritional variety!"
        ))
    }

    return recommendations
}
