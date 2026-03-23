#[test_only]
module astrologistics::threat_oracle_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap};

/// Query non-existent system returns 0
#[test]
fun test_query_nonexistent_system() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        assert!(threat_oracle::get_danger_score(&map, 99999, &clock) == 0);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Empty route returns 0
#[test]
fun test_empty_route_max_danger() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let route = vector[];
        assert!(threat_oracle::max_danger_on_route(&map, &route, &clock) == 0);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Empty batch update (0 entries)
#[test]
fun test_batch_update_empty() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        threat_oracle::batch_update(&mut map, &cap, vector[], vector[], &clock);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Extreme decay — fully decayed to 0
#[test]
fun test_extreme_decay() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(900, scenario.ctx()); // aggressive lambda
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);
        threat_oracle::batch_update(&mut map, &cap, vector[1], vector[10000], &clock);
        // After 1200 hours: x = 900 * 1200 / 1000 = 1080 >= fp → clamp to 0
        clock::set_for_testing(&mut clock, 1200 * 3_600_000);
        assert!(threat_oracle::get_danger_score(&map, 1, &clock) == 0);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Revoke reporter cap
#[test]
fun test_revoke_reporter() {
    let admin = @0xAD;
    let courier = @0xC1;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let reporter_cap = threat_oracle::issue_reporter_cap(&cap, courier, 5, scenario.ctx());
        threat_oracle::revoke_reporter(&cap, reporter_cap);
        test_scenario::return_to_sender(&scenario, cap);
    };
    scenario.end();
}

/// Batch too large should fail
#[test]
#[expected_failure(abort_code = threat_oracle::E_BATCH_TOO_LARGE)]
fun test_batch_too_large() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Create 101 entries (max is 100)
        let mut ids = vector[];
        let mut scores = vector[];
        let mut i = 0;
        while (i <= 100) {
            ids.push_back(i);
            scores.push_back(100);
            i = i + 1;
        };
        threat_oracle::batch_update(&mut map, &cap, ids, scores, &clock);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Route too long should fail
#[test]
#[expected_failure(abort_code = threat_oracle::E_ROUTE_TOO_LONG)]
fun test_route_too_long() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Create route with 51 entries (max is 50)
        let mut route = vector[];
        let mut i = 0;
        while (i <= 50) {
            route.push_back(i);
            i = i + 1;
        };
        let _ = threat_oracle::max_danger_on_route(&map, &route, &clock);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
