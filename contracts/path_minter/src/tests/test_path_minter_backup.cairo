//! Integration tests for PathMinter
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use path_interfaces::{IPathMinterDispatcher, IPathMinterDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, mock_call, start_cheat_caller_address,
    stop_cheat_caller_address, test_address,
};
use starknet::ContractAddress;

// re compute `SALES_ROLE` and `RESERVED_ROLE` selectors, and MAX_MINUS_ONE
const SALES_ROLE: felt252 = selector!("SALES_ROLE");
const RESERVED_ROLE: felt252 = selector!("RESERVED_ROLE");
pub const MAX_MINUS_ONE: u256 = u256 {
    low: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE, high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
};

pub fn deploy_fixture(
    reserved_cap: u64,
) -> (IPathMinterDispatcher, ContractAddress, ContractAddress, ContractAddress, ContractAddress) {
    let nft_owner: ContractAddress = 1.try_into().unwrap();
    let minter_admin: ContractAddress = 2.try_into().unwrap();
    let minter_sales: ContractAddress = 3.try_into().unwrap();
    let minter_reserved: ContractAddress = 4.try_into().unwrap();
    let first_id_low = 0;
    let first_id_high = 0;

    // Deploy PathNFT and PathMinter contracts, and set up roles
    let nft_class = declare("PathNFT").unwrap().contract_class();
    let (nft_addr, _) = nft_class.deploy(@array![nft_owner.into()]).unwrap();

    let class = declare("PathMinter").unwrap().contract_class();
    let (minter_addr, _) = class
        .deploy(
            @array![
                minter_admin.into(), nft_addr.into(), first_id_low.into(), first_id_high.into(),
                reserved_cap.into(),
            ],
        )
        .unwrap();
    let minter_iface = IPathMinterDispatcher { contract_address: minter_addr };
    let minter_access_iface = IAccessControlDispatcher { contract_address: minter_addr };
    let nft_ownable_iface = IOwnableDispatcher { contract_address: nft_addr };

    // transfer ownership of the NFT contract to minter_addr
    start_cheat_caller_address(nft_addr, nft_owner);
    nft_ownable_iface.transfer_ownership(minter_addr);
    stop_cheat_caller_address(nft_addr);

    // Grant roles in minter contract as administrator
    start_cheat_caller_address(minter_addr, minter_admin);
    minter_access_iface.grant_role(SALES_ROLE, minter_sales);
    minter_access_iface.grant_role(RESERVED_ROLE, minter_reserved);
    stop_cheat_caller_address(minter_addr);

    return (minter_iface, minter_admin, minter_sales, minter_reserved, nft_addr);
}


#[test]
fn constructor_sets_caps() {
    let (minter, _, _, _, _) = deploy_fixture(10);
    let stranger = test_address(); // helper macro

    start_cheat_caller_address(minter.contract_address, stranger);
    assert_eq!(minter.get_reserved_cap(), 10_u64);
    assert_eq!(minter.get_reserved_remaining(), 10_u64);
    stop_cheat_caller_address(minter.contract_address); // reset caller
}

#[test]
fn sales_role_can_mint_public() {
    let (minter, _, sales, _, nft_addr) = deploy_fixture(10);
    start_cheat_caller_address(minter.contract_address, sales);
    mock_call(nft_addr, selector!("safe_mint"), (), 2); // mock PathNFT’s safe_mint twice

    let id0 = minter.mint_public(sales, array![].span());
    let id1 = minter.mint_public(sales, array![].span());
    assert_eq!(id0, 0_u256);
    assert_eq!(id1, 1_u256);
    assert_eq!(minter.get_reserved_remaining(), 10_u64); // untouched

    stop_cheat_caller_address(minter.contract_address); // reset caller
}

#[test]
fn reserved_mint_descends_and_counts_down() {
    let (minter, _, _, reserved, nft_addr) = deploy_fixture(10);
    start_cheat_caller_address(minter.contract_address, reserved);
    mock_call(nft_addr, selector!("safe_mint"), (), 3);

    for i in 0_u64..3_u64 {
        let id = minter.mint_sparker(reserved, array![].span());
        assert_eq!(id, MAX_MINUS_ONE - i.into()); // descending id
    }
    assert_eq!(minter.get_reserved_remaining(), 7_u64);
    stop_cheat_caller_address(minter.contract_address); // reset caller
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn mint_public_without_role_reverts() {
    let (minter, _, _, _, _) = deploy_fixture(10);
    // Any account that lacks SALES_ROLE
    let attacker = test_address(); // helper macro
    start_cheat_caller_address(minter.contract_address, attacker);
    let _ = minter.mint_public(attacker, array![].span());
}

#[test]
fn mock_call_safe_mint() {
    let (minter, _, sales, _, path_nft_addr) = deploy_fixture(10);

    // Mock PathNFT’s safe_mint so the test doesn’t need a real ERC-721
    mock_call(path_nft_addr, selector!("safe_mint"), array![0], 1); // cheat-code docs

    start_cheat_caller_address(minter.contract_address, sales);
    let _ = minter.mint_public(sales, array![].span()); // works without deploying PathNFT
}

// ---------- edge-case: reserved cap exhausted ----------
#[test]
#[should_panic(expected: 'NO_RESERVED_LEFT')]
fn reserved_cap_exhausts_on_one_more_call() {
    let cap = 10_u64;
    let (minter, _admin, _sales, reserved, nft) = deploy_fixture(cap); // cap = 10
    let cap_one_more: u32 = (cap + 1).try_into().unwrap();
    let recipient: ContractAddress = test_address();
    mock_call(nft, selector!("safe_mint"), (), cap_one_more);

    start_cheat_caller_address(minter.contract_address, reserved);

    // first 10 mints succeed
    for _ in 0_u8..cap_one_more.try_into().unwrap() {
        let _ = minter.mint_sparker(recipient, array![].span());
    }

    // 11th call should hit the assert and panic
    minter.mint_sparker(recipient, array![].span());
}

// ---------- edge-case: zero cap ----------
#[test]
#[should_panic(expected: 'NO_RESERVED_LEFT')]
fn zero_cap_reverts_immediately() {
    let (minter, _, _, sparker, _) = deploy_fixture(0);
    start_cheat_caller_address(minter.contract_address, sparker);
    minter.mint_sparker(sparker, array![].span());
}
