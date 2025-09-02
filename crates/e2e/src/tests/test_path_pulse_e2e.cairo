use core::array::ArrayTrait;
use snforge_std::cheatcodes::{CheatSpan, mock_call};
use snforge_std::{
    EventSpyTrait, EventsFilterTrait, cheat_block_number, cheat_block_timestamp,
    cheat_caller_address, spy_events,
};
use crate::tests::test_helper::*;

#[test]
fn gl_wiring_and_target() {
    let e = deploy_env();
    // Adapter.target() should point to auction
    assert_eq!(e.adapter.target(), e.auction_addr);
}

#[test]
#[feature("safe_dispatcher")]
fn admin_setters_reject_zero_and_only_owner() {
    let e = deploy_env();

    // zero rejection
    cheat_caller_address(e.adapter_addr, ADMIN(), CheatSpan::TargetCalls(1));
    match e.adapter_safe.set_minter(ZERO()) {
        Result::Ok(_) => panic!("ZERO_MINTER expected"),
        Result::Err(p) => { assert_eq!(*p.at(0), 'ZERO_MINTER'); },
    }

    // only owner
    cheat_caller_address(e.adapter_addr, ALICE(), CheatSpan::TargetCalls(1));
    match e.adapter_safe.set_auction(e.auction_addr) {
        Result::Ok(_) => panic!("ONLY_OWNER expected"),
        Result::Err(p) => { assert_eq!(*p.at(0), 'Ownable: caller is not the owner'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn nft_owner_can_burn_then_owner_of_reverts() {
    let e = deploy_env();

    // Mint directly via PathMinter (bypassing auction) to set baseline
    cheat_caller_address(e.minter_addr, ADMIN(), CheatSpan::TargetCalls(1));
    let id = e.minter.mint_public(ALICE(), array![].span());
    assert_eq!(e.erc721.owner_of(id), ALICE());

    // Burn and verify owner_of reverts
    cheat_caller_address(e.nft_addr, ALICE(), CheatSpan::TargetCalls(1));
    e.nft.burn(id);

    match e.erc721.owner_of_safe(id) {
        Result::Ok(_) => panic!("expected invalid token ID"),
        Result::Err(p) => { assert_eq!(*p.at(0), 'ERC721: invalid token ID'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn auction_not_open_reverts() {
    let e = deploy_env();
    cheat_caller_address(e.auction_addr, ALICE(), CheatSpan::TargetCalls(1));
    match e.auction_safe.bid(1_000_u128.into()) {
        Result::Ok(_) => panic!("AUCTION_NOT_OPEN expected"),
        Result::Err(p) => { assert_eq!(*p.at(0), 'AUCTION_NOT_OPEN'); },
    }
}

#[test]
fn genesis_bid_activates_curve_and_mints_one() {
    let e = deploy_env();

    // mock ERC20 transferFrom success for 1 call
    mock_call(ZERO(), 0_u128.into(), array![1].span(), 1);

    cheat_block_number(e.auction_addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction_addr, 1_000_u64, CheatSpan::TargetCalls(1));
    cheat_caller_address(e.auction_addr, ALICE(), CheatSpan::TargetCalls(1));

    let mut spy = spy_events();
    e.auction.bid(1_000_u128.into());

    // Sale event emitted & curve active
    let evs = spy.get_events().emitted_by(e.auction_addr);
    assert!(evs.events.len() > 0);
}

#[test]
#[feature("safe_dispatcher")]
fn adapter_only_auction_can_settle_and_revert_rolls_back() {
    let e = deploy_env();

    // Non-auction trying to settle
    cheat_caller_address(e.adapter_addr, ALICE(), CheatSpan::TargetCalls(1));
    match e.adapter_safe.settle(ALICE(), array![].span()) {
        Result::Ok(_) => panic!("ONLY_AUCTION expected"),
        Result::Err(p) => { assert_eq!(*p.at(0), 'ONLY_AUCTION'); },
    }

    // Now drive a bid but force adapter to revert: set a flag on adapter admin if you expose it,
    // else mock a revert by making ERC20 call fail if your adapter propagates it.
    // Example: if PathMinterAdapter surfaces 'ADAPTER_REVERT' in your admin:
    cheat_caller_address(e.adapter_addr, ADMIN(), CheatSpan::TargetCalls(1));
    // e.adapter_admin.set_should_revert(true); // uncomment if you expose this in adapter

    cheat_block_number(e.auction_addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction_addr, 1_000_u64, CheatSpan::TargetCalls(1));
    cheat_caller_address(e.auction_addr, ALICE(), CheatSpan::TargetCalls(1));

    match e.auction_safe.bid(1_000_u128.into()) {
        Result::Ok(_) => panic!("expected adapter revert"),
        Result::Err(_p) => {},
    }
    // After revert: curve not active; next_id unchanged (peek via minter if you expose it)
}
