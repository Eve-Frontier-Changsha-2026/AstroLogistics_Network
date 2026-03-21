#[test_only]
module astrologistics::fuel_tests;

use sui::test_scenario;
use sui::coin;
use astrologistics::fuel::{Self, FuelTreasuryCap};

#[test]
fun test_init_creates_treasury_cap() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        fuel::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(admin);
    {
        assert!(test_scenario::has_most_recent_for_sender<FuelTreasuryCap>(&scenario));
    };
    scenario.end();
}

#[test]
fun test_mint_and_burn() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        fuel::init_for_testing(scenario.ctx());
    };
    scenario.next_tx(admin);
    {
        let mut treasury = test_scenario::take_from_sender<FuelTreasuryCap>(&scenario);
        let fuel_coin = fuel::mint(&mut treasury, 1000, scenario.ctx());
        assert!(coin::value(&fuel_coin) == 1000);
        fuel::burn(&mut treasury, fuel_coin);
        test_scenario::return_to_sender(&scenario, treasury);
    };
    scenario.end();
}
