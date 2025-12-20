use core::array::ArrayTrait;
use path_test_support::prelude::*;
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{cheat_caller_address, try_deserialize_bytearray_error};

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
        uri.starts_with("data:application/json,"),
    ); // OZ metadata returns JSON ByteArray. :contentReference[oaicite:6]{index=6}

    assert!(uri.contains("\"token\":"));
    assert!(uri.contains("\"thought\":1"));
    assert!(uri.contains("\"will\":2"));
    assert!(uri.contains("\"awa\":3"));
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
        Result::Err(panic_data) => {
            let msg = try_deserialize_bytearray_error(panic_data.span()).expect("non-string panic");
            assert_eq!(msg, "ERC721: invalid token ID");
        },
    }
}
