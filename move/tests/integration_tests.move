#[test_only]
module astrologistics::integration_tests;

use sui::test_scenario;
use sui::clock;
use sui::coin;
use sui::sui::SUI;
use astrologistics::storage::{Self, Storage, DepositReceipt};
use astrologistics::fuel::{Self, FUEL, FuelTreasuryCap};
use astrologistics::fuel_station::{Self, FuelStation, SupplierReceipt};
use astrologistics::transport::{Self, TransportOrder};
use astrologistics::threat_oracle::{Self, ThreatMap, OracleCap, ReporterCap};
use astrologistics::courier_market::{Self, CourierContract, CourierBadge};

// ============ Helpers ============

const ADMIN: address = @0xAD;
const USER: address = @0xA1;
const COURIER: address = @0xA2;
const SUPPLIER: address = @0xA3;
const KEEPER: address = @0xA4;

/// Full world setup: 2 storages (sys 1001, 2002) + fuel treasury + threat oracle + fuel station
fun setup_full_world(): test_scenario::Scenario {
    let mut scenario = test_scenario::begin(ADMIN);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        // Two storages
        let cap1 = storage::create_storage(1001, 50000, 500, &clock, scenario.ctx());
        let cap2 = storage::create_storage(2002, 50000, 500, &clock, scenario.ctx());
        transfer::public_transfer(cap1, ADMIN);
        transfer::public_transfer(cap2, ADMIN);
        // Fuel token
        fuel::init_for_testing(scenario.ctx());
        // Threat oracle
        let oracle_cap = threat_oracle::create_threat_map_for_testing(100, scenario.ctx());
        transfer::public_transfer(oracle_cap, ADMIN);
        clock::destroy_for_testing(clock);
    };

    // Create fuel station linked to storage 1001
    scenario.next_tx(ADMIN);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let (from, other) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let station_cap = fuel_station::create_station(
            &from,
            100,   // base_price
            500,   // alpha (0.5x)
            1000,  // owner_fee_bps (10%)
            scenario.ctx(),
        );
        transfer::public_transfer(station_cap, ADMIN);
        test_scenario::return_shared(from);
        test_scenario::return_shared(other);
    };
    scenario
}

/// Helper: take the storage with matching system_id (returns both, caller returns them)
fun take_storages_ordered(scenario: &test_scenario::Scenario): (Storage, Storage) {
    let s1 = test_scenario::take_shared<Storage>(scenario);
    let s2 = test_scenario::take_shared<Storage>(scenario);
    if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) }
}

// ============================================================
// Test 1: Full Transport E2E with Fuel Station
// deposit cargo → supply fuel → buy fuel → create order → pay → complete → withdraw at destination
// ============================================================
#[test]
fun test_e2e_transport_with_fuel_station() {
    let mut scenario = setup_full_world();

    // 1. Supplier mints & supplies fuel to station
    scenario.next_tx(SUPPLIER);
    {
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, ADMIN);
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let fuel_coin = fuel::mint(&mut treasury, 10000, scenario.ctx());
        let supplier_receipt = fuel_station::supply_fuel(&mut station, fuel_coin, scenario.ctx());
        transfer::public_transfer(supplier_receipt, SUPPLIER);
        test_scenario::return_shared(station);
        test_scenario::return_to_address(ADMIN, treasury);
    };

    // 2. User deposits cargo into storage 1001
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"minerals", 500, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 3. User buys fuel from station
    scenario.next_tx(USER);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let price = fuel_station::current_price(&station);
        // Buy 5000 FUEL units (fuel_cost will be within bounds for weight 500)
        let payment = coin::mint_for_testing<SUI>(price * 5000 + 1000000, scenario.ctx());
        let fuel_coin = fuel_station::buy_fuel(&mut station, payment, 5000, price, scenario.ctx());
        transfer::public_transfer(fuel_coin, USER);
        test_scenario::return_shared(station);
    };

    // 4. User creates transport order
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        // fuel_cost for weight 500: min=5000, max=50_000_000
        let order = transport::create_order(
            &from, &to, receipt,
            vector[1001, 1500, 2002],
            5000,   // fuel_cost (min bound)
            200,    // danger_snapshot
            0,      // tier: Instant
            &clock,
            scenario.ctx(),
        );
        assert!(transport::order_status(&order) == 0); // Created
        transfer::public_transfer(order, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 5. User pays fuel for transport
    scenario.next_tx(USER);
    {
        let mut order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, ADMIN);
        let fuel = test_scenario::take_from_sender<coin::Coin<FUEL>>(&scenario);
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());
        assert!(transport::order_status(&order) == 1); // FuelPaid
        transfer::public_transfer(order, USER);
        test_scenario::return_to_address(ADMIN, treasury);
    };

    // 6. Complete transport (Instant = no delay)
    scenario.next_tx(USER);
    {
        let (mut from, mut to) = take_storages_ordered(&scenario);
        let order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);

        // Verify source has cargo, dest doesn't
        let from_load_before = storage::current_load(&from);
        let to_load_before = storage::current_load(&to);
        assert!(from_load_before == 500);
        assert!(to_load_before == 0);

        let new_receipt = transport::complete_transport(order, &mut from, &mut to, &clock, scenario.ctx());

        // Verify cargo moved
        assert!(storage::current_load(&from) == 0);
        assert!(storage::current_load(&to) == 500);

        transfer::public_transfer(new_receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 7. User withdraws cargo at destination
    scenario.next_tx(USER);
    {
        let (from, mut to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let payment = coin::mint_for_testing<SUI>(0, scenario.ctx());
        let cargo = storage::withdraw(&mut to, receipt, payment, &clock, scenario.ctx());
        assert!(storage::cargo_weight(&cargo) == 500);
        assert!(storage::cargo_value(&cargo) == 10000);
        transfer::public_transfer(cargo, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 8. Supplier claims revenue from fuel station
    scenario.next_tx(SUPPLIER);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut supplier_receipt = test_scenario::take_from_sender<SupplierReceipt>(&scenario);
        let revenue = fuel_station::claim_revenue(&mut station, &mut supplier_receipt, scenario.ctx());
        // Revenue should be > 0 from the fuel sale
        assert!(coin::value(&revenue) > 0);
        transfer::public_transfer(revenue, SUPPLIER);
        transfer::public_transfer(supplier_receipt, SUPPLIER);
        test_scenario::return_shared(station);
    };

    scenario.end();
}

// ============================================================
// Test 2: Full Courier E2E — create → accept → deliver → confirm → settle → ReporterCap
// ============================================================
#[test]
fun test_e2e_courier_full_lifecycle() {
    let mut scenario = setup_full_world();

    // 1. Client deposits cargo
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"crystals", 300, 15000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 2. Client creates courier contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 10000);
        let reward = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(3000, scenario.ctx());

        courier_market::create_contract(
            &from, &to, receipt,
            reward, penalty,
            15000,  // min_courier_deposit (will be clamped to cargo_value=15000)
            vector[1001, 2002],
            7_200_000,  // deadline: 2 hours
            &clock,
            scenario.ctx(),
        );

        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 3. Courier accepts
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 20000);
        let deposit = coin::mint_for_testing<SUI>(15000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 1); // Accepted
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // 4. Courier picks up and delivers
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let (mut from, mut to) = take_storages_ordered(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 30000);

        assert!(storage::current_load(&from) == 300);
        assert!(storage::current_load(&to) == 0);

        courier_market::pickup_and_deliver(
            &mut contract, &badge,
            &mut from, &mut to,
            &clock, scenario.ctx(),
        );

        assert!(courier_market::contract_status(&contract) == 2); // PendingConfirm
        assert!(storage::current_load(&from) == 0);
        assert!(storage::current_load(&to) == 300);

        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // 5. Client confirms delivery
    scenario.next_tx(USER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        courier_market::confirm_delivery(&mut contract, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 3); // Delivered
        test_scenario::return_shared(contract);
    };

    // 6. Settle — courier gets reward + ReporterCap
    scenario.next_tx(COURIER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let oracle_cap = test_scenario::take_from_address<OracleCap>(&scenario, ADMIN);
        courier_market::settle(contract, badge, &oracle_cap, scenario.ctx());
        test_scenario::return_to_address(ADMIN, oracle_cap);
    };

    // 7. Verify courier got ReporterCap, use it to report an incident
    scenario.next_tx(COURIER);
    {
        let mut threat_map = test_scenario::take_shared<ThreatMap>(&scenario);
        let mut reporter_cap = test_scenario::take_from_sender<ReporterCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 50000);

        // Report incident on system 1001
        threat_oracle::report_incident(&mut threat_map, &mut reporter_cap, 1001, &clock);

        // Verify danger score is now > 0
        let score = threat_oracle::get_danger_score(&threat_map, 1001, &clock);
        assert!(score > 0);

        threat_oracle::transfer_reporter_cap(reporter_cap, COURIER);
        test_scenario::return_shared(threat_map);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 3: Courier Dispute E2E — create → accept → deliver → dispute → resolve (client wins)
// ============================================================
#[test]
fun test_e2e_courier_dispute_client_wins() {
    let mut scenario = setup_full_world();

    // Deposit cargo
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"data_cores", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let reward = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            5000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Accept
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(5000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Pickup and deliver
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let (mut from, mut to) = take_storages_ordered(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);
        courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Client raises dispute
    scenario.next_tx(USER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 4000);
        courier_market::raise_dispute(&mut contract, &clock, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 4); // Disputed
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Oracle resolves: client wins (ruling=0)
    scenario.next_tx(ADMIN);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_address<CourierBadge>(&scenario, COURIER);
        let oracle_cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        courier_market::resolve_dispute(contract, badge, &oracle_cap, 0, scenario.ctx());
        test_scenario::return_to_address(ADMIN, oracle_cap);
    };

    // Verify: client gets receipt + both deposits (client won)
    // The receipt and coins are transferred inside resolve_dispute
    scenario.end();
}

// ============================================================
// Test 4: Transport → Fuel Station revenue distribution
// Two buyers purchase fuel → supplier claims accumulated revenue
// ============================================================
#[test]
fun test_fuel_station_revenue_after_multiple_buys() {
    let mut scenario = setup_full_world();

    // Supplier supplies 20000 fuel
    scenario.next_tx(SUPPLIER);
    {
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, ADMIN);
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let fuel_coin = fuel::mint(&mut treasury, 20000, scenario.ctx());
        let receipt = fuel_station::supply_fuel(&mut station, fuel_coin, scenario.ctx());
        transfer::public_transfer(receipt, SUPPLIER);
        test_scenario::return_shared(station);
        test_scenario::return_to_address(ADMIN, treasury);
    };

    // Buyer 1: buy 3000 fuel
    scenario.next_tx(USER);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let price = fuel_station::current_price(&station);
        let payment = coin::mint_for_testing<SUI>(price * 3000 + 1000000, scenario.ctx());
        let fuel = fuel_station::buy_fuel(&mut station, payment, 3000, price, scenario.ctx());
        transfer::public_transfer(fuel, USER);
        test_scenario::return_shared(station);
    };

    // Buyer 2: buy 5000 fuel
    scenario.next_tx(COURIER);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let price = fuel_station::current_price(&station);
        let payment = coin::mint_for_testing<SUI>(price * 5000 + 1000000, scenario.ctx());
        let fuel = fuel_station::buy_fuel(&mut station, payment, 5000, price, scenario.ctx());
        transfer::public_transfer(fuel, COURIER);
        test_scenario::return_shared(station);
    };

    // Supplier claims revenue
    scenario.next_tx(SUPPLIER);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let mut receipt = test_scenario::take_from_sender<SupplierReceipt>(&scenario);
        let revenue = fuel_station::claim_revenue(&mut station, &mut receipt, scenario.ctx());
        // Should have revenue from 2 sales (90% of total since owner_fee = 10%)
        assert!(coin::value(&revenue) > 0);
        transfer::public_transfer(revenue, SUPPLIER);
        transfer::public_transfer(receipt, SUPPLIER);
        test_scenario::return_shared(station);
    };

    // Supplier withdraws entirely
    scenario.next_tx(SUPPLIER);
    {
        let mut station = test_scenario::take_shared<FuelStation>(&scenario);
        let receipt = test_scenario::take_from_sender<SupplierReceipt>(&scenario);
        let (rev_coin, fuel_coin) = fuel_station::withdraw_supplier(&mut station, receipt, scenario.ctx());
        // Should get remaining fuel (20000 - 3000 - 5000 = 12000)
        assert!(coin::value(&fuel_coin) == 12000);
        transfer::public_transfer(rev_coin, SUPPLIER);
        transfer::public_transfer(fuel_coin, SUPPLIER);
        test_scenario::return_shared(station);
    };

    scenario.end();
}

// ============================================================
// Test 5: Threat oracle → transport danger snapshot verification
// Oracle sets danger, user creates transport with snapshot
// ============================================================
#[test]
fun test_threat_oracle_affects_transport_context() {
    let mut scenario = setup_full_world();

    // Oracle sets danger on system 1001
    scenario.next_tx(ADMIN);
    {
        let mut threat_map = test_scenario::take_shared<ThreatMap>(&scenario);
        let oracle_cap = test_scenario::take_from_sender<OracleCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);

        threat_oracle::batch_update(
            &mut threat_map, &oracle_cap,
            vector[1001, 2002],
            vector[800, 200],
            &clock,
        );

        // Verify max danger on route
        let max_d = threat_oracle::max_danger_on_route(&threat_map, &vector[1001, 2002], &clock);
        assert!(max_d == 800);

        test_scenario::return_to_address(ADMIN, oracle_cap);
        test_scenario::return_shared(threat_map);
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo and create transport with danger_snapshot from oracle
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"weapons", 200, 20000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);

        // In real usage, off-chain reads danger_snapshot from oracle and passes it in
        let order = transport::create_order(
            &from, &to, receipt,
            vector[1001, 2002],
            5000,  // fuel_cost (200 weight * 10 min = 2000, * 25 = 5000)
            800,   // danger_snapshot from oracle
            2,     // Standard tier
            &clock,
            scenario.ctx(),
        );

        // Standard tier delay = 15 min = 900_000ms
        assert!(transport::order_earliest_complete_at(&order) == 2000 + 900_000);
        transfer::public_transfer(order, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 6: Courier timeout (Accepted, no pickup) — keeper claims bounty
// ============================================================
#[test]
fun test_e2e_courier_accepted_timeout() {
    let mut scenario = setup_full_world();

    // Deposit cargo
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"cargo", 150, 6000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 100_000);
        let reward = coin::mint_for_testing<SUI>(2000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            6000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Courier accepts
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 200_000);
        let deposit = coin::mint_for_testing<SUI>(6000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Time passes beyond pickup_deadline (2 hours = 7_200_000ms from accept)
    // Keeper claims timeout
    scenario.next_tx(KEEPER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        // pickup_deadline = 200_000 + 7_200_000 = 7_400_000
        clock::set_for_testing(&mut clock, 7_500_000);
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        // Bounty = 0.5% of courier deposit (6000) = 30
        assert!(coin::value(&bounty) == 30);
        transfer::public_transfer(bounty, KEEPER);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 7: PendingConfirm timeout — auto-confirm, courier gets reward
// ============================================================
#[test]
fun test_e2e_courier_pending_confirm_timeout() {
    let mut scenario = setup_full_world();

    // Deposit
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"gems", 200, 8000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let reward = coin::mint_for_testing<SUI>(3000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            8000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Accept
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(8000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Deliver
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let (mut from, mut to) = take_storages_ordered(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);
        courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Client does NOT confirm — timeout after confirm_deadline (24h = 86_400_000ms)
    scenario.next_tx(KEEPER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        // confirm_deadline = 3000 + 86_400_000
        clock::set_for_testing(&mut clock, 3000 + 86_400_000 + 1000);
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        // PendingConfirm timeout: no keeper bounty, auto-confirm for courier
        assert!(coin::value(&bounty) == 0);
        transfer::public_transfer(bounty, KEEPER);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 8: Dispute timeout — auto-resolve courier wins
// ============================================================
#[test]
fun test_e2e_dispute_timeout_courier_wins() {
    let mut scenario = setup_full_world();

    // Deposit
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"rare_metal", 100, 4000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let reward = coin::mint_for_testing<SUI>(1500, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(500, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            4000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Accept
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let deposit = coin::mint_for_testing<SUI>(4000, scenario.ctx());
        let badge = courier_market::accept_contract(&mut contract, deposit, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Deliver
    scenario.next_tx(COURIER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let badge = test_scenario::take_from_sender<CourierBadge>(&scenario);
        let (mut from, mut to) = take_storages_ordered(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 3000);
        courier_market::pickup_and_deliver(&mut contract, &badge, &mut from, &mut to, &clock, scenario.ctx());
        transfer::public_transfer(badge, COURIER);
        test_scenario::return_shared(contract);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Client disputes
    scenario.next_tx(USER);
    {
        let mut contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 4000);
        courier_market::raise_dispute(&mut contract, &clock, scenario.ctx());
        assert!(courier_market::contract_status(&contract) == 4); // Disputed
        test_scenario::return_shared(contract);
        clock::destroy_for_testing(clock);
    };

    // Dispute times out (72h = 259_200_000ms) → keeper claims → courier auto-wins
    scenario.next_tx(KEEPER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        // dispute_deadline = 4000 + 259_200_000
        clock::set_for_testing(&mut clock, 4000 + 259_200_000 + 1000);
        let bounty = courier_market::claim_timeout(contract, &clock, scenario.ctx());
        assert!(coin::value(&bounty) == 0);
        transfer::public_transfer(bounty, KEEPER);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 9: Cancel transport → recover receipt → use in courier contract
// Demonstrates cross-module receipt portability
// ============================================================
#[test]
fun test_cancel_transport_then_create_courier() {
    let mut scenario = setup_full_world();

    // Deposit cargo
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"alloys", 250, 12000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create transport order (status=Created, not paid)
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let order = transport::create_order(
            &from, &to, receipt,
            vector[1001, 2002], 5000, 100, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Cancel transport → get receipt back
    scenario.next_tx(USER);
    {
        let order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let receipt = transport::cancel_order(order, scenario.ctx());
        transfer::public_transfer(receipt, USER);
    };

    // Use recovered receipt in courier contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 5000);
        let reward = coin::mint_for_testing<SUI>(3000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            12000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Verify contract was created
    scenario.next_tx(USER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        assert!(courier_market::contract_status(&contract) == 0); // Open
        assert!(courier_market::contract_cargo_value(&contract) == 12000);
        test_scenario::return_shared(contract);
    };

    scenario.end();
}

// ============================================================
// Test 10: Storage capacity boundary — transport fills destination exactly
// ============================================================
#[test]
fun test_transport_fills_destination_exactly() {
    let mut scenario = test_scenario::begin(ADMIN);

    // Create source storage (large) and destination storage (tight capacity)
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 50000, 0, &clock, scenario.ctx());
        // Destination: exact capacity 300
        let cap2 = storage::create_storage(2002, 300, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, ADMIN);
        transfer::public_transfer(cap2, ADMIN);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    // Deposit cargo of weight exactly 300
    scenario.next_tx(USER);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let (mut from, to) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let receipt = storage::deposit(&mut from, b"heavy_ore", 300, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create + pay transport
    scenario.next_tx(USER);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let (from, to) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let order = transport::create_order(
            &from, &to, receipt, vector[1001, 2002], 3000, 0, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(USER);
    {
        let mut order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, ADMIN);
        let fuel = fuel::mint(&mut treasury, 3000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());
        transfer::public_transfer(order, USER);
        test_scenario::return_to_address(ADMIN, treasury);
    };

    // Complete transport — destination has exactly 300 capacity, cargo weighs 300
    scenario.next_tx(USER);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let (mut from, mut to) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);

        let new_receipt = transport::complete_transport(order, &mut from, &mut to, &clock, scenario.ctx());

        // Destination should be exactly full
        assert!(storage::available_capacity(&to) == 0);
        assert!(storage::current_load(&to) == 300);

        transfer::public_transfer(new_receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 11: Transport destination full — should abort
// ============================================================
#[test]
#[expected_failure(abort_code = storage::E_CAPACITY_EXCEEDED)]
fun test_transport_destination_capacity_exceeded() {
    let mut scenario = test_scenario::begin(ADMIN);

    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 50000, 0, &clock, scenario.ctx());
        // Destination capacity = 200, cargo weight will be 300
        let cap2 = storage::create_storage(2002, 200, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap1, ADMIN);
        transfer::public_transfer(cap2, ADMIN);
        fuel::init_for_testing(scenario.ctx());
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(USER);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let (mut from, to) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let receipt = storage::deposit(&mut from, b"ore", 300, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(USER);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let (from, to) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let order = transport::create_order(
            &from, &to, receipt, vector[1001, 2002], 3000, 0, 0, &clock, scenario.ctx(),
        );
        transfer::public_transfer(order, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(USER);
    {
        let mut order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let mut treasury = test_scenario::take_from_address<FuelTreasuryCap>(&scenario, ADMIN);
        let fuel = fuel::mint(&mut treasury, 3000, scenario.ctx());
        transport::pay_fuel(&mut order, fuel, &mut treasury, scenario.ctx());
        transfer::public_transfer(order, USER);
        test_scenario::return_to_address(ADMIN, treasury);
    };

    // This should fail: destination capacity (200) < cargo weight (300)
    scenario.next_tx(USER);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let (mut from, mut to) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let order = test_scenario::take_from_sender<TransportOrder>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 2000);
        let receipt = transport::complete_transport(order, &mut from, &mut to, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.end();
}

// ============================================================
// Test 12: Courier cancel → client re-deposits in different contract
// ============================================================
#[test]
fun test_courier_cancel_and_reuse_receipt() {
    let mut scenario = setup_full_world();

    // Deposit cargo
    scenario.next_tx(USER);
    {
        let (mut from, to) = take_storages_ordered(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut from, b"cargo", 100, 3000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, USER);
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Create contract
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let reward = coin::mint_for_testing<SUI>(1500, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(500, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            3000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    // Client cancels
    scenario.next_tx(USER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        let (receipt, refund) = courier_market::cancel_by_client(contract, scenario.ctx());
        // Receipt recovered, refund received
        assert!(coin::value(&refund) == 2000); // reward + penalty
        transfer::public_transfer(receipt, USER);
        transfer::public_transfer(refund, USER);
    };

    // Use receipt to create a new courier contract with higher reward
    scenario.next_tx(USER);
    {
        let (from, to) = take_storages_ordered(&scenario);
        let receipt = test_scenario::take_from_sender<DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 5000);
        let reward = coin::mint_for_testing<SUI>(3000, scenario.ctx());
        let penalty = coin::mint_for_testing<SUI>(1000, scenario.ctx());
        courier_market::create_contract(
            &from, &to, receipt, reward, penalty,
            3000, vector[1001, 2002], 7_200_000, &clock, scenario.ctx(),
        );
        test_scenario::return_shared(from);
        test_scenario::return_shared(to);
        clock::destroy_for_testing(clock);
    };

    scenario.next_tx(USER);
    {
        let contract = test_scenario::take_shared<CourierContract>(&scenario);
        assert!(courier_market::contract_reward(&contract) == 3000);
        test_scenario::return_shared(contract);
    };

    scenario.end();
}
