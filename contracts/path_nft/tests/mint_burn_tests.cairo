use openzeppelin::token::erc721::interface::IERC721DispatcherTrait;
use path_nft::i_path_nft::IPathNFTDispatcherTrait;
use snforge_std::{CheatSpan, cheat_caller_address};
use starknet::ContractAddress;
use crate::utils::setup;

const ERR_NOT_OWNER: felt252 =
    0x43616c6c6572206973206e6f7420746865206f776e6572; // "Caller is not the owner"
const ERR_UNAUTHORIZED: felt252 =
    0x4552433732313a20756e617574686f72697a65642063616c6c6572; // "ERC721: unauthorized caller"

// Helper: Deploy contract, and prepare the interfaces

#[test]
fn contract_owner_can_safe_mint_to_recipient_and_recipient_can_burn() {
    let (owner, addr, nft_iface, erc721_iface, _, token_id, recipient, data) = setup();

    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    nft_iface.safe_mint(recipient, token_id, data);
    assert_eq!(erc721_iface.owner_of(token_id), recipient);

    cheat_caller_address(addr, recipient, CheatSpan::TargetCalls(1));
    nft_iface.burn(token_id);
    assert_eq!(erc721_iface.balance_of(recipient), 0_u256);
}

#[test]
#[should_panic(expected: 0x43616c6c6572206973206e6f7420746865206f776e6572)]
fn not_contract_owner_can_not_safe_mint() {
    let (_, addr, nft_iface, _, _, token_id, recipient, data) = setup();

    let not_owner: ContractAddress = 4.try_into().unwrap();
    cheat_caller_address(addr, not_owner, CheatSpan::TargetCalls(1));
    nft_iface.safe_mint(recipient, token_id, data);
}

#[test]
#[should_panic(expected: 0x4552433732313a20756e617574686f72697a65642063616c6c6572)]
fn not_recipient_can_not_burn() {
    let (owner, addr, nft_iface, erc721_iface, _, token_id, recipient, data) = setup();

    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    nft_iface.safe_mint(recipient, token_id, data);
    assert_eq!(erc721_iface.owner_of(token_id), recipient);

    let not_recipient: ContractAddress = 4.try_into().unwrap();
    cheat_caller_address(addr, not_recipient, CheatSpan::TargetCalls(1));
    nft_iface.burn(token_id);
}
