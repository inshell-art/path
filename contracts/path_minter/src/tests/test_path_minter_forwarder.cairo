use core::array::Span;
use openzeppelin::access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use path_interfaces::{IForwarderDispatcher, IForwarderDispatcherTrait};
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address, test_address};
use starknet::ContractAddress;
use crate::tests::helper::deploy_fixture;


const TRANSFER_OWNERSHIP_SEL: felt252 = selector!("transfer_ownership");

#[test]
fn execute_transfer_ownership() {
    let (minter_iface, minter_admin, _minter_sales, _minter_reserved, nft_addr) = deploy_fixture(
        10,
    );
    let minter_addr: ContractAddress = minter_iface.contract_address;
    let forwarder: IForwarderDispatcher = IForwarderDispatcher { contract_address: minter_addr };
    let new_owner: ContractAddress = test_address();
    let calldata = array![new_owner.into()].span();

    start_cheat_caller_address(minter_addr, minter_admin);
    let _ret = forwarder.execute(nft_addr, TRANSFER_OWNERSHIP_SEL, calldata);
    stop_cheat_caller_address(minter_addr);

    let owner_after = IOwnableDispatcher { contract_address: nft_addr }.owner();
    assert_eq!(owner_after, new_owner);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn execute_without_admin_role_reverts() {
    let (minter, _minter_admin, _minter_sales, _minter_reserved, nft_addr) = deploy_fixture(10);
    let minter_addr: ContractAddress = minter.contract_address;
    let forwarder: IForwarderDispatcher = IForwarderDispatcher { contract_address: minter_addr };

    let attacker: ContractAddress = 100.try_into().unwrap();
    let bogus_owner: ContractAddress = 101.try_into().unwrap();

    let calldata = array![bogus_owner.into()].span();

    // Impersonate attacker (no role)
    start_cheat_caller_address(minter_addr, attacker);

    // This call should revert at the `assert_only_role` check
    let _ = forwarder.execute(nft_addr, TRANSFER_OWNERSHIP_SEL, calldata);
}
