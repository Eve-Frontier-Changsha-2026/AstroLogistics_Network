#[test_only]
module astrologistics::fuel_station_monkey_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use astrologistics::storage::{Self, Storage};
use astrologistics::fuel::{Self, FuelTreasuryCap};
use astrologistics::fuel_station::{Self, FuelStation, StationCap};

/// Monkey: buy more fuel than available
#[test]
#[expected_failure(abort_code = fuel_station::E_INSUFFICIENT_FUEL)]
fun test_buy_more_than_available() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let buyer = @0xA3;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(supplier);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut t, 100, scenario.ctx());
        let r = fuel_station::supply_fuel(&mut st, fuel, scenario.ctx());
        transfer::public_transfer(r, supplier);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.next_tx(buyer);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let payment = coin::mint_for_testing<sui::sui::SUI>(1_000_000, scenario.ctx());
        // Try to buy 200 but only 100 available
        let f = fuel_station::buy_fuel(&mut st, payment, 200, 10000, scenario.ctx());
        coin::burn_for_testing(f);
        test_scenario::return_shared(st);
    };
    scenario.end();
}

/// Monkey: slippage protection — price exceeds max
#[test]
#[expected_failure(abort_code = fuel_station::E_PRICE_EXCEEDS_MAX)]
fun test_slippage_protection() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let buyer = @0xA3;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        // High alpha = 900 means price spikes when scarce
        let sc = fuel_station::create_station(&s, 100, 900, 0, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(supplier);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut t, 100, scenario.ctx());
        let r = fuel_station::supply_fuel(&mut st, fuel, scenario.ctx());
        transfer::public_transfer(r, supplier);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.next_tx(buyer);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let payment = coin::mint_for_testing<sui::sui::SUI>(1_000_000, scenario.ctx());
        // Set max_price_per_unit very low (50) — actual price is higher
        let f = fuel_station::buy_fuel(&mut st, payment, 10, 50, scenario.ctx());
        coin::burn_for_testing(f);
        test_scenario::return_shared(st);
    };
    scenario.end();
}

/// Monkey: update fee above cap should fail
#[test]
#[expected_failure(abort_code = fuel_station::E_FEE_TOO_HIGH)]
fun test_update_fee_above_cap() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let cap = test_scenario::take_from_sender<StationCap>(&scenario);
        // 6000 > 5000 cap — should fail
        fuel_station::update_fee(&mut st, &cap, 6000);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(st);
    };
    scenario.end();
}

/// Monkey: cap mismatch — use wrong StationCap
#[test]
#[expected_failure(abort_code = fuel_station::E_CAP_MISMATCH)]
fun test_cap_mismatch_update_pricing() {
    let admin = @0xAD;
    let admin2 = @0xAD2;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    // Create two stations
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin2);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap2 = storage::create_storage(2, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap2, admin2);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin2);
    {
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let sc2 = fuel_station::create_station(&s2, 200, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc2, admin2);
        test_scenario::return_shared(s2);
    };

    // Try to update wrong station with admin2's cap
    scenario.next_tx(admin2);
    {
        // Take both stations, find the one that DOESN'T match cap2
        let mut st_a = test_scenario::take_shared<FuelStation>(&scenario);
        let mut st_b = test_scenario::take_shared<FuelStation>(&scenario);
        let cap2 = test_scenario::take_from_sender<StationCap>(&scenario);
        let cap2_station = fuel_station::station_id_from_cap(&cap2);

        if (object::id(&st_a) != cap2_station) {
            // st_a is the wrong one — update it with cap2 (should fail)
            fuel_station::update_pricing(&mut st_a, &cap2, 300, 100);
            test_scenario::return_to_sender(&scenario, cap2);
            test_scenario::return_shared(st_a);
            test_scenario::return_shared(st_b);
        } else {
            // st_b is the wrong one — update it with cap2 (should fail)
            fuel_station::update_pricing(&mut st_b, &cap2, 300, 100);
            test_scenario::return_to_sender(&scenario, cap2);
            test_scenario::return_shared(st_a);
            test_scenario::return_shared(st_b);
        };
    };
    scenario.end();
}

/// Monkey: insufficient SUI payment
#[test]
#[expected_failure(abort_code = fuel_station::E_INSUFFICIENT_PAYMENT)]
fun test_insufficient_payment() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let buyer = @0xA3;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 0, 0, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(supplier);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let mut t = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut t, 1000, scenario.ctx());
        let r = fuel_station::supply_fuel(&mut st, fuel, scenario.ctx());
        transfer::public_transfer(r, supplier);
        test_scenario::return_to_address(admin, t);
        test_scenario::return_shared(st);
    };
    scenario.next_tx(buyer);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        // Price is 100 per unit, buying 10 = 1000 SUI needed, but only send 1
        let payment = coin::mint_for_testing<sui::sui::SUI>(1, scenario.ctx());
        let f = fuel_station::buy_fuel(&mut st, payment, 10, 200, scenario.ctx());
        coin::burn_for_testing(f);
        test_scenario::return_shared(st);
    };
    scenario.end();
}

/// Monkey: receipt mismatch — claim revenue with wrong station's receipt
#[test]
#[expected_failure(abort_code = fuel_station::E_RECEIPT_MISMATCH)]
fun test_claim_revenue_receipt_mismatch() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        transfer::public_transfer(cap2, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    // Create two stations
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin);
    {
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let sc2 = fuel_station::create_station(&s2, 200, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc2, admin);
        test_scenario::return_shared(s2);
    };

    // Supply fuel to station 1
    scenario.next_tx(supplier);
    {
        let mut st1 = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 1000, scenario.ctx());
        let receipt = fuel_station::supply_fuel(&mut st1, fuel, scenario.ctx());
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(st1);
    };

    // Try to claim from station 2 using station 1's receipt
    scenario.next_tx(supplier);
    {
        // Take both stations — we want the "other" one
        let st1 = test_scenario::take_shared<FuelStation>(&scenario);
        let mut st2 = test_scenario::take_shared<FuelStation>(&scenario);
        let mut receipt = test_scenario::take_from_sender<fuel_station::SupplierReceipt>(&scenario);

        // This should fail — receipt is for st1, not st2
        let revenue = fuel_station::claim_revenue(&mut st2, &mut receipt, scenario.ctx());
        coin::burn_for_testing(revenue);
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_shared(st1);
        test_scenario::return_shared(st2);
    };
    scenario.end();
}

/// Monkey: alpha too high in update_pricing
#[test]
#[expected_failure(abort_code = fuel_station::E_ALPHA_TOO_HIGH)]
fun test_update_pricing_alpha_too_high() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let sc = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(sc, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin);
    {
        let mut st = test_scenario::take_shared<FuelStation>(&scenario);
        let cap = test_scenario::take_from_sender<StationCap>(&scenario);
        // 20000 > max_alpha (10000) — should fail
        fuel_station::update_pricing(&mut st, &cap, 100, 20000);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(st);
    };
    scenario.end();
}
