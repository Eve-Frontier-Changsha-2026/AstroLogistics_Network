#[test_only]
module astrologistics::guild_monkey_tests;

use sui::test_scenario;
use sui::clock;
use astrologistics::guild::{Self, Guild, GuildMemberCap};

// ---- Helpers ----

fun setup_guild(): test_scenario::Scenario {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"TestGuild".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario
}

fun setup_guild_with_member(): test_scenario::Scenario {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario
}

// ---- Monkey Tests ----

#[test]
#[expected_failure(abort_code = astrologistics::guild::EAlreadyMember)]
fun test_double_add_member() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = setup_guild_with_member();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ENotLeader)]
fun test_non_leader_adds_member() {
    let member = @0xA2;
    let outsider = @0xA3;
    let mut scenario = setup_guild_with_member();
    scenario.next_tx(member);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let member_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &member_cap, outsider, scenario.ctx());
        test_scenario::return_to_sender(&scenario, member_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ENotMember)]
fun test_remove_non_member() {
    let leader = @0xA1;
    let outsider = @0xA3;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, outsider);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ELeaderCannotLeave)]
fun test_leader_cannot_leave() {
    let leader = @0xA1;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::leave_guild(&mut guild, cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ELeaderCannotLeave)]
fun test_leader_cannot_remove_self() {
    let leader = @0xA1;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, leader);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_stale_cap_after_removal() {
    let leader = @0xA1;
    let member = @0xA2;
    let mut scenario = setup_guild_with_member();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &leader_cap, member);
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.next_tx(member);
    {
        let guild = test_scenario::take_shared<Guild>(&scenario);
        let cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        assert!(!guild::verify_membership(&guild, &cap));
        guild::destroy_stale_cap(cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ECapGuildMismatch)]
fun test_wrong_guild_cap() {
    let leader1 = @0xA1;
    let leader2 = @0xA2;
    let outsider = @0xA3;
    let mut scenario = test_scenario::begin(leader1);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"Guild1".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader2);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"Guild2".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    // leader1 tries to add a member to leader2's guild using leader1's cap
    scenario.next_tx(leader1);
    {
        let g1 = test_scenario::take_shared<Guild>(&scenario);
        let g2 = test_scenario::take_shared<Guild>(&scenario);
        let cap1 = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        // cap1 belongs to whichever guild leader1 created; try to use it on the other guild
        let (mut target, other) = if (guild::guild_leader(&g1) == leader2) {
            (g1, g2)
        } else {
            (g2, g1)
        };
        guild::add_member(&mut target, &cap1, outsider, scenario.ctx());
        test_scenario::return_to_sender(&scenario, cap1);
        test_scenario::return_shared(target);
        test_scenario::return_shared(other);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::EGuildFull)]
fun test_guild_full() {
    let leader = @0xA1;
    let mut scenario = setup_guild();
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        // Fill guild to capacity (leader counts as 1, fill remaining 99 slots)
        guild::test_fill_guild_to_capacity(&mut guild, &leader_cap, scenario.ctx());
        // Now try to add one more — should fail with EGuildFull
        let overflow_addr = @0xDEAD;
        guild::add_member(&mut guild, &leader_cap, overflow_addr, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ENameTooLong)]
fun test_guild_name_too_long() {
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        // 200 bytes — well over the 128 byte limit
        let long_name = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".to_string();
        guild::create_guild(long_name, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.end();
}

#[test]
#[expected_failure(abort_code = astrologistics::guild::ENotLeader)]
fun test_non_leader_removes_member() {
    let leader = @0xA1;
    let member = @0xA2;
    let member2 = @0xA3;
    let mut scenario = setup_guild_with_member();
    // Add member2
    scenario.next_tx(leader);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let leader_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::add_member(&mut guild, &leader_cap, member2, scenario.ctx());
        test_scenario::return_to_sender(&scenario, leader_cap);
        test_scenario::return_shared(guild);
    };
    // member tries to remove member2 — not leader
    scenario.next_tx(member);
    {
        let mut guild = test_scenario::take_shared<Guild>(&scenario);
        let member_cap = test_scenario::take_from_sender<GuildMemberCap>(&scenario);
        guild::remove_member(&mut guild, &member_cap, member2);
        test_scenario::return_to_sender(&scenario, member_cap);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_empty_guild_name() {
    // Empty name should be allowed (length 0 <= 128)
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        guild::create_guild(b"".to_string(), &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let guild = test_scenario::take_shared<Guild>(&scenario);
        assert!(guild::guild_member_count(&guild) == 1);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}

#[test]
fun test_exact_max_name_length() {
    // Exactly 128 bytes — should succeed
    let leader = @0xA1;
    let mut scenario = test_scenario::begin(leader);
    {
        let clock = clock::create_for_testing(scenario.ctx());
        let name_128 = b"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".to_string();
        guild::create_guild(name_128, &clock, scenario.ctx());
        clock::destroy_for_testing(clock);
    };
    scenario.next_tx(leader);
    {
        let guild = test_scenario::take_shared<Guild>(&scenario);
        assert!(guild::guild_member_count(&guild) == 1);
        test_scenario::return_shared(guild);
    };
    scenario.end();
}
