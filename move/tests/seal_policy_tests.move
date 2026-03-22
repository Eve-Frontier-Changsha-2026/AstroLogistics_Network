#[test_only]
module astrologistics::seal_policy_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::storage::{Self, Storage};
use astrologistics::guild::{Self, Guild, GuildMemberCap};
use astrologistics::seal_policy;

#[test]
fun test_set_and_get_encrypted_coords() {
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
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let encrypted = b"encrypted_xyz_coords_here";
        storage::set_encrypted_coords(&mut s, &cap, encrypted);
        let result = storage::get_encrypted_coords(&s);
        assert!(result == encrypted);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
fun test_get_encrypted_coords_empty_when_unset() {
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
        let s = test_scenario::take_shared<Storage>(&scenario);
        let result = storage::get_encrypted_coords(&s);
        assert!(result == vector[]);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
fun test_encrypted_coords_overwrite() {
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
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        storage::set_encrypted_coords(&mut s, &cap, b"first");
        storage::set_encrypted_coords(&mut s, &cap, b"second");
        let result = storage::get_encrypted_coords(&s);
        assert!(result == b"second");
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
    };
    scenario.end();
}

#[test]
fun test_seal_approve_guild_member_valid() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, leader);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
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
        let s = test_scenario::take_shared<Storage>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        seal_policy::seal_approve_guild_member(&guild, &cap, &s);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_seal_approve_guild_leader_valid() {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, leader);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        // Leader is auto-enrolled, should pass
        seal_policy::seal_approve_guild_member(&guild, &leader_cap, &s);
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::seal_policy::ENotGuildMember)]
fun test_seal_approve_non_member() {
    let leader = @0xA1;
    let outsider = @0xA3;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, leader);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let mut s = test_scenario::take_shared<Storage>(&scenario);
        let cap = test_scenario::take_from_sender<storage::AdminCap>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        storage::set_storage_guild(&mut s, &cap, object::id(&guild));
        test_scenario::return_to_sender(&scenario, cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    // Outsider creates their own guild to get a GuildMemberCap
    scenario.next_tx(outsider);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"FakeGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(outsider);
    {
        let g1 = test_scenario::take_shared<Guild>(&scenario);
        let g2 = test_scenario::take_shared<Guild>(&scenario);
        let s = test_scenario::take_shared<Storage>(&scenario);
        let fake_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        // Pick the guild that the storage belongs to (leader's guild)
        let target = if (guild::guild_leader(&g1) == leader) { &g1 } else { &g2 };
        // This should fail — outsider's cap is from a different guild
        seal_policy::seal_approve_guild_member(target, &fake_cap, &s);
        test_scenario::return_to_sender(&scenario, fake_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(g1);
        test_scenario::return_shared(g2);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::seal_policy::EGuildMismatch)]
fun test_seal_approve_storage_no_guild() {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let cap = storage::create_storage(1001, 10000, 100, &clock, scenario.ctx());
        transfer::public_transfer(cap, leader);
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        // Storage has no guild set
        let s = test_scenario::take_shared<Storage>(&scenario);
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        seal_policy::seal_approve_guild_member(&guild, &leader_cap, &s);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(s);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}
