#[test_only]
module astrologistics::threat_oracle_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap, ReporterCap};

#[test]
fun test_create_threat_map() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        assert!(test_scenario::has_most_recent_for_sender<OracleCap>(&scenario));
        let map = test_scenario::take_shared<ThreatMap>(&scenario);
        test_scenario::return_shared(map);
    };
    scenario.end();
}

#[test]
fun test_batch_update_and_query() {
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
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        threat_oracle::batch_update(&mut map, &cap, vector[10u64, 20u64], vector[800u64, 1500u64], &clock);
        assert!(threat_oracle::get_danger_score(&map, 10, &clock) == 800);
        assert!(threat_oracle::get_danger_score(&map, 20, &clock) == 1500);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_reporter_incident_with_cooldown() {
    let admin = @0xAD;
    let courier = @0xC1;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let reporter_cap = threat_oracle::issue_reporter_cap(&cap, courier, 5, scenario.ctx());
        threat_oracle::transfer_reporter_cap(reporter_cap, courier);
        test_scenario::return_to_sender(&scenario, cap);
    };
    scenario.next_tx(courier);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let mut reporter = test_scenario::take_from_sender<ReporterCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        threat_oracle::report_incident(&mut map, &mut reporter, 42, &clock);
        let score = threat_oracle::get_danger_score(&map, 42, &clock);
        assert!(score > 0);
        test_scenario::return_to_sender(&scenario, reporter);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = threat_oracle::E_COOLDOWN_NOT_MET)]
fun test_reporter_cooldown_enforced() {
    let admin = @0xAD;
    let courier = @0xC1;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let reporter_cap = threat_oracle::issue_reporter_cap(&cap, courier, 5, scenario.ctx());
        threat_oracle::transfer_reporter_cap(reporter_cap, courier);
        test_scenario::return_to_sender(&scenario, cap);
    };
    scenario.next_tx(courier);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let mut reporter = test_scenario::take_from_sender<ReporterCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        threat_oracle::report_incident(&mut map, &mut reporter, 42, &clock);
        // Try again 1 second later — should fail
        clock::set_for_testing(&mut clock, 2000);
        threat_oracle::report_incident(&mut map, &mut reporter, 42, &clock);
        test_scenario::return_to_sender(&scenario, reporter);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_danger_score_decays_over_time() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map_for_testing(500, scenario.ctx()); // lambda=0.5/hr
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);
        threat_oracle::batch_update(&mut map, &cap, vector[10], vector[1000], &clock);
        assert!(threat_oracle::get_danger_score(&map, 10, &clock) == 1000);
        // After 2 hours: should be less
        clock::set_for_testing(&mut clock, 2 * 3_600_000);
        let score_later = threat_oracle::get_danger_score(&map, 10, &clock);
        assert!(score_later < 1000);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_max_danger_on_route() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let oracle_cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 0);
        threat_oracle::batch_update(&mut map, &cap, vector[10, 20, 30], vector[500, 1200, 800], &clock);
        let route = vector[10, 20, 30];
        let max_d = threat_oracle::max_danger_on_route(&map, &route, &clock);
        assert!(max_d == 1200);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
