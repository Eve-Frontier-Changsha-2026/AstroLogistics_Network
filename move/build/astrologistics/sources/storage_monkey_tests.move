#[test_only]
module astrologistics::storage_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, AdminCap};
use astrologistics::guild::{Self, Guild, GuildMemberCap};

/// Deposit exactly at max capacity
#[test]
fun test_deposit_exact_capacity() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 100, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 1000, &clock, scenario.ctx());
        assert!(storage::available_capacity(&s) == 0);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Zero weight cargo — should fail (Fix H-5)
#[test]
#[expected_failure(abort_code = storage::E_ZERO_WEIGHT)]
fun test_deposit_zero_weight() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 100, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"intel", 0, 500, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Zero value cargo — should fail (Fix H-5)
#[test]
#[expected_failure(abort_code = storage::E_ZERO_VALUE)]
fun test_deposit_zero_value_fails() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 100, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"junk", 10, 0, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Multiple deposits then out-of-order withdrawals
#[test]
fun test_multiple_deposit_withdraw_out_of_order() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 1000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    let r1;
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        r1 = storage::deposit(&mut s, b"a", 100, 100, &clock, scenario.ctx());
        let r2 = storage::deposit(&mut s, b"b", 200, 200, &clock, scenario.ctx());
        let r3 = storage::deposit(&mut s, b"c", 300, 300, &clock, scenario.ctx());
        assert!(storage::current_load(&s) == 600);
        transfer::public_transfer(r2, user);
        transfer::public_transfer(r3, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Withdraw first item (r1)
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(0, scenario.ctx());
        let cargo = storage::withdraw(&mut s, r1, payment, &clock, scenario.ctx());
        assert!(storage::current_load(&s) == 500);
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// admin_reclaim with live receipt should fail
#[test]
#[expected_failure(abort_code = storage::E_RECEIPT_STILL_LIVE)]
fun test_admin_reclaim_receipt_still_live() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 1000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    let cargo_id;
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        cargo_id = storage::receipt_cargo_id(&receipt);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Try reclaim with live receipt — should fail
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 31 * 86_400_000);
        storage::admin_reclaim(&mut s, &cap, cargo_id, &clock, scenario.ctx());
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// admin_reclaim before grace period (receipt cleared) should fail
#[test]
#[expected_failure(abort_code = storage::E_GRACE_PERIOD_NOT_MET)]
fun test_admin_reclaim_too_early() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 1000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    let cargo_id;
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        cargo_id = storage::receipt_cargo_id(&receipt);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Clear live_receipt first
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        storage::clear_live_receipt_for_testing(&mut s, cargo_id);
        test_scenario::return_shared(s);
    };
    // Try reclaim after only 1 day — should fail (need 30)
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_400_000);
        storage::admin_reclaim(&mut s, &cap, cargo_id, &clock, scenario.ctx());
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// withdraw_with_auth — mismatched receipt_id should fail
#[test]
#[expected_failure(abort_code = storage::E_AUTH_MISMATCH)]
fun test_withdraw_auth_mismatch() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        // Create auth with WRONG receipt_id
        let auth = storage::create_withdraw_auth(
            object::id_from_address(@0xBAD),
            object::id_from_address(@0xCC),
        );
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(0, scenario.ctx());
        let cargo = storage::withdraw_with_auth(&mut s, receipt, auth, payment, &clock, scenario.ctx());
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Fee rate too high on create should fail
#[test]
#[expected_failure(abort_code = storage::E_FEE_TOO_HIGH)]
fun test_create_storage_fee_too_high() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        // 6000 > max_owner_fee_bps (5000)
        let cap = storage::create_storage(1001, 10000, 6000, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

/// Fee rate too high on update should fail
#[test]
#[expected_failure(abort_code = storage::E_FEE_TOO_HIGH)]
fun test_update_fee_rate_too_high() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        storage::update_fee_rate(&mut s, &cap, 6000); // > 5000
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

/// Verify fee amount numerically
#[test]
fun test_fee_calculation_correct() {
    let admin = @0xAD;
    let user = @0x01;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        // 1% daily = 100 bps
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 10000, &clock, scenario.ctx());
        // Check fee after 3 days: 10000 * 100 * 3 / 10000 = 300
        let cargo_id = storage::receipt_cargo_id(&receipt);
        let mut clock2 = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock2, 3 * 86_400_000);
        let fee = storage::calculate_fee(&s, cargo_id, &clock2);
        assert!(fee == 300);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
        clock::destroy_for_testing(clock2);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::storage::E_CAP_MISMATCH)]
fun test_set_guild_wrong_cap() {
    let admin1 = @0xA1;
    let admin2 = @0xA2;
    let mut scenario = test_scenario::begin(admin1);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap1 = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap1, admin1);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin2);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap2 = storage::create_storage(2002, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap2, admin2);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin2);
    {
        let s1 = test_scenario::take_shared<Storage>(&scenario);
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let cap2 = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let (mut target, other) = if (storage::system_id(&s1) == 1001) { (s1, s2) } else { (s2, s1) };
        let fake_guild_id = object::id_from_address(@0xDEAD);
        storage::set_storage_guild(&mut target, &cap2, fake_guild_id);
        test_scenario::return_to_sender(&scenario, cap2);
        test_scenario::return_shared(target);
        test_scenario::return_shared(other);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::storage::E_NOT_GUILD_MEMBER)]
fun test_withdraw_guild_non_member() {
    let admin = @0xAD;
    let outsider = @0xA3;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 500, &clock, scenario.ctx());
        transfer::public_transfer(cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(outsider);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"FakeGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(outsider);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 5000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, outsider);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(outsider);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let g1 = test_scenario::take_shared<Guild>(&scenario);
        let g2 = test_scenario::take_shared<Guild>(&scenario);
        let fake_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(500, scenario.ctx());
        let target_guild = if (guild::guild_leader(&g1) == admin) { &g1 } else { &g2 };
        let cargo = storage::withdraw_as_guild_member(
            &mut s, receipt, payment, target_guild, &fake_cap, &clock, scenario.ctx()
        );
        transfer::public_transfer(cargo, outsider);
        test_scenario::return_to_sender(&scenario, fake_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(g1);
        test_scenario::return_shared(g2);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
