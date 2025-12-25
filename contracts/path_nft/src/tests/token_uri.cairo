use core::array::ArrayTrait;
use core::byte_array::ByteArrayTrait;
use openzeppelin::token::erc721::interface::{
    IERC721MetadataDispatcherTrait, IERC721SafeDispatcherTrait,
};
use path_interfaces::interfaces::IPathNFTDispatcherTrait;
use path_test_support::prelude::*;
use snforge_std::cheat_caller_address;
use snforge_std::cheatcodes::CheatSpan;

const T0: u256 = 0_u256;

#[test]
fn token_uri_wraps_path_look_metadata() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    grant_minter_on_nft(@h, MINTER());
    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T0, array![1, 2, 3].span());

    let uri = h.meta.token_uri(T0);
    assert!(
        starts_with_bytes(@uri, @"data:application/json,"),
    ); // OZ metadata returns JSON ByteArray. :contentReference[oaicite:6]{index=6}

    assert!(contains_bytes(@uri, @"\"token\":"));
    assert!(contains_bytes(@uri, @"\"stage\":\"IDEAL\""));
    assert!(contains_bytes(@uri, @"\"thought\":\"Latent\""));
    assert!(contains_bytes(@uri, @"\"will\":\"Latent\""));
    assert!(contains_bytes(@uri, @"\"awa\":\"Latent\""));
}

#[test]
fn token_uri_reflects_stage_after_movement() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    grant_minter_on_nft(@h, MINTER());
    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.nft.set_authorized_minter('THOUGHT', ALICE());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T0, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    h.nft.consume_movement(T0, 'THOUGHT', to);

    let uri = h.meta.token_uri(T0);
    assert!(contains_bytes(@uri, @"\"stage\":\"THOUGHT\""));
    assert!(contains_bytes(@uri, @"\"thought\":\"Manifested\""));
    assert!(contains_bytes(@uri, @"\"will\":\"Latent\""));
    assert!(contains_bytes(@uri, @"\"awa\":\"Latent\""));
}

#[test]
#[feature("safe_dispatcher")]
fn token_uri_nonexistent_reverts() {
    let h = deploy_path_nft_default();

    // owner_of / token_uri on a non-minted id should revert with a string "ERC721: invalid token
    // ID" per OZ. :contentReference[oaicite:7]{index=7}
    // Call via Safe dispatcher pattern by using the generic SafeDispatcher on ERC721 for owner_of
    match h.erc721_safe.owner_of(T0) {
        Result::Ok(_) => panic!("expected revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ERC721: invalid token ID'); },
    }
}

fn starts_with_bytes(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let hay_len = haystack.len();
    let ned_len = needle.len();
    if ned_len == 0_usize {
        return true;
    }
    if ned_len > hay_len {
        return false;
    }
    let mut i: usize = 0_usize;
    while i < ned_len {
        if haystack.at(i).unwrap() != needle.at(i).unwrap() {
            return false;
        }
        i = i + 1_usize;
    }
    true
}

fn contains_bytes(haystack: @ByteArray, needle: @ByteArray) -> bool {
    let hay_len = haystack.len();
    let ned_len = needle.len();
    if ned_len == 0_usize {
        return true;
    }
    if ned_len > hay_len {
        return false;
    }
    let mut i: usize = 0_usize;
    while i + ned_len <= hay_len {
        let mut j: usize = 0_usize;
        let mut matched = true;
        while j < ned_len {
            if haystack.at(i + j).unwrap() != needle.at(j).unwrap() {
                matched = false;
                break;
            }
            j = j + 1_usize;
        }
        if matched {
            return true;
        }
        i = i + 1_usize;
    }
    false
}
