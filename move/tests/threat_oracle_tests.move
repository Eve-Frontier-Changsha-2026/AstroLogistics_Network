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
        let oracle_cap = threat_oracle::create_threat_map(100, scenario.ctx());
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
        let cap = threat_oracle::create_threat_map(100, scenario.ctx());
        transfer::public_transfer(cap, admin);
    };
    scenario.next_tx(admin);
    {
        let mut map = test_scenario::take_shared<ThreatMap>(&scenario);
        let cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        threat_oracle::batch_update(&mut map, &cap, vector[10u64, 20u64], vector[800u64, 1500u64], &clock);

        let score_10 = threat_oracle::get_danger_score(&map, 10, &clock);
        let score_20 = threat_oracle::get_danger_score(&map, 20, &clock);
        assert!(score_10 == 800);
        assert!(score_20 == 1500);

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(map);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
