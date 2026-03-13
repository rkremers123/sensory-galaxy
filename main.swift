// main.swift
// Swift test runner for Bridge Food Algorithm v3
// Mirrors test_algorithm.py – outputs pipe-delimited lines for comparison.
//
// Changes vs. first translation:
// – foodGroup added to every SensoryProfile in foodDb
// – honey_crackers added (grain) to match Python test suite
// – detectTrend call updated to pass foodDb (Fix 3)

import Foundation

// ============================================================================
// FOOD DATABASE (identical values to test_algorithm.py, + foodGroup)
// ============================================================================

let foodDb: [String: SensoryProfile] = [
 "nuggets": SensoryProfile(
 texture: 6.0, flavorSweet: 2.0, flavorSalty: 7.0,
 flavorSavory: 5.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 50.0, color: "brown", mouthfeel: "crispy",
 prepMethod: "fried", foodGroup: "protein"),

 "toast": SensoryProfile(
 texture: 6.0, flavorSweet: 1.0, flavorSalty: 3.0,
 flavorSavory: 2.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 45.0, color: "brown", mouthfeel: "crispy",
 prepMethod: "baked", foodGroup: "grain"),

 "rice": SensoryProfile(
 texture: 4.0, flavorSweet: 0.0, flavorSalty: 1.0,
 flavorSavory: 1.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 45.0, color: "white", mouthfeel: "soft",
 prepMethod: "boiled", foodGroup: "grain"),

 "cheese": SensoryProfile(
 texture: 3.0, flavorSweet: 0.0, flavorSalty: 6.0,
 flavorSavory: 7.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 25.0, color: "yellow", mouthfeel: "creamy",
 prepMethod: "raw", foodGroup: "dairy"),

 "seaweed": SensoryProfile(
 texture: 8.0, flavorSweet: 0.0, flavorSalty: 8.0,
 flavorSavory: 6.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 25.0, color: "green", mouthfeel: "crispy",
 prepMethod: "raw", foodGroup: "vegetable"),

 "sweet_potato": SensoryProfile(
 texture: 4.0, flavorSweet: 7.0, flavorSalty: 1.0,
 flavorSavory: 2.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 45.0, color: "orange", mouthfeel: "creamy",
 prepMethod: "baked", foodGroup: "vegetable"),

 "apple": SensoryProfile(
 texture: 7.0, flavorSweet: 8.0, flavorSalty: 0.0,
 flavorSavory: 0.0, flavorSour: 2.0, flavorBitter: 0.0,
 temperature: 15.0, color: "red", mouthfeel: "crispy",
 prepMethod: "raw", foodGroup: "fruit"),

 "banana": SensoryProfile(
 texture: 2.0, flavorSweet: 8.0, flavorSalty: 0.0,
 flavorSavory: 0.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 20.0, color: "yellow", mouthfeel: "creamy",
 prepMethod: "raw", foodGroup: "fruit"),

 "broccoli": SensoryProfile(
 texture: 5.0, flavorSweet: 2.0, flavorSalty: 1.0,
 flavorSavory: 3.0, flavorSour: 0.0, flavorBitter: 7.0,
 temperature: 25.0, color: "green", mouthfeel: "crispy",
 prepMethod: "raw", foodGroup: "vegetable"),

 "honey_crackers": SensoryProfile(
 texture: 7.0, flavorSweet: 6.0, flavorSalty: 2.0,
 flavorSavory: 1.0, flavorSour: 0.0, flavorBitter: 0.0,
 temperature: 20.0, color: "tan", mouthfeel: "crispy",
 prepMethod: "baked", foodGroup: "grain"),
]

let foodNames: [String: String] = [
 "nuggets": "Chicken Nuggets",
 "toast": "Toast",
 "rice": "White Rice",
 "cheese": "Cheddar Cheese",
 "seaweed": "Seaweed Snacks",
 "sweet_potato": "Sweet Potato Fries",
 "apple": "Apple Slices",
 "banana": "Banana",
 "broccoli": "Broccoli",
 "honey_crackers":"Honey Crackers",
]

let superSafe: Set<String> = ["nuggets", "toast"]
let regularSafe: Set<String> = ["rice", "cheese"]

// ============================================================================
// TEST HELPERS
// ============================================================================

func runTest(name: String, logs: [FoodLog], today: Date) -> [Recommendation] {
 let recs = generateRecommendations(
 kidId: "test_kid_1",
 allLogs: logs,
 superSafeFoods: superSafe,
 regularSafeFoods: regularSafe,
 foodDb: foodDb,
 foodNames: foodNames,
 today: today
 )
 print("SWIFT:\(name)")
 for rec in recs {
 let dist = rec.distance.map { String(format: "%.4f", $0) } ?? "None"
 print(" \(rec.rank)|\(rec.foodId ?? "nil")|\(rec.foodName ?? "nil")|\(dist)")
 }
 return recs
}

// ============================================================================
// TEST 1 – Week 1: Static baseline (no logs)
// ============================================================================

func testWeek1() -> [Recommendation] {
 return runTest(name: "WEEK1", logs: [], today: makeDate(year: 2026, month: 3, day: 1))
}

// ============================================================================
// TEST 2 – Week 2: Dynamic baseline with exposure states
// ============================================================================

func testWeek2() -> [Recommendation] {
 let logs: [FoodLog] = [
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 2), exposureStates: ["looked_at"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 5), exposureStates: ["touched", "smelled"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 8), exposureStates: ["tasted"]),
 FoodLog(foodId: "seaweed", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 3), exposureStates: ["looked_at", "touched"]),
 FoodLog(foodId: "sweet_potato", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 6), exposureStates: ["tasted"]),
 FoodLog(foodId: "banana", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 10), exposureStates: ["looked_at"]),
 FoodLog(foodId: "seaweed", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 11), exposureStates: ["looked_at"]),
 ]
 return runTest(name: "WEEK2", logs: logs, today: makeDate(year: 2026, month: 3, day: 12))
}

// ============================================================================
// TEST 3 – Week 3: Trend detection (sweet streak)
// ============================================================================

func testWeek3() -> [Recommendation] {
 let logs: [FoodLog] = [
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 2), exposureStates: ["looked_at"]),
 FoodLog(foodId: "seaweed", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 3), exposureStates: ["looked_at", "touched"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 15), exposureStates: ["ate"]),
 FoodLog(foodId: "banana", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 16), exposureStates: ["ate"]),
 FoodLog(foodId: "sweet_potato", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 17), exposureStates: ["tasted"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 18), exposureStates: ["ate"]),
 FoodLog(foodId: "banana", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 19), exposureStates: ["ate"]),
 FoodLog(foodId: "seaweed", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 20), exposureStates: ["ate"]),
 FoodLog(foodId: "sweet_potato", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 21), exposureStates: ["ate"]),
 ]
 return runTest(name: "WEEK3", logs: logs, today: makeDate(year: 2026, month: 3, day: 22))
}

// ============================================================================
// TEST 4 – Edge case: Deduplication (same food logged 5x)
// ============================================================================

func testDeduplication() -> [Recommendation] {
 let logs: [FoodLog] = [
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 15), exposureStates: ["looked_at"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 16), exposureStates: ["looked_at"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 17), exposureStates: ["touched"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 18), exposureStates: ["looked_at"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 19), exposureStates: ["tasted"]),
 ]
 return runTest(name: "DEDUP", logs: logs, today: makeDate(year: 2026, month: 3, day: 20))
}

// ============================================================================
// TEST 5 – Edge case: Regression (tasted → ate → ate → looked_at)
// ============================================================================

func testRegression() -> [Recommendation] {
 let logs: [FoodLog] = [
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 10), exposureStates: ["tasted"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 12), exposureStates: ["ate"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 14), exposureStates: ["ate"]),
 FoodLog(foodId: "apple", kidId: "test_kid_1",
 timestamp: makeDate(year: 2026, month: 3, day: 20), exposureStates: ["looked_at"]),
 ]
 return runTest(name: "REGRESSION", logs: logs, today: makeDate(year: 2026, month: 3, day: 21))
}

// ============================================================================
// MAIN
// ============================================================================

testWeek1()
testWeek2()
testWeek3()
testDeduplication()
testRegression()
