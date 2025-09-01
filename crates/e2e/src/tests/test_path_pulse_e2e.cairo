use core::array::ArrayTrait;
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataDispatcher,
};
use path_interfaces::{IPathMinterDispatcher, IPathNFTDispatcher};
use pulse_adapter::interface::{
    IPulseAdapterDispatcher, IPulseAdapterSafeDispatcher, IPulseAdapterSafeDispatcherTrait,
};

// Pulse auction & adapter ABIs (imported from your git deps)
use pulse_auction::interface::{
    IPulseAuctionDispatcher, IPulseAuctionDispatcherTrait, IPulseAuctionSafeDispatcher,
    IPulseAuctionSafeDispatcherTrait,
};
use snforge_std::cheatcodes::{CheatSpan, mock_call};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, cheat_block_number, cheat_block_timestamp,
    cheat_caller_address, declare,
};
use starknet::ContractAddress;

// ---- local admin interface to your PathMinterAdapter (owner-gated) ----
// If your adapter already exposes a public admin interface crate, feel free to
// replace this with that import; otherwise, this local trait is fine as long as
// the function names & signatures match your contract.
#[starknet::interface]
trait IAdapterAdmin<T> {
    fn set_auction(ref self: T, auction: ContractAddress);
    fn set_minter(ref self: T, minter: ContractAddress);
    fn get_config(self: @T) -> (ContractAddress, ContractAddress); // (auction, minter)
}

// ---- local addresses / constants ----
fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}
fn BUYER() -> ContractAddress {
    'BUYER'.try_into().unwrap()
}
fn TREASURY() -> ContractAddress {
    'TREASURY'.try_into().unwrap()
}
fn ZERO_ADDR() -> ContractAddress {
    0.try_into().unwrap()
}
fn SELECTOR_TRANSFER_FROM() -> felt252 {
    selector!("transfer_from")
}

fn NAME() -> ByteArray {
    "PATH NFT"
}
fn SYMBOL() -> ByteArray {
    "PATH"
}
fn BASE_URI() -> ByteArray {
    ""
}

// Pulse params (choose values that avoid underflow in anchor calc: k/(gap) <= now)
const GENESIS_PRICE: u256 = 1_000_u256;
const GENESIS_FLOOR: u256 = 900_u256; // gap = 100
const K: u256 = 600_u256; // k/gap = 6, so 1000 - 6 is safe
const PTS: felt252 = 1; // price-time scale
const OPEN_DELAY_SECS: u64 = 0;

// ---- test fixture ----
#[derive(Drop)]
struct Env {
    // addresses
    nft_addr: ContractAddress,
    minter_addr: ContractAddress,
    adapter_addr: ContractAddress,
    auction_addr: ContractAddress,
    // typed dispatchers (so calls read nicely in tests)
    nft: IPathNFTDispatcher,
    erc721: IERC721Dispatcher,
    meta: IERC721MetadataDispatcher,
    minter: IPathMinterDispatcher,
    adapter: IPulseAdapterDispatcher,
    adapter_safe: IPulseAdapterSafeDispatcher,
    adapter_admin: IAdapterAdminDispatcher,
    auction: IPulseAuctionDispatcher,
    auction_safe: IPulseAuctionSafeDispatcher,
}

// Deploy PathNFT with (admin=ADMIN, minter=MINTER will be granted later via AccessControl
// if your minter is not known yet). In this flow, we pass the known minter *now*.
fn deploy_path_nft(
    admin: ContractAddress, minter: ContractAddress,
) -> (ContractAddress, IPathNFTDispatcher, IERC721Dispatcher, IERC721MetadataDispatcher) {
    let class = declare("PathNFT").unwrap().contract_class();

    let mut cd = ArrayTrait::new();
    admin.serialize(ref cd);
    minter.serialize(ref cd);
    NAME().serialize(ref cd);
    SYMBOL().serialize(ref cd);
    BASE_URI().serialize(ref cd);

    let (addr, _) = class.deploy(@cd).unwrap();

    (
        addr,
        IPathNFTDispatcher { contract_address: addr },
        IERC721Dispatcher { contract_address: addr },
        IERC721MetadataDispatcher { contract_address: addr },
    )
}

fn deploy_path_minter(
    owner: ContractAddress, nft_addr: ContractAddress,
) -> (ContractAddress, IPathMinterDispatcher) {
    // Adjust the constructor calldata to match your PathMinter ctor
    // (owner, nft_addr, …). If your minter ctor doesn’t take NFT yet,
    // you can configure it later via a setter.
    let class = declare("PathMinter").unwrap().contract_class();

    let mut cd = ArrayTrait::new();
    owner.serialize(ref cd);
    nft_addr.serialize(ref cd);

    let (addr, _) = class.deploy(@cd).unwrap();

    (addr, IPathMinterDispatcher { contract_address: addr })
}

fn deploy_adapter(
    owner: ContractAddress, auction_addr: ContractAddress, minter_addr: ContractAddress,
) -> (
    ContractAddress, IPulseAdapterDispatcher, IPulseAdapterSafeDispatcher, IAdapterAdminDispatcher,
) {
    let class = declare("PathMinterAdapter").unwrap().contract_class();

    let mut cd = ArrayTrait::new();
    owner.serialize(ref cd);
    auction_addr.serialize(ref cd); // initially ZERO; we’ll set later
    minter_addr.serialize(ref cd);

    let (addr, _) = class.deploy(@cd).unwrap();

    (
        addr,
        IPulseAdapterDispatcher { contract_address: addr },
        IPulseAdapterSafeDispatcher { contract_address: addr },
        IAdapterAdminDispatcher { contract_address: addr },
    )
}

fn deploy_pulse_auction(
    start_delay_sec: u64,
    k: u256,
    genesis_price: u256,
    genesis_floor: u256,
    pts: felt252,
    payment_token: ContractAddress,
    treasury: ContractAddress,
    adapter_addr: ContractAddress,
) -> (ContractAddress, IPulseAuctionDispatcher, IPulseAuctionSafeDispatcher) {
    let class = declare("PulseAuction").unwrap().contract_class();

    let mut cd = ArrayTrait::new();
    start_delay_sec.serialize(ref cd);
    k.serialize(ref cd);
    genesis_price.serialize(ref cd);
    genesis_floor.serialize(ref cd);
    pts.serialize(ref cd);
    payment_token.serialize(ref cd);
    treasury.serialize(ref cd);
    adapter_addr.serialize(ref cd);

    let (addr, _) = class.deploy(@cd).unwrap();

    (
        addr,
        IPulseAuctionDispatcher { contract_address: addr },
        IPulseAuctionSafeDispatcher { contract_address: addr },
    )
}

fn deploy_env() -> Env {
    // 1) Pre-deploy minter with a placeholder NFT (ZERO); we’ll wire NFT afterwards
    // If your minter must know NFT at construction time, we’ll pass a real address below instead.
    let (placeholder_nft, minter) = deploy_path_minter(ADMIN(), ZERO_ADDR());

    // 2) Deploy NFT now that we have a minter address → this grants MINTER_ROLE inside its ctor
    let (nft_addr, nft, erc721, meta) = deploy_path_nft(
        ADMIN(), placeholder_nft,
    ); // <— if your NFT grants minter here, pass `minter_addr` instead

    // If your minter needs to be told about the NFT post-deploy, do that here:
    // cheat_caller_address(minter.contract_address, ADMIN(), CheatSpan::TargetCalls(1));
    // minter.set_nft(nft_addr);  // adjust to your actual setter

    // 3) Deploy adapter (owner=ADMIN, auction = ZERO for now, minter = PathMinter)
    let (adapter_addr, adapter, adapter_safe, adapter_admin) = deploy_adapter(
        ADMIN(), ZERO_ADDR(), minter.contract_address,
    );

    // 4) Deploy auction → points at adapter
    let pay_token = 'PAYTOKEN'.try_into().unwrap(); // fake ERC-20; we’ll mock transfer_from
    let (auction_addr, auction, auction_safe) = deploy_pulse_auction(
        OPEN_DELAY_SECS, K, GENESIS_PRICE, GENESIS_FLOOR, PTS, pay_token, TREASURY(), adapter_addr,
    );

    // 5) Finish wiring: adapter.set_auction(auction_addr)
    cheat_caller_address(adapter_addr, ADMIN(), CheatSpan::TargetCalls(1));
    adapter_admin.set_auction(auction_addr);

    // 6) Optionally enforce adapter.minimally correct config
    let (a, m) = adapter_admin.get_config();
    assert(a == auction_addr, 'bad_adapter_auction');
    assert(m == minter.contract_address, 'bad_adapter_minter');

    Env {
        nft_addr,
        minter_addr: minter.contract_address,
        adapter_addr,
        auction_addr,
        nft,
        erc721,
        meta,
        minter,
        adapter,
        adapter_safe,
        adapter_admin,
        auction,
        auction_safe,
    }
}

// -------------------------------------------------------
//                       TESTS
// -------------------------------------------------------

#[test]
fn e2e_genesis_bid_mints_to_buyer_via_adapter() {
    let e = deploy_env();

    // Mock the ERC-20 transfer so auction `bid` can proceed
    // v0.48.* accepts a *typed* boolean `true` for ret_data.
    mock_call( // token
        'PAYTOKEN'.try_into().unwrap(), // selector
        SELECTOR_TRANSFER_FROM(), // return value (true) and call count
        true,
        1,
    );

    // Open the auction right away and avoid anchor underflow in calc
    cheat_block_number(e.auction_addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction_addr, 1_000_u64, CheatSpan::TargetCalls(1));

    // Buyers calls bid with a ceiling equal to the current ask (GENESIS_PRICE)
    cheat_caller_address(e.auction_addr, BUYER(), CheatSpan::TargetCalls(1));
    e.auction.bid(GENESIS_PRICE);

    // Post-conditions (minimal but end-to-end):
    // - Curve is active
    assert!(e.auction.curve_active());

    // - Buyer owns exactly one token in the collection
    //   (avoids assuming a particular token_id policy)
    assert_eq!(e.erc721.balance_of(BUYER()), 1_u256);
}

#[test]
#[feature("safe_dispatcher")]
fn e2e_adapter_gate_only_auction_can_settle() {
    let e = deploy_env();

    // Non-auction caller tries to call adapter.settle → revert with ONLY_AUCTION
    cheat_caller_address(e.adapter_addr, BUYER(), CheatSpan::TargetCalls(1));
    match e.adapter_safe.settle(BUYER(), array![].span()) {
        Result::Ok(_) => panic!("expected ONLY_AUCTION"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ONLY_AUCTION'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn e2e_same_block_second_bid_is_blocked() {
    let e = deploy_env();

    mock_call('PAYTOKEN'.try_into().unwrap(), SELECTOR_TRANSFER_FROM(), true, 2);

    // First bid in block #1 at t=1000
    cheat_block_number(e.auction_addr, 1_u64, CheatSpan::TargetCalls(1));
    cheat_block_timestamp(e.auction_addr, 1_000_u64, CheatSpan::TargetCalls(1));

    cheat_caller_address(e.auction_addr, BUYER(), CheatSpan::TargetCalls(1));
    e.auction.bid(GENESIS_PRICE);

    // Second bid in the *same* block should revert
    cheat_caller_address(e.auction_addr, BUYER(), CheatSpan::TargetCalls(1));
    match e.auction_safe.bid(GENESIS_PRICE) {
        Result::Ok(_) => panic!("ONE_BID_PER_BLOCK expected"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ONE_BID_PER_BLOCK'); },
    }
}
