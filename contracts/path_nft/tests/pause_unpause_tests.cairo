use openzeppelin::security::interface::IPausableDispatcherTrait;
use path_nft::PathNFT_interface::PathNFTInterfaceDispatcherTrait;
use snforge_std::{CheatSpan, cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::setup;

const ERR_NOT_OWNER: felt252 =
    0x43616c6c6572206973206e6f7420746865206f776e6572; // "Caller is not the owner"

#[test]
fn pause_and_unpause_by_owner() {
    let (owner, addr, nft_iface, _, pausable_iface, _, _, _) = setup();

    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    nft_iface.pause();
    assert_eq!(pausable_iface.is_paused(), true);

    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    nft_iface.unpause();
    assert_eq!(pausable_iface.is_paused(), false);
}

#[test]
#[should_panic(expected: 0x43616c6c6572206973206e6f7420746865206f776e6572)]
fn not_owner_can_not_pause() {
    let (owner, addr, nft_iface, _, _, _, _, _) = setup();
    let not_owner_felt: felt252 = owner.into() + 1;
    let not_owner: ContractAddress = not_owner_felt.try_into().unwrap();

    cheat_caller_address(addr, not_owner, CheatSpan::TargetCalls(1));
    nft_iface.pause();
}
