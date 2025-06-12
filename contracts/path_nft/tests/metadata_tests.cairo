use openzeppelin::token::erc721::interface::{
    IERC721DispatcherTrait, IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait,
};
use path_nft::i_path_nft::IPathNFTDispatcherTrait;
use snforge_std::{CheatSpan, cheat_caller_address};
use crate::utils::setup;

// “ERC721: invalid token ID” as a felt252 short-string
const ERC721_INVALID_TOKEN_ID: felt252 = 0x4552433732313a20696e76616c696420746f6b656e204944;


#[test]
fn token_uri_happy_path() {
    let (owner, addr, nft_iface, erc721_iface, _, token_id, recipient, data) = setup();

    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    nft_iface.safe_mint(recipient, token_id, data);
    assert_eq!(erc721_iface.owner_of(token_id), recipient);

    let metadata_iface = IERC721MetadataDispatcher { contract_address: addr };

    cheat_caller_address(addr, recipient, CheatSpan::TargetCalls(1));
    metadata_iface.token_uri(token_id);
    // Assuming the token_uri returns a valid SVG or metadata string
    let svg = metadata_iface.token_uri(token_id);
    assert!(svg.len() > 0, "Token URI should not be empty");
}


#[test]
#[should_panic(expected: 0x4552433732313a20696e76616c696420746f6b656e204944)]
fn nonexistent_token_id_call_token_uri_should_panic() {
    let (owner, addr, _, _, _, _, _, _) = setup();
    let nonexistent_token_id: u256 = 999_u256; // Assuming this token ID does not exist

    let metadata_iface = IERC721MetadataDispatcher { contract_address: addr };
    cheat_caller_address(addr, owner, CheatSpan::TargetCalls(1));
    metadata_iface.token_uri(nonexistent_token_id);
}
