#!/usr/bin/env python3
"""
Bridge Food Recommendation Algorithm v3 - Reference Implementation

SOS-based recommendation engine with dynamic weighted baseline,
exposure state tracking, and trend detection.

Ready for Swift translation after Claude review.
"""

import math
from typing import Dict, List, Tuple, Optional, Set
from dataclasses import dataclass
from datetime import datetime, timedelta
from enum import Enum


# ============================================================================
# DATA MODELS
# ============================================================================

class ExposureState(Enum):
    """SOS exposure states from looking → eating."""
    LOOKED_AT = ("looked_at", 0.3)
    TOUCHED = ("touched", 0.5)
    SMELLED = ("smelled", 0.6)
    TASTED = ("tasted", 0.8)
    ATE = ("ate", 1.0)

    def __init__(self, name_str: str, multiplier: float):
        self.state_name = name_str
        self.multiplier = multiplier


@dataclass
class SensoryProfile:
    """6-dimensional sensory profile for a food."""
    texture: float  # 0-10 (liquid → hard)
    flavor_sweet: float  # 0-10
    flavor_salty: float  # 0-10
    flavor_savory: float  # 0-10
    flavor_sour: float  # 0-10
    flavor_bitter: float  # 0-10
    temperature: float  # 0-100 (celsius)
    color: str  # red, orange, yellow, green, brown, white, mixed
    mouthfeel: str  # juicy, dry, creamy, crispy, tender, chewy
    prep_method: str  # raw, boiled, baked, fried, steamed

    def to_vector(self) -> List[float]:
        """Convert to numeric vector for distance calculation."""
        return [
            self.texture,
            self.flavor_sweet,
            self.flavor_salty,
            self.flavor_savory,
            self.flavor_sour,
            self.flavor_bitter,
            self.temperature / 10,  # Normalize to 0-10 range
        ]


@dataclass
class FoodLog:
    """A single food log entry from parent."""
    food_id: str
    kid_id: str
    timestamp: datetime
    exposure_states: List[str]  # ["looked_at", "touched", "tasted"]
    parent_notes: Optional[str] = None


@dataclass
class FoodProfile:
    """Aggregated food info from multiple logs."""
    food_id: str
    highest_state: str
    highest_state_multiplier: float
    most_recent_date: datetime
    all_logs: List[FoodLog]
    last_successful_state: str  # From last 3 logs

    def get_weight(
        self,
        today: datetime,
        num_explored: int,
        is_super_safe: bool = False,
        is_regular_safe: bool = False,
    ) -> float:
        """Calculate composite weight: state × recency × scaling × regression."""
        # State multiplier
        state_mult = self.highest_state_multiplier

        # Recency weight
        days_ago = (today - self.most_recent_date).days
        recency = calculate_recency_weight(days_ago)

        # Super-safe / regular-safe scaling cap
        if is_super_safe:
            scaling = 0.60 / (1 + math.log(max(1, num_explored)))
            state_mult = scaling
        elif is_regular_safe:
            scaling = 0.40 / (1 + math.log(max(1, num_explored)))
            state_mult = scaling

        # Regression penalty
        regression_penalty = 1.0
        if self.last_successful_state != self.highest_state:
            regression_penalty = 0.8

        return state_mult * recency * regression_penalty


@dataclass
class Recommendation:
    """A single food recommendation."""
    rank: str  # "Safe Pick", "Stretch Pick", "Variety Pick"
    food_id: Optional[str]
    food_name: Optional[str]
    distance: Optional[float]
    explanation: str


# ============================================================================
# CONSTANTS
# ============================================================================

DISTANCE_WEIGHTS = {
    "texture": 0.15,
    "flavor_sweet": 0.08,
    "flavor_salty": 0.12,
    "flavor_savory": 0.08,
    "flavor_sour": 0.05,
    "flavor_bitter": 0.08,
    "temperature": 0.10,
}

SAFE_PICK_MAX = 2.5
STRETCH_PICK_MIN = 2.5
STRETCH_PICK_MAX = 4.5
VARIETY_PICK_MAX = 4.5

MIN_FOODS_FOR_TREND = 5
TREND_STRENGTH_THRESHOLD = 5 / 7  # 71% of foods


# ============================================================================
# WEIGHT CALCULATIONS
# ============================================================================

def calculate_recency_weight(days_ago: int) -> float:
    """Return weight based on how long ago food was logged."""
    if days_ago <= 3:
        return 1.0
    elif days_ago <= 7:
        return 0.75
    elif days_ago <= 14:
        return 0.50
    elif days_ago <= 30:
        return 0.25
    else:
        return 0.10


def calculate_distance(profile1: SensoryProfile, profile2: SensoryProfile) -> float:
    """
    Calculate multi-dimensional Euclidean distance between two sensory profiles.
    Lower = more similar.
    """
    vec1 = profile1.to_vector()
    vec2 = profile2.to_vector()

    distance_sq = 0.0
    for i, (v1, v2) in enumerate(zip(vec1, vec2)):
        diff = v1 - v2
        weight = list(DISTANCE_WEIGHTS.values())[i]
        distance_sq += weight * (diff ** 2)

    return math.sqrt(distance_sq)


def get_highest_state(state_names: List[str]) -> Tuple[str, float]:
    """
    Given a list of exposure state names, return the highest state and its multiplier.
    States are ordered: looked_at < touched < smelled < tasted < ate
    """
    state_order = {
        "looked_at": ExposureState.LOOKED_AT,
        "touched": ExposureState.TOUCHED,
        "smelled": ExposureState.SMELLED,
        "tasted": ExposureState.TASTED,
        "ate": ExposureState.ATE,
    }

    highest = None
    for state_name in state_names:
        state = state_order.get(state_name)
        if state and (highest is None or state.multiplier > highest.multiplier):
            highest = state

    if highest is None:
        # Default to looked_at if empty
        highest = ExposureState.LOOKED_AT

    return highest.state_name, highest.multiplier


# ============================================================================
# BASELINE CALCULATION
# ============================================================================

def aggregate_food_logs(
    all_logs: List[FoodLog],
) -> Dict[str, FoodProfile]:
    """
    Aggregate all logs by food_id.
    For each food, track highest state, most recent date, and last 3 logs.
    """
    food_profiles = {}

    for log in all_logs:
        if log.food_id not in food_profiles:
            highest_state, mult = get_highest_state(log.exposure_states)
            food_profiles[log.food_id] = FoodProfile(
                food_id=log.food_id,
                highest_state=highest_state,
                highest_state_multiplier=mult,
                most_recent_date=log.timestamp,
                all_logs=[log],
                last_successful_state=highest_state,
            )
        else:
            # Update highest state
            highest_state, mult = get_highest_state(
                food_profiles[log.food_id].all_logs[0].exposure_states
                + log.exposure_states
            )
            food_profiles[log.food_id].highest_state = highest_state
            food_profiles[log.food_id].highest_state_multiplier = mult

            # Update most recent date
            if log.timestamp > food_profiles[log.food_id].most_recent_date:
                food_profiles[log.food_id].most_recent_date = log.timestamp

            # Track last 3 logs for regression detection
            all_states = [s for l in food_profiles[log.food_id].all_logs for s in l.exposure_states]
            all_states.extend(log.exposure_states)
            last_3_states = all_states[-3:]
            last_success, _ = get_highest_state(last_3_states)
            food_profiles[log.food_id].last_successful_state = last_success

            food_profiles[log.food_id].all_logs.append(log)

    return food_profiles


def calculate_weighted_baseline(
    food_profiles: Dict[str, FoodProfile],
    super_safe_foods: Set[str],
    regular_safe_foods: Set[str],
    food_db: Dict[str, SensoryProfile],
    today: datetime,
) -> SensoryProfile:
    """
    Calculate weighted baseline from all foods.
    Weights: state × recency × scaling × regression
    """
    total_weight = 0.0
    weighted_vector = [0.0] * 7  # 7 dimensions in to_vector()

    # Super safe foods
    for food_id in super_safe_foods:
        profile = food_profiles.get(food_id)
        if profile and food_id in food_db:
            weight = profile.get_weight(
                today,
                len(food_profiles),
                is_super_safe=True,
            )
            vector = food_db[food_id].to_vector()
            for i, v in enumerate(vector):
                weighted_vector[i] += v * weight
            total_weight += weight

    # Regular safe foods
    for food_id in regular_safe_foods:
        profile = food_profiles.get(food_id)
        if profile and food_id in food_db:
            weight = profile.get_weight(
                today,
                len(food_profiles),
                is_regular_safe=True,
            )
            vector = food_db[food_id].to_vector()
            for i, v in enumerate(vector):
                weighted_vector[i] += v * weight
            total_weight += weight

    # Explored foods
    for food_id, profile in food_profiles.items():
        if food_id in super_safe_foods or food_id in regular_safe_foods:
            continue
        if food_id in food_db:
            weight = profile.get_weight(today, len(food_profiles))
            vector = food_db[food_id].to_vector()
            for i, v in enumerate(vector):
                weighted_vector[i] += v * weight
            total_weight += weight

    # Normalize
    if total_weight > 0:
        weighted_vector = [v / total_weight for v in weighted_vector]

    # Convert back to SensoryProfile
    return SensoryProfile(
        texture=weighted_vector[0],
        flavor_sweet=weighted_vector[1],
        flavor_salty=weighted_vector[2],
        flavor_savory=weighted_vector[3],
        flavor_sour=weighted_vector[4],
        flavor_bitter=weighted_vector[5],
        temperature=weighted_vector[6] * 10,  # Denormalize
        color="mixed",  # Baseline color is mixed
        mouthfeel="mixed",
        prep_method="mixed",
    )


# ============================================================================
# TREND DETECTION
# ============================================================================

def deduplicate_last_n_logs(all_logs: List[FoodLog], n: int = 7) -> List[Tuple[str, str, float]]:
    """
    Get last N logs, deduplicated by food_id.
    Returns: List of (food_id, highest_state, multiplier)
    """
    # Get last N logs, newest first
    recent = sorted(all_logs, key=lambda x: x.timestamp, reverse=True)[:n]

    # Deduplicate by food_id, taking highest state
    seen = {}
    for log in recent:
        if log.food_id not in seen:
            highest, mult = get_highest_state(log.exposure_states)
            seen[log.food_id] = (log.food_id, highest, mult)

    return list(seen.values())


def detect_trend(
    dedup_logs: List[Tuple[str, str, float]],
) -> Optional[Dict[str, float]]:
    """
    Detect trends in sensory dimensions from recent logs.
    Returns: Dict of {dimension: strength (0-1)} or None if no trend.
    """
    if len(dedup_logs) < MIN_FOODS_FOR_TREND:
        return None

    # Count sensory dimensions across logs
    # This is simplified - in real implementation, query food_db for full profiles
    dimension_counts = {
        "bitter": 0,
        "sweet": 0,
        "salty": 0,
        "crunchy": 0,
        "soft": 0,
    }

    # Analyze state progression as proxy for trend
    ate_count = sum(1 for _, state, _ in dedup_logs if state == "ate")
    tasted_count = sum(1 for _, state, _ in dedup_logs if state == "tasted")

    trend = {}
    trend_strength = (ate_count + tasted_count) / len(dedup_logs)

    if trend_strength >= TREND_STRENGTH_THRESHOLD:
        trend["oral_acceptance"] = trend_strength
        return trend

    return None


# ============================================================================
# RECOMMENDATION GENERATION
# ============================================================================

def find_safe_pick(
    baseline: SensoryProfile,
    food_db: Dict[str, SensoryProfile],
    exclude_foods: Set[str],
) -> Optional[Tuple[str, float]]:
    """Find closest food within SAFE_PICK_MAX distance."""
    best_food = None
    best_distance = float("inf")

    for food_id, profile in food_db.items():
        if food_id in exclude_foods:
            continue

        distance = calculate_distance(baseline, profile)
        if distance <= SAFE_PICK_MAX and distance < best_distance:
            best_food = food_id
            best_distance = distance

    return (best_food, best_distance) if best_food else None


def find_stretch_pick(
    baseline: SensoryProfile,
    food_db: Dict[str, SensoryProfile],
    exclude_foods: Set[str],
    trend: Optional[Dict[str, float]] = None,
) -> Optional[Tuple[str, float]]:
    """Find food in stretch distance range."""
    best_food = None
    best_distance = float("inf")

    for food_id, profile in food_db.items():
        if food_id in exclude_foods:
            continue

        distance = calculate_distance(baseline, profile)
        if STRETCH_PICK_MIN <= distance <= STRETCH_PICK_MAX and distance < best_distance:
            best_food = food_id
            best_distance = distance

    return (best_food, best_distance) if best_food else None


def find_variety_pick(
    baseline: SensoryProfile,
    food_db: Dict[str, SensoryProfile],
    exclude_foods: Set[str],
    missing_groups: List[str],
) -> Optional[Tuple[str, float]]:
    """
    Find food in missing nutritional group within variety distance.
    Returns None if no suitable variety pick exists (fallback to 2 picks).
    """
    if not missing_groups:
        return None

    # Simplified: just find closest in missing group
    # In real implementation, filter by food_group attribute
    best_food = None
    best_distance = float("inf")

    for food_id, profile in food_db.items():
        if food_id in exclude_foods:
            continue

        distance = calculate_distance(baseline, profile)
        if distance <= VARIETY_PICK_MAX and distance < best_distance:
            best_food = food_id
            best_distance = distance

    return (best_food, best_distance) if best_food else None


def generate_recommendations(
    kid_id: str,
    all_logs: List[FoodLog],
    super_safe_foods: Set[str],
    regular_safe_foods: Set[str],
    food_db: Dict[str, SensoryProfile],
    food_names: Dict[str, str],
    today: Optional[datetime] = None,
) -> List[Recommendation]:
    """
    Generate 3 daily recommendations using the full v3 algorithm.
    """
    if today is None:
        today = datetime.now()

    # Aggregate logs
    food_profiles = aggregate_food_logs(all_logs)

    # Calculate baseline
    baseline = calculate_weighted_baseline(
        food_profiles,
        super_safe_foods,
        regular_safe_foods,
        food_db,
        today,
    )

    # Detect trend
    dedup_recent = deduplicate_last_n_logs(all_logs)
    trend = detect_trend(dedup_recent)

    # Exclude recently logged foods
    recent_food_ids = {food_id for food_id, _, _ in dedup_recent}

    # Generate picks
    recommendations = []

    # Safe Pick
    safe_result = find_safe_pick(baseline, food_db, recent_food_ids)
    if safe_result:
        food_id, distance = safe_result
        recommendations.append(
            Recommendation(
                rank="Safe Pick",
                food_id=food_id,
                food_name=food_names.get(food_id, food_id),
                distance=distance,
                explanation=f"Very similar to foods you love. High chance of success!",
            )
        )
    else:
        # Fallback: return closest regardless of distance
        closest = min(
            ((fid, calculate_distance(baseline, fp)) for fid, fp in food_db.items()
             if fid not in recent_food_ids),
            key=lambda x: x[1],
            default=(None, float("inf")),
        )
        if closest[0]:
            recommendations.append(
                Recommendation(
                    rank="Safe Pick",
                    food_id=closest[0],
                    food_name=food_names.get(closest[0], closest[0]),
                    distance=closest[1],
                    explanation="New adventure. We think you're ready!",
                )
            )

    # Stretch Pick
    stretch_result = find_stretch_pick(baseline, food_db, recent_food_ids, trend)
    if stretch_result:
        food_id, distance = stretch_result
        recommendations.append(
            Recommendation(
                rank="Stretch Pick",
                food_id=food_id,
                food_name=food_names.get(food_id, food_id),
                distance=distance,
                explanation="A small challenge. One new element from familiar foods.",
            )
        )

    # Variety Pick
    missing_groups = ["vegetables"]  # Simplified
    variety_result = find_variety_pick(baseline, food_db, recent_food_ids, missing_groups)
    if variety_result:
        food_id, distance = variety_result
        recommendations.append(
            Recommendation(
                rank="Variety Pick",
                food_id=food_id,
                food_name=food_names.get(food_id, food_id),
                distance=distance,
                explanation="Let's add some nutritional variety!",
            )
        )

    return recommendations


# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    print("✅ Bridge Food Algorithm v3 - Reference Implementation Ready")
    print("Use this module in test_algorithm.py to validate against test cases.")
