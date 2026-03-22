module astrologistics::guild;

use sui::table::{Self, Table};
use sui::clock::Clock;
use sui::event;
use astrologistics::constants;

// ============ Error codes ============
const ENotLeader: u64 = 0;
const EAlreadyMember: u64 = 1;
const ENotMember: u64 = 2;
const EGuildFull: u64 = 3;
const ELeaderCannotLeave: u64 = 4;
const ECapGuildMismatch: u64 = 5;
const ENameTooLong: u64 = 6;

// ============ Structs ============

public struct Guild has key {
    id: UID,
    name: std::string::String,
    leader: address,
    members: Table<address, bool>,
    member_count: u64,
    created_at: u64,
}

/// Non-transferable guild membership token.
/// Validity is checked against Guild.members table (can become stale if removed).
public struct GuildMemberCap has key {
    id: UID,
    guild_id: ID,
    member: address,
}

// ============ Events ============

public struct GuildCreated has copy, drop {
    guild_id: ID,
    leader: address,
    name: std::string::String,
}

public struct MemberAdded has copy, drop {
    guild_id: ID,
    member: address,
}

public struct MemberRemoved has copy, drop {
    guild_id: ID,
    member: address,
}

public struct MemberLeft has copy, drop {
    guild_id: ID,
    member: address,
}

// ============ Public functions ============

/// Create a new guild. Caller becomes leader and auto-enrolled member.
public fun create_guild(
    name: std::string::String,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(name.length() <= constants::max_guild_name_length(), ENameTooLong);

    let leader = ctx.sender();
    let mut members = table::new<address, bool>(ctx);
    members.add(leader, true);

    let guild = Guild {
        id: object::new(ctx),
        name,
        leader,
        members,
        member_count: 1,
        created_at: clock.timestamp_ms(),
    };

    let guild_id = object::id(&guild);

    let leader_cap = GuildMemberCap {
        id: object::new(ctx),
        guild_id,
        member: leader,
    };

    event::emit(GuildCreated { guild_id, leader, name: guild.name });

    transfer::share_object(guild);
    transfer::transfer(leader_cap, leader);
}

/// Leader adds a member. GuildMemberCap transferred to member internally.
public fun add_member(
    guild: &mut Guild,
    leader_cap: &GuildMemberCap,
    member_addr: address,
    ctx: &mut TxContext,
) {
    assert!(leader_cap.guild_id == object::id(guild), ECapGuildMismatch);
    assert!(leader_cap.member == guild.leader, ENotLeader);
    assert!(!guild.members.contains(member_addr), EAlreadyMember);
    assert!(guild.member_count < constants::max_guild_members(), EGuildFull);

    guild.members.add(member_addr, true);
    guild.member_count = guild.member_count + 1;

    let cap = GuildMemberCap {
        id: object::new(ctx),
        guild_id: object::id(guild),
        member: member_addr,
    };

    event::emit(MemberAdded { guild_id: object::id(guild), member: member_addr });
    transfer::transfer(cap, member_addr);
}

/// Leader removes a member from the guild table.
public fun remove_member(
    guild: &mut Guild,
    leader_cap: &GuildMemberCap,
    member_addr: address,
) {
    assert!(leader_cap.guild_id == object::id(guild), ECapGuildMismatch);
    assert!(leader_cap.member == guild.leader, ENotLeader);
    assert!(guild.members.contains(member_addr), ENotMember);
    assert!(member_addr != guild.leader, ELeaderCannotLeave);

    guild.members.remove(member_addr);
    guild.member_count = guild.member_count - 1;

    event::emit(MemberRemoved { guild_id: object::id(guild), member: member_addr });
}

/// Member voluntarily leaves the guild and destroys their cap.
public fun leave_guild(
    guild: &mut Guild,
    cap: GuildMemberCap,
) {
    let GuildMemberCap { id, guild_id, member } = cap;
    assert!(guild_id == object::id(guild), ECapGuildMismatch);
    assert!(member != guild.leader, ELeaderCannotLeave);

    if (guild.members.contains(member)) {
        guild.members.remove(member);
        guild.member_count = guild.member_count - 1;
    };

    event::emit(MemberLeft { guild_id: object::id(guild), member });
    id.delete();
}

/// Destroy a stale cap (member was removed by leader, cap is no longer valid).
public fun destroy_stale_cap(cap: GuildMemberCap) {
    let GuildMemberCap { id, .. } = cap;
    id.delete();
}

/// Check if a cap holder is currently a valid member of the guild.
public fun verify_membership(guild: &Guild, cap: &GuildMemberCap): bool {
    cap.guild_id == object::id(guild) &&
    guild.members.contains(cap.member)
}

// ============ Getters ============

public fun guild_leader(guild: &Guild): address { guild.leader }
public fun guild_member_count(guild: &Guild): u64 { guild.member_count }
public fun guild_name(guild: &Guild): &std::string::String { &guild.name }
public fun member_cap_guild_id(cap: &GuildMemberCap): ID { cap.guild_id }
public fun member_cap_member(cap: &GuildMemberCap): address { cap.member }
public fun is_member(guild: &Guild, addr: address): bool {
    guild.members.contains(addr)
}

// ============ Test-only helpers ============

#[test_only]
/// Set max members to a smaller value for testing guild-full scenarios.
public fun test_fill_guild_to_capacity(
    guild: &mut Guild,
    leader_cap: &GuildMemberCap,
    ctx: &mut TxContext,
) {
    assert!(leader_cap.guild_id == object::id(guild), ECapGuildMismatch);
    assert!(leader_cap.member == guild.leader, ENotLeader);

    let max = constants::max_guild_members();
    let mut i = guild.member_count;
    while (i < max) {
        let addr = sui::address::from_u256((0x2000u256 + (i as u256)));
        guild.members.add(addr, true);
        guild.member_count = guild.member_count + 1;
        // Note: we don't create caps for these fake members (test only)
        i = i + 1;
    };
    // Suppress unused ctx warning
    let _ = ctx;
}
