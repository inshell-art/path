use core::array::ArrayTrait;
use openzeppelin::access::accesscontrol::interface::IAccessControlDispatcherTrait;
use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use path_minter_adapter::path_minter_adapter::IAdapterAdminDispatcherTrait;
use path_test_support::prelude::*;
use pulse_adapter::interface::IPulseAdapterSafeDispatcherTrait;
use pulse_auction::interface::{IPulseAuctionDispatcherTrait, IPulseAuctionSafeDispatcherTrait};
use snforge_std::cheatcodes::{CheatSpan, mock_call};
use snforge_std::{cheat_block_number, cheat_block_timestamp, cheat_caller_address};

//
// Helper
//

#[derive(Drop)]
struct Env {
    nft: NftHandles,
    minter: MinterHandles,
    adapter: AdapterHandles,
    auction: AuctionHandles,
    erc721: IERC721Dispatcher,
}

fn wire_env(start_delay_sec: u64, k: u256, gp: u256, gf: u256, pts: felt252) -> Env {
    let nft = deploy_path_nft_default(); // admin = ADMIN, initial_minter omitted per your helper
    let erc721 = IERC721Dispatcher { contract_address: nft.addr };

    // 2) PathMinter
    let minter = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);

    // 3) Adapter (auction unknown yet → ZERO, will be set after auction deploy)
    let adapter = deploy_path_minter_adapter(ADMIN(), ZERO_ADDR(), minter.addr);

    // 4) Auction (PAYTOKEN is a sentinel; we'll mock transfer_from)
    let auction = deploy_pulse_auction_with(
        start_delay_sec, k, gp, gf, pts, PAYTOKEN(), TREASURY(), adapter.addr,
    );

    // 5) Finalize wiring
    cheat_caller_address(adapter.addr, ADMIN(), CheatSpan::TargetCalls(1));
    adapter.admin.set_auction(auction.addr);

    grant_minter_on_nft(@nft, minter.addr); // NFT → MINTER_ROLE to PathMinter
    cheat_caller_address(minter.addr, ADMIN(), CheatSpan::TargetCalls(1));
    minter.ac.grant_role(SALES_ROLE, adapter.addr); // PathMinter → SALES_ROLE to Adapter

    Env { nft, minter, adapter, auction, erc721 }
}

//
// gl_* (global / config)
//
#[test]
#[feature("safe_dispatcher")]
fn gl_config_ok_and_adapter_only_auction() {
    let e = wire_env(0, 10_000_u128.into(), 1_000_u128.into(), 800_u128.into(), 10);

    // Auction config sanity
    let (open_time, gp, gf, k, pts) = e.auction.auction.get_config();
    assert!(open_time >= 0_u64);
    assert_eq!(gp, 1_000_u128.into());
    assert_eq!(gf, 800_u128.into());
    assert_eq!(k, 10_000_u128.into());
    assert_eq!(pts, 10);

    // Adapter ONLY_AUCTION guard (negative probe)
    cheat_caller_address(e.adapter.addr, ALICE(), CheatSpan::TargetCalls(1));
    match e.adapter.adapter_safe.settle(ALICE(), array![].span()) {
        Result::Ok(_) => panic!("adapter.settle by non-auction should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ONLY_AUCTION'); },
    }
}

//
// bid_* (bidding through full chain)
//
#[test]
#[feature("safe_dispatcher")]
fn bid_before_open_time_reverts() {
    // open in future: start_delay_sec = 500
    let e = wire_env(500, 10_000_u128.into(), 1_000_u128.into(), 800_u128.into(), 10);

    cheat_caller_address(e.auction.addr, ALICE(), CheatSpan::TargetCalls(1));
    match e.auction.auction_safe.bid(1_000_u128.into()) {
        Result::Ok(_) => panic!("AUCTION_NOT_OPEN expected"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'AUCTION_NOT_OPEN'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn bid_genesis_mints_to_path_nft() {
    let e = wire_env(0, 10_000_u128.into(), 1_000_u128.into(), 800_u128.into(), 10);
    let receiver = deploy_receiver();

    // Mock ERC-20 transfer_from(buyer→treasury, ask) to return true once
    let selector_transfer_from = selector!("transfer_from");
    mock_call(PAYTOKEN(), selector_transfer_from, array![1].span(), 1);

    // Deterministic boot: avoid u64_sub underflow in anchor calc and set block guard baseline
    cheat_block_number(e.auction.addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction.addr, 1_000_u64, CheatSpan::TargetCalls(1));

    // Genesis bid
    cheat_caller_address(e.auction.addr, receiver, CheatSpan::TargetCalls(1));
    e.auction.auction.bid(1_000_u128.into());

    assert!(e.auction.auction.curve_active());
    assert_eq!(e.erc721.owner_of(FIRST_PUBLIC_ID), receiver);

    // Same block → one-bid-per-block guard
    cheat_block_number(e.auction.addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction.addr, 1_000_u64, CheatSpan::TargetCalls(1));
    cheat_caller_address(e.auction.addr, receiver, CheatSpan::TargetCalls(1));
    match e.auction.auction_safe.bid(1_000_u128.into()) {
        Result::Ok(_) => panic!("second bid in same block should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ONE_BID_PER_BLOCK'); },
    }
}

#[test]
fn bid_next_block_succeeds_and_id_increments() {
    let e = wire_env(0, 10_000_u128.into(), 1_000_u128.into(), 800_u128.into(), 10);
    let receiver = deploy_receiver();

    // Mock two payments (genesis + next)
    let selector_transfer_from = selector!("transfer_from");
    mock_call(PAYTOKEN(), selector_transfer_from, array![1].span(), 2);

    // Genesis @ block 1, t=1000
    cheat_block_number(e.auction.addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction.addr, 1_000_u64, CheatSpan::TargetCalls(1));
    cheat_caller_address(e.auction.addr, receiver, CheatSpan::TargetCalls(1));
    e.auction.auction.bid(1_000_u128.into());
    assert!(e.auction.auction.curve_active());
    assert_eq!(e.erc721.owner_of(FIRST_PUBLIC_ID), receiver);

    // Next bid @ block 2, later timestamp
    cheat_block_number(e.auction.addr, 2_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction.addr, 1_010_u64, CheatSpan::TargetCalls(1));
    cheat_caller_address(e.auction.addr, receiver, CheatSpan::TargetCalls(1));
    e.auction.auction.bid(10_000_u128.into()); // generous ceiling

    assert_eq!(e.erc721.owner_of(FIRST_PUBLIC_ID + 1_u128.into()), receiver);
}

#[test]
fn bid_price_decays_over_time_after_genesis() {
    let e = wire_env(0, 10_000_u128.into(), 1_000_u128.into(), 800_u128.into(), 10);
    let receiver = deploy_receiver();

    // One mocked payment for genesis
    let selector_transfer_from = selector!("transfer_from");
    mock_call(PAYTOKEN(), selector_transfer_from, array![1].span(), 1);

    // Activate curve
    cheat_block_number(e.auction.addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction.addr, 1_000_u64, CheatSpan::TargetCalls(1));
    cheat_caller_address(e.auction.addr, receiver, CheatSpan::TargetCalls(1));
    e.auction.auction.bid(1_000_u128.into());

    // Sample prices at later times: k/(now-a)+b decreases with now
    cheat_block_timestamp(e.auction.addr, 1_050_u64, CheatSpan::TargetCalls(1));
    let p1 = e.auction.auction.get_current_price();

    cheat_block_timestamp(e.auction.addr, 1_500_u64, CheatSpan::TargetCalls(1));
    let p2 = e.auction.auction.get_current_price();

    assert!(p2 < p1);
}

//
// adp_* (adapter)
//
#[test]
#[feature("safe_dispatcher")]
fn adp_only_auction_can_settle() {
    let e = wire_env(0, 10_000_u128.into(), 1_000_u128.into(), 800_u128.into(), 10);
    // Direct call from non-auction should revert
    cheat_caller_address(e.adapter.addr, ALICE(), CheatSpan::TargetCalls(1));
    match e.adapter.adapter_safe.settle(ALICE(), array![].span()) {
        Result::Ok(_) => panic!("adapter.settle by non-auction should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ONLY_AUCTION'); },
    }
}
