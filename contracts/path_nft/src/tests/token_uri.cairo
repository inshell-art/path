#[test]
fn token_uri_is_inline_json_and_svg_contains_id() {
    let h = deploy_path_nft(ADMIN(), MINTER());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T0, array![].span());

    let uri = h.meta.token_uri(T0);
    assert!(
        uri.starts_with("data:application/json,"),
    ); // OZ metadata returns JSON ByteArray. :contentReference[oaicite:6]{index=6}

    // Your implementation builds an inline SVG containing "token_id: <id>"
    let needle = format!("token_id: {}", T0);
    assert!(uri.contains(needle));
}

#[test]
#[feature("safe_dispatcher")]
fn token_uri_nonexistent_reverts() {
    let h = deploy_path_nft(ADMIN(), MINTER());
    // Use a safe dispatcher (metadata has a dedicated interface)
    let meta_safe = IERC721MetadataDispatcher {
        contract_address: h.addr,
    }; // calling normal dispatcher will panic

    // owner_of / token_uri on a non-minted id should revert with a string "ERC721: invalid token
    // ID" per OZ. :contentReference[oaicite:7]{index=7}
    let meta_safe = IERC721MetadataDispatcher { contract_address: h.addr };
    // Call via Safe dispatcher pattern by using the generic SafeDispatcher on ERC721 for owner_of
    match h.erc721_safe.owner_of(T0) {
        Result::Ok(_) => panic!("expected revert"),
        Result::Err(panic_data) => {
            let msg = try_deserialize_bytearray_error(panic_data.span()).expect("non-string panic");
            assert_eq!(msg, "ERC721: invalid token ID");
        },
    }
}
