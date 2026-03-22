#[test_only]
module astrologistics::storage_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage, AdminCap};
use astrologistics::guild::{Self, Guild, GuildMemberCap};

#[test]
fun test_create_storage() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        assert!(test_scenario::has_most_recent_for_sender<AdminCap>(&scenario));
        let storage = test_scenario::take_shared<Storage>(&scenario);
        assert!(storage::system_id(&storage) == 1001);
        assert!(storage::available_capacity(&storage) == 10000);
        assert!(storage::fee_rate(&storage) == 100);
        test_scenario::return_shared(storage);
    };
    scenario.end();
}

#[test]
fun test_deposit_and_withdraw() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let receipt = storage::deposit(&mut s, b"ore", 500, 10000, &clock, scenario.ctx());
        assert!(storage::available_capacity(&s) == 9500);
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Withdraw ~1 day later — fee = 10000 * 100 / 10000 * 1 = 100
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(200, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());
        assert!(storage::available_capacity(&s) == 10000);
        assert!(storage::cargo_weight(&cargo) == 500);
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_withdraw_zero_fee() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
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
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(0, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_CAPACITY_EXCEEDED)]
fun test_deposit_exceeds_capacity() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 100, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 200, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_INSUFFICIENT_FEE)]
fun test_withdraw_insufficient_fee() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt = storage::deposit(&mut s, b"ore", 100, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(user);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_400_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(10, scenario.ctx());
        let cargo = storage::withdraw(&mut s, receipt, payment, &clock, scenario.ctx());
        transfer::public_transfer(cargo, user);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_withdraw_with_auth() {
    let user = @0x01;
    let courier = @0xC1;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
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
    scenario.next_tx(courier);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_address<storage::DepositReceipt>(&scenario, user);
        let clock = clock::create_for_testing(scenario.ctx());
        let receipt_id = object::id(&receipt);
        let auth = storage::create_withdraw_auth(receipt_id, object::id_from_address(@0xCC));
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(0, scenario.ctx());
        let cargo = storage::withdraw_with_auth(&mut s, receipt, auth, payment, &clock, scenario.ctx());
        assert!(storage::cargo_weight(&cargo) == 100);
        transfer::public_transfer(cargo, courier);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_admin_reclaim_after_grace_period() {
    let user = @0x01;
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 0, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
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
    // Clear live_receipt (simulate receipt consumed)
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        storage::clear_live_receipt_for_testing(&mut s, cargo_id);
        test_scenario::return_shared(s);
    };
    // Admin reclaims after 31 days
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 31 * 86_400_000);
        assert!(storage::current_load(&s) == 100);
        storage::admin_reclaim(&mut s, &cap, cargo_id, &clock, scenario.ctx());
        assert!(storage::current_load(&s) == 0);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
fun test_update_fee_rate() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<AdminCap>(&scenario);
        storage::update_fee_rate(&mut s, &cap, 200);
        assert!(storage::fee_rate(&s) == 200);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = storage::E_CAP_MISMATCH)]
fun test_update_fee_rate_wrong_cap() {
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
        let cap2 = storage::create_storage(1002, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap2, admin2);
        clock::destroy_for_testing(clock);
    };
    // admin2 tries to use cap2 on storage1 (take both, return storage2, keep storage1)
    scenario.next_tx(admin2);
    {
        let s2 = test_scenario::take_shared<Storage>(&scenario);
        let mut s1 = test_scenario::take_shared<Storage>(&scenario);
        let cap2 = test_scenario::take_from_sender<AdminCap>(&scenario);
        // cap2 is for s2, but we call on s1 → should fail
        storage::update_fee_rate(&mut s1, &cap2, 999);
        test_scenario::return_to_sender(&scenario, cap2);
        test_scenario::return_shared(s1);
        test_scenario::return_shared(s2);
    };
    scenario.end();
}

#[test]
fun test_set_storage_guild() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let guild_id = object::id(&guild);
        storage::set_storage_guild(&mut s, &cap, guild_id);
        let guild_opt = storage::storage_guild_id(&s);
        assert!(option::is_some(&guild_opt));
        assert!(*option::borrow(&guild_opt) == guild_id);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_remove_storage_guild() {
    let admin = @0xAD;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(admin_cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        storage::remove_storage_guild(&mut s, &cap);
        assert!(option::is_none(&storage::storage_guild_id(&s)));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_withdraw_as_guild_member() {
    let admin = @0xAD;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(admin);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let admin_cap = storage::create_storage(1001, 10000, 500, &clock, scenario.ctx()); // 5% fee
        transfer::public_transfer(admin_cap, admin);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(admin);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(member);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 1000);
        let receipt = storage::deposit(&mut s, b"ore", 500, 10000, &clock, scenario.ctx());
        transfer::public_transfer(receipt, member);
        test_scenario::return_shared(s);
        clock::destroy_for_testing(clock);
    };
    // Member withdraws with guild discount (1 day later)
    // Normal fee: 10000 * 500 / 10000 * 1 = 500
    // Guild discount: 500 * (10000 - 3000) / 10000 = 350
    scenario.next_tx(member);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let receipt = test_scenario::take_from_sender<storage::DepositReceipt>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let guild_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        let mut clock = clock::create_for_testing(scenario.ctx());
        clock::set_for_testing(&mut clock, 86_401_000);
        let payment = sui::coin::mint_for_testing<sui::sui::SUI>(500, scenario.ctx());
        let cargo = storage::withdraw_as_guild_member(
            &mut s, receipt, payment, &guild, &guild_cap, &clock, scenario.ctx()
        );
        transfer::public_transfer(cargo, member);
        test_scenario::return_to_sender(&scenario, guild_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}
