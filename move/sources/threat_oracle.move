module astrologistics::threat_oracle;

use sui::table::{Self, Table};
use sui::clock::{Self, Clock};
use sui::event;
use astrologistics::constants;

// ============ Error codes ============
const E_BATCH_TOO_LARGE: u64 = 0;
const E_BATCH_LENGTH_MISMATCH: u64 = 1;
const E_COOLDOWN_NOT_MET: u64 = 2;
const E_ROUTE_TOO_LONG: u64 = 3;
const E_DISABLED: u64 = 4;

// ============ Structs ============

public struct ThreatMap has key {
    id: UID,
    danger_scores: Table<u64, DangerEntry>,
    decay_lambda: u64, // FP_SCALE
}

public struct DangerEntry has store, drop, copy {
    score: u64,
    event_count: u64,
    last_updated: u64,
}

public struct OracleCap has key, store {
    id: UID,
}

public struct ReporterCap has key {
    id: UID,
    reporter: address,
    missions_completed: u64,
    last_report_at: u64,
    cooldown_ms: u64,
}

// ============ Events ============

public struct ThreatUpdated has copy, drop {
    system_id: u64,
    new_score: u64,
    source: vector<u8>,
}

public struct IncidentReported has copy, drop {
    system_id: u64,
    reporter: address,
    weight: u64,
}

public struct ReporterRevoked has copy, drop {
    reporter: address,
}

// ============ Public functions ============

/// Disabled after initial deployment — prevents rogue OracleCap minting (Fix C-1).
public fun create_threat_map(_decay_lambda: u64, _ctx: &mut TxContext): OracleCap {
    abort E_DISABLED
}

#[test_only]
/// Test-only: creates ThreatMap + OracleCap (original implementation).
public fun create_threat_map_for_testing(decay_lambda: u64, ctx: &mut TxContext): OracleCap {
    let map = ThreatMap {
        id: object::new(ctx),
        danger_scores: table::new(ctx),
        decay_lambda,
    };
    transfer::share_object(map);
    OracleCap { id: object::new(ctx) }
}

/// Oracle batch update — sets scores directly.
public fun batch_update(
    map: &mut ThreatMap,
    _cap: &OracleCap,
    system_ids: vector<u64>,
    scores: vector<u64>,
    clock: &Clock,
) {
    let len = system_ids.length();
    assert!(len == scores.length(), E_BATCH_LENGTH_MISMATCH);
    assert!(len <= constants::max_batch_size(), E_BATCH_TOO_LARGE);

    let now = clock::timestamp_ms(clock);
    let mut i = 0;
    while (i < len) {
        let sys_id = system_ids[i];
        let score = scores[i];
        if (table::contains(&map.danger_scores, sys_id)) {
            let entry = table::borrow_mut(&mut map.danger_scores, sys_id);
            entry.score = score;
            entry.last_updated = now;
        } else {
            table::add(&mut map.danger_scores, sys_id, DangerEntry {
                score,
                event_count: 0,
                last_updated: now,
            });
        };
        event::emit(ThreatUpdated { system_id: sys_id, new_score: score, source: b"oracle" });
        i = i + 1;
    };
}

/// Get danger score with time decay applied.
public fun get_danger_score(map: &ThreatMap, system_id: u64, clock: &Clock): u64 {
    if (!table::contains(&map.danger_scores, system_id)) {
        return 0
    };
    let entry = table::borrow(&map.danger_scores, system_id);
    let now = clock::timestamp_ms(clock);
    apply_decay(entry.score, now, entry.last_updated, map.decay_lambda)
}

/// Max danger score along a route
public fun max_danger_on_route(map: &ThreatMap, route: &vector<u64>, clock: &Clock): u64 {
    assert!(route.length() <= constants::max_route_length(), E_ROUTE_TOO_LONG);
    let mut max_score = 0u64;
    let mut i = 0;
    while (i < route.length()) {
        let score = get_danger_score(map, route[i], clock);
        if (score > max_score) {
            max_score = score;
        };
        i = i + 1;
    };
    max_score
}

/// Issue a ReporterCap (gated by OracleCap)
public fun issue_reporter_cap(
    _cap: &OracleCap,
    reporter: address,
    missions_completed: u64,
    ctx: &mut TxContext,
): ReporterCap {
    ReporterCap {
        id: object::new(ctx),
        reporter,
        missions_completed,
        last_report_at: 0,
        cooldown_ms: constants::reporter_cooldown_ms(),
    }
}

/// Reporter reports an incident (with cooldown + weight)
public fun report_incident(
    map: &mut ThreatMap,
    reporter_cap: &mut ReporterCap,
    system_id: u64,
    clock: &Clock,
) {
    let now = clock::timestamp_ms(clock);
    assert!(
        reporter_cap.last_report_at == 0 || now >= reporter_cap.last_report_at + reporter_cap.cooldown_ms,
        E_COOLDOWN_NOT_MET,
    );

    // Weight based on missions_completed: min(missions, 10) * FP_SCALE / 10
    let missions_capped = if (reporter_cap.missions_completed > 10) { 10 } else { reporter_cap.missions_completed };
    let weight = missions_capped * constants::fp_scale() / 10;
    let base_increment = 100;
    let score_increment = base_increment * weight / constants::fp_scale();

    if (table::contains(&map.danger_scores, system_id)) {
        let entry = table::borrow_mut(&mut map.danger_scores, system_id);
        entry.score = apply_decay(entry.score, now, entry.last_updated, map.decay_lambda) + score_increment;
        entry.event_count = entry.event_count + 1;
        entry.last_updated = now;
    } else {
        table::add(&mut map.danger_scores, system_id, DangerEntry {
            score: score_increment,
            event_count: 1,
            last_updated: now,
        });
    };

    reporter_cap.last_report_at = now;
    event::emit(IncidentReported { system_id, reporter: reporter_cap.reporter, weight });
}

/// Revoke a reporter (burn their cap)
public fun revoke_reporter(_cap: &OracleCap, reporter_cap: ReporterCap) {
    let reporter_addr = reporter_cap.reporter;
    let ReporterCap { id, reporter: _, missions_completed: _, last_report_at: _, cooldown_ms: _ } = reporter_cap;
    object::delete(id);
    event::emit(ReporterRevoked { reporter: reporter_addr });
}

/// Transfer a ReporterCap to a specific address (since ReporterCap is key-only)
public fun transfer_reporter_cap(cap: ReporterCap, recipient: address) {
    transfer::transfer(cap, recipient);
}

/// Increment missions_completed on a ReporterCap
public fun increment_missions(reporter_cap: &mut ReporterCap) {
    reporter_cap.missions_completed = reporter_cap.missions_completed + 1;
}

// ============ Internal ============

/// 3rd-order Taylor approximation of e^(-x):
/// e^(-x) ≈ 1 - x + x²/2 - x³/6
fun apply_decay(score: u64, now: u64, last_updated: u64, lambda: u64): u64 {
    if (now <= last_updated) { return score };
    let dt_ms = now - last_updated;
    let dt_hours = dt_ms / 3_600_000;
    if (dt_hours == 0) { return score };

    let fp = constants::fp_scale();
    let x = lambda * dt_hours / fp;

    if (x >= fp) {
        return 0
    };

    let x2 = x * x / fp;
    let x3 = x2 * x / fp;
    // decay_factor = fp - x + x2/2 - x3/6
    // Safe: x < fp guaranteed, intermediate values bounded
    let decay_factor = fp - x + x2 / 2 - x3 / 6;
    let clamped = if (decay_factor > fp) { fp } else { decay_factor };

    score * clamped / fp
}
