//! Integration tests for PathMinter
use core::integer::u256;
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, mock_call, start_cheat_caller_address,
    stop_cheat_caller_address, test_address,
};
use starknet::ContractAddress;
use crate::interface::{IPathMinterDispatcher, IPathMinterDispatcherTrait};


// ----------------------- Constants -----------------------
// re compute `SALES_ROLE` and `RESERVED_ROLE` selectors, and MAX_MINUS_ONE
const SALES_ROLE: felt252 = selector!("SALES_ROLE");
const RESERVED_ROLE: felt252 = selector!("RESERVED_ROLE");
const MAX_MINUS_ONE: u256 = u256 {
    low: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE, high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
};

// ----------------------- deploy helper --------------------------
fn deploy_fixture() -> (
    IPathMinterDispatcher, ContractAddress, ContractAddress, ContractAddress, ContractAddress,
) {
    let nft_owner: ContractAddress = 1.try_into().unwrap();
    let minter_admin: ContractAddress = 2.try_into().unwrap();
    let minter_sales: ContractAddress = 3.try_into().unwrap();
    let minter_reserved: ContractAddress = 4.try_into().unwrap();
    let first_id_low = 0;
    let first_id_high = 0;
    let reserved_cap: u64 = 10_u64;

    /// Deploy PathNFT and PathMinter contracts, and set up roles
    let nft_class = declare("PathNFT").unwrap().contract_class();
    let (nft_addr, _) = nft_class.deploy(@array![nft_owner.into()]).unwrap();

    let class = declare("PathMinter").unwrap().contract_class();
    let (minter_addr, _) = class
        .deploy(
            @array![
                minter_admin.into(),
                nft_addr.into(),
                first_id_low.into(),
                first_id_high.into(),
                reserved_cap.into(),
            ],
        )
        .unwrap();
    let minter = IPathMinterDispatcher { contract_address: minter_addr };
    let access_iface = IAccessControlDispatcher { contract_address: minter_addr };

    // Grant roles (as admin)
    start_cheat_caller_address(minter_addr, minter_admin); // cheat-code
    access_iface.grant_role(SALES_ROLE, minter_sales);
    access_iface.grant_role(RESERVED_ROLE, minter_reserved);
    stop_cheat_caller_address(minter_addr); // reset caller

    return (minter, minter_admin, minter_sales, minter_reserved, nft_addr);
}

#[test]
fn constructor_sets_caps() {
    let (minter, _, _, _, _) = deploy_fixture();
    let stranger = test_address(); // helper macro

    start_cheat_caller_address(minter.contract_address, stranger);
    assert_eq!(minter.get_reserved_cap(), 10_u64);
    assert_eq!(minter.get_reserved_remaining(), 10_u64);
    stop_cheat_caller_address(minter.contract_address); // reset caller
}

#[test]
fn sales_role_can_mint_public() {
    let (minter, _, sales, _, nft_addr) = deploy_fixture();
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
    let (minter, _, _, reserved, nft_addr) = deploy_fixture();
    start_cheat_caller_address(minter.contract_address, reserved);
    mock_call(nft_addr, selector!("safe_mint"), (), 3);

    for i in 0_u64..3_u64 {
        let id = minter.mint_finder(reserved, array![].span());
        assert_eq!(id, MAX_MINUS_ONE - i.into()); // descending id
    }
    assert_eq!(minter.get_reserved_remaining(), 7_u64);
    stop_cheat_caller_address(minter.contract_address); // reset caller
}


#[test]
#[should_panic(expected: 'Caller is missing role')]
fn mint_public_without_role_reverts() {
    let (minter, _, _, _, _) = deploy_fixture();
    // Any account that lacks SALES_ROLE
    let attacker = test_address(); // helper macro
    start_cheat_caller_address(minter.contract_address, attacker);
    let _ = minter.mint_public(attacker, array![].span());
}

#[test]
fn mock_call_safe_mint() {
    let (minter, _, sales, _, path_nft_addr) = deploy_fixture();

    // Mock PathNFT’s safe_mint so the test doesn’t need a real ERC-721
    mock_call(path_nft_addr, selector!("safe_mint"), array![0], 1); // cheat-code docs

    start_cheat_caller_address(minter.contract_address, sales);
    let _ = minter.mint_public(sales, array![].span()); // works without deploying PathNFT
}
