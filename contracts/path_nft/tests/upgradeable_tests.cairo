use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721DispatcherTrait};
use openzeppelin::upgrades::interface::{IUpgradeableDispatcher, IUpgradeableDispatcherTrait};
use path_nft::PathNFT_interface::PathNFTInterfaceDispatcherTrait;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare,
    get_class_hash,
};
use crate::PathNFTV1Stub::{PathNFTV1StubInterfaceDispatcher, PathNFTV1StubInterfaceDispatcherTrait};
use crate::utils::setup;

const ERR_NOT_OWNER: felt252 =
    0x43616c6c6572206973206e6f7420746865206f776e6572; // "Caller is not the owner"

#[test]
fn upgrade_flow_happy_way() {
    let (owner, addr, nft_iface, _, _, token_id, recipient, _) = setup();

    // Mint token_id to recipient so we can verify the storage survival later
    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    nft_iface.safe_mint(recipient, token_id, array![0_felt252].span()); // Try 1_felt252 later

    // Prepare: deploy V1 and get the class hash, and create an upgradeable dispatcher
    let (stub_addr, _) = declare("PathNFTV1Stub")
        .unwrap()
        .contract_class()
        .deploy(@array![1_felt252])
        .unwrap();
    let class_v1 = get_class_hash(stub_addr);
    let upgradeable_iface = IUpgradeableDispatcher { contract_address: addr };

    // Upgrade the contract
    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    upgradeable_iface.upgrade(class_v1);

    // Assert 1: the class hash is the new one
    let class_hash = get_class_hash(addr);
    assert!(class_hash == class_v1, "Class hash did not update correctly");

    // Assert 2: the token_id is still owned by recipient
    let erc721_iface = IERC721Dispatcher { contract_address: addr };
    let token_owner = erc721_iface.owner_of(token_id);
    assert!(token_owner == recipient, "Token owner did not remain the same");

    // Assert 3: version() returns the correct version
    let version = PathNFTV1StubInterfaceDispatcher { contract_address: addr }.version();
    assert!(version == 1_felt252, "No method version() found in V1");
}

#[test]
#[should_panic(expected: 0x43616c6c6572206973206e6f7420746865206f776e6572)]
fn only_owner_can_upgrade() {
    let (_, addr, _, _, _, _, recipient, _) = setup();
    let upgradeable_iface = IUpgradeableDispatcher { contract_address: addr };

    // Deploy V1 and get the class hash
    let (addr, _) = declare("PathNFTV1Stub")
        .unwrap()
        .contract_class()
        .deploy(@array![1_felt252])
        .unwrap();
    let class_v1 = get_class_hash(addr);

    // Try to upgrade the contract as a non-owner
    cheat_caller_address(addr, recipient, CheatSpan::TargetCalls(1));
    upgradeable_iface.upgrade(class_v1);
}
