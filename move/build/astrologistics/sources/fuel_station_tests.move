#[test_only]
module astrologistics::fuel_station_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use astrologistics::storage::{Self, Storage};
use astrologistics::fuel::{Self, FuelTreasuryCap};
use astrologistics::fuel_station::{Self, FuelStation, StationCap};

#[test]
fun test_create_station() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    // Setup storage
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(
            &s,
            100,    // base_price
            500,    // alpha (0.5 in FP_SCALE)
            1000,   // owner_fee_bps (10%)
            scenario.ctx(),
        );
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    scenario.next_tx(admin);
    {
        let station = test_scenario::take_shared<FuelStation>(&scenario);
        // No fuel supplied: price = base_price * (1 + alpha/FP) = 100 * (1000 + 500) / 1000 = 150
        assert!(fuel_station::current_price(&station) == 150);
        let (current, max) = fuel_station::fuel_level(&station);
        assert!(current == 0 && max == 0);
        test_scenario::return_shared(station);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = fuel_station::E_FEE_TOO_HIGH)]
fun test_create_station_fee_too_high() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        // 6000 > MAX_OWNER_FEE_BPS (5000) — should fail
        let station_cap = fuel_station::create_station(&s, 100, 500, 6000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = fuel_station::E_ALPHA_TOO_HIGH)]
fun test_create_station_alpha_too_high() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        // 20000 > max_alpha (10000) — should fail
        let station_cap = fuel_station::create_station(&s, 100, 20000, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
fun test_supply_and_buy_fuel() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let buyer = @0xA3;
    let mut scenario = test_scenario::begin(admin);

    // Setup
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    // Supplier adds fuel
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 10000, scenario.ctx());

        let receipt = fuel_station::supply_fuel(&mut station, fuel, scenario.ctx());

        let (current, max) = fuel_station::fuel_level(&station);
        assert!(current == 10000 && max == 10000);

        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };

    // Buyer buys fuel (Fix C2: no treasury param)
    scenario.next_tx(buyer);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let price = fuel_station::current_price(&station);

        // Buy 100 units of fuel
        let payment = coin::mint_for_testing<sui::sui::SUI>(price * 100, scenario.ctx());

        let fuel_out = fuel_station::buy_fuel(
            &mut station, payment, 100, price + 10, scenario.ctx(),
        );

        assert!(coin::value(&fuel_out) == 100);
        let (current, _) = fuel_station::fuel_level(&station);
        assert!(current == 9900);

        coin::burn_for_testing(fuel_out);
        test_scenario::return_shared(station);
    };

    // Supplier claims revenue
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut receipt = test_scenario::take_from_sender<fuel_station::SupplierReceipt>(&scenario);

        let revenue = fuel_station::claim_revenue(&mut station, &mut receipt, scenario.ctx());
        assert!(coin::value(&revenue) > 0);

        coin::burn_for_testing(revenue);
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_shared(station);
    };
    scenario.end();
}

#[test]
fun test_withdraw_supplier() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    // Supply fuel
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 5000, scenario.ctx());
        let receipt = fuel_station::supply_fuel(&mut station, fuel, scenario.ctx());
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };

    // Withdraw supplier (exit) — Fix C2: no treasury param
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let receipt = test_scenario::take_from_sender<fuel_station::SupplierReceipt>(&scenario);

        let (revenue, fuel_back) = fuel_station::withdraw_supplier(
            &mut station, receipt, scenario.ctx(),
        );

        // Should get back fuel (no sales happened, so revenue = 0)
        assert!(coin::value(&revenue) == 0);
        assert!(coin::value(&fuel_back) == 5000);

        coin::burn_for_testing(revenue);
        coin::burn_for_testing(fuel_back);
        test_scenario::return_shared(station);
    };
    scenario.end();
}

#[test]
fun test_update_pricing() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 500, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };
    scenario.next_tx(admin);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let cap = test_scenario::take_from_sender<StationCap>(&scenario);

        fuel_station::update_pricing(&mut station, &cap, 200, 800);
        // No fuel: price = 200 * (1000 + 800) / 1000 = 360
        assert!(fuel_station::current_price(&station) == 360);

        fuel_station::update_fee(&mut station, &cap, 2000);
        // Should pass (2000 <= 5000)

        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(station);
    };
    scenario.end();
}

#[test]
fun test_add_supply_with_pending_rewards() {
    let admin = @0xAD;
    let supplier = @0xA2;
    let buyer = @0xA3;
    let mut scenario = test_scenario::begin(admin);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let s = test_scenario::take_shared<Storage>(&scenario);
        let station_cap = fuel_station::create_station(&s, 100, 0, 1000, scenario.ctx());
        transfer::public_transfer(station_cap, admin);
        test_scenario::return_shared(s);
    };

    // Initial supply
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let fuel = fuel::mint(&mut treasury, 1000, scenario.ctx());
        let receipt = fuel_station::supply_fuel(&mut station, fuel, scenario.ctx());
        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };

    // Buyer buys some fuel (generates revenue)
    scenario.next_tx(buyer);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let price = fuel_station::current_price(&station);
        let payment = coin::mint_for_testing<sui::sui::SUI>(price * 100, scenario.ctx());
        let fuel_out = fuel_station::buy_fuel(
            &mut station, payment, 100, price + 10, scenario.ctx(),
        );
        coin::burn_for_testing(fuel_out);
        test_scenario::return_shared(station);
    };

    // Supplier adds more supply — should auto-flush pending rewards
    scenario.next_tx(supplier);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, admin);
        let mut receipt = test_scenario::take_from_sender<fuel_station::SupplierReceipt>(&scenario);
        let fuel = fuel::mint(&mut treasury, 500, scenario.ctx());

        fuel_station::add_supply(&mut station, &mut receipt, fuel, scenario.ctx());

        transfer::public_transfer(receipt, supplier);
        test_scenario::return_to_address(admin, treasury);
        test_scenario::return_shared(station);
    };
    // If auto-flush worked, supplier should have received SUI in the previous tx
    scenario.end();
}
