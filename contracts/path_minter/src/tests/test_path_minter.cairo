use core::array::ArrayTrait;
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait, IAccessControlSafeDispatcherTrait,
};
use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait, ISRC5_ID};
use openzeppelin::token::erc721::ERC721Component;
use openzeppelin::token::erc721::interface::IERC721DispatcherTrait;
use path_interfaces::{IPathMinterDispatcherTrait, IPathMinterSafeDispatcherTrait};
use path_nft::path_nft::PathNFTEvent;
use path_test_support::prelude::*;
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{
    EventSpyAssertionsTrait, cheat_caller_address, mock_call, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};

//
// gl_*  (Global)
//

#[test]
fn gl_pm_constructor_registers_src5_and_caps() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);

    let src5 = ISRC5Dispatcher { contract_address: m.addr };
    assert!(src5.supports_interface(ISRC5_ID));

    assert_eq!(m.minter.get_reserved_cap(), RESERVED_CAP);
    assert_eq!(m.minter.get_reserved_remaining(), RESERVED_CAP);
}

#[test]
fn gl_pm_supports_interface_false_for_unknown() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let unknown: felt252 = 'NO_IFACE';
    let src5 = ISRC5Dispatcher { contract_address: m.addr };
    assert!(!src5.supports_interface(unknown));
}

//
// ac_*  (AccessControl)
//

#[test]
#[feature("safe_dispatcher")]
fn ac_pm_only_admin_can_grant_roles() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);

    cheat_caller_address(m.addr, BOB(), CheatSpan::TargetCalls(1));
    match m.ac_safe.grant_role(SALES_ROLE, ALICE()) {
        Result::Ok(_) => panic!("non-admin should not grant SALES_ROLE"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'Caller is missing role');
        },
    }

    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(2));
    m.ac.grant_role(SALES_ROLE, ALICE());
    m.ac.grant_role(RESERVED_ROLE, ALICE());

    assert!(m.ac.has_role(SALES_ROLE, ALICE()));
    assert!(m.ac.has_role(RESERVED_ROLE, ALICE()));
}

#[test]
#[feature("safe_dispatcher")]
fn ac_pm_non_admin_cannot_revoke_roles() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);

    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(SALES_ROLE, ALICE());
    assert!(m.ac.has_role(SALES_ROLE, ALICE()));

    cheat_caller_address(m.addr, BOB(), CheatSpan::TargetCalls(1));
    match m.ac_safe.revoke_role(SALES_ROLE, ALICE()) {
        Result::Ok(_) => panic!("non-admin should not revoke SALES_ROLE"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'Caller is missing role');
        },
    }
    assert!(m.ac.has_role(SALES_ROLE, ALICE()));
}

//
// mint_public_* (Public)
//

#[test]
#[feature("safe_dispatcher")]
fn mint_public_requires_sales_role() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr);

    cheat_caller_address(m.addr, BOB(), CheatSpan::TargetCalls(1));
    match m.minter_safe.mint_public(to, array![].span()) {
        Result::Ok(_) => panic!("mint_public without SALES_ROLE should revert"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'Caller is missing role');
        },
    }
}

#[test]
fn mint_public_sequences_ids_and_sets_ownership() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(SALES_ROLE, ALICE());

    cheat_caller_address(m.addr, ALICE(), CheatSpan::TargetCalls(2));
    let id0 = m.minter.mint_public(to, array![].span());
    let id1 = m.minter.mint_public(to, array![].span());

    assert_eq!(id0, FIRST_PUBLIC_ID);
    assert_eq!(id1, FIRST_PUBLIC_ID + 1_u256);
    assert_eq!(m.erc721.owner_of(id0), to);
    assert_eq!(m.erc721.owner_of(id1), to);
}

#[test]
#[feature("safe_dispatcher")]
fn mint_public_rolls_back_next_id_on_nft_revert() {
    // NFT with NO minter
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    // Give ALICE SALES_ROLE on PathMinter, but DO NOT grant MINTER_ROLE on the NFT yet
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(SALES_ROLE, ALICE());

    // Sanity: PathMinter should not be an NFT minter now
    let ac_nft = IAccessControlDispatcher { contract_address: nft.addr };
    let minter_role = selector!("MINTER_ROLE");
    assert!(!ac_nft.has_role(minter_role, m.addr));

    // 1) This must revert -> state (next_id) should roll back
    cheat_caller_address(m.addr, ALICE(), CheatSpan::TargetCalls(1));
    match m.minter_safe.mint_public(to, array![].span()) {
        Result::Ok(_) => panic!("expected revert: PathMinter missing MINTER_ROLE on NFT"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'Caller is missing role');
        },
    }

    // 2) Grant MINTER_ROLE, then mint -> should return FIRST_PUBLIC_ID (not 1001)
    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ALICE(), CheatSpan::TargetCalls(1));
    let id = m.minter.mint_public(to, array![].span());
    assert_eq!(m.erc721.owner_of(id), to);
    assert_eq!(id, FIRST_PUBLIC_ID);
}


#[test]
fn mint_reserved_ids_are_above_public_ids() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(2));
    m.ac.grant_role(SALES_ROLE, ALICE());
    m.ac.grant_role(RESERVED_ROLE, ALICE());

    start_cheat_caller_address(m.addr, ALICE());
    let pub_id = m.minter.mint_public(to, array![].span());
    let res_id = m.minter.mint_sparker(to, array![].span());
    stop_cheat_caller_address(m.addr);

    assert!(res_id.high > pub_id.high, "reserved id should be in the high range");
}

#[test]
#[feature("safe_dispatcher")]
fn mint_mint_public_to_address_that_rejects_receiver_reverts() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(SALES_ROLE, to);

    const ON_ERC721_RECEIVED: felt252 = selector!("on_erc721_received");
    const BAD_ID: felt252 = 0;
    mock_call(to, ON_ERC721_RECEIVED, BAD_ID, 1_u32);

    cheat_caller_address(m.addr, to, CheatSpan::TargetCalls(1));
    match m.minter_safe.mint_public(to, array![].span()) {
        Result::Ok(_) => panic!("expected revert due to receiver rejecting"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'ERC721: safe mint failed');
        },
    }
}


//
// mint_sparker_* (Reserved)
//

#[test]
#[feature("safe_dispatcher")]
fn mint_sparker_requires_reserved_role() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr); // ensure underlying NFT accepts mints

    cheat_caller_address(m.addr, BOB(), CheatSpan::TargetCalls(1));
    match m.minter_safe.mint_sparker(to, array![].span()) {
        Result::Ok(_) => panic!("mint_sparker without RESERVED_ROLE should revert"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'Caller is missing role');
        },
    }
}

#[test]
fn mint_sparker_counts_down_and_updates_remaining() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(RESERVED_ROLE, ALICE());

    start_cheat_caller_address(m.addr, ALICE());
    let id0 = m.minter.mint_sparker(to, array![].span());
    assert_eq!(m.erc721.owner_of(id0), to);
    assert_eq!(m.minter.get_reserved_remaining(), RESERVED_CAP - 1_u64);

    let id1 = m.minter.mint_sparker(to, array![].span());
    assert_eq!(id1, id0 - 1_u256);
    assert_eq!(m.erc721.owner_of(id1), to);
    assert_eq!(m.minter.get_reserved_remaining(), RESERVED_CAP - 2_u64);
    stop_cheat_caller_address(m.addr);
}

#[test]
#[feature("safe_dispatcher")]
fn mint_sparker_exhaustion_reverts() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(RESERVED_ROLE, ALICE());

    // Mint out the reserved pool
    start_cheat_caller_address(m.addr, ALICE());
    let _ = m.minter.mint_sparker(to, array![].span());
    let _ = m.minter.mint_sparker(to, array![].span());
    let _ = m.minter.mint_sparker(to, array![].span());
    assert_eq!(m.minter.get_reserved_remaining(), 0_u64);

    // Next call must revert with NO_RESERVED_LEFT (string or felt short-string)
    match m.minter_safe.mint_sparker(to, array![].span()) {
        Result::Ok(_) => panic!("expected NO_RESERVED_LEFT revert"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'NO_RESERVED_LEFT');
        },
    }
    stop_cheat_caller_address(m.addr);
}

//
//      int_* (Integration)
//

#[test]
#[feature("safe_dispatcher")]
fn int_pm_requires_minter_role_on_nft() {
    let nft = deploy_path_nft_default(); // PathMinter not yet minter on NFT
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    // Give SALES_ROLE so only the NFT minter-role dependency can fail
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(SALES_ROLE, ALICE());

    // ALICE attempts mint_public -> underlying NFT.safe_mint should revert (no MINTER_ROLE)
    cheat_caller_address(m.addr, ALICE(), CheatSpan::TargetCalls(1));
    match m.minter_safe.mint_public(to, array![].span()) {
        Result::Ok(_) => panic!("expected revert due to missing MINTER_ROLE on NFT for PathMinter"),
        Result::Err(panic_data) => {
            assert_eq!(panic_data.len(), 1, "expected single-felt panic data");
            assert_eq!(*panic_data.at(0), 'Caller is missing role');
        },
    }
}

#[test]
fn int_pm_emits_transfer_on_public_mint() {
    let nft = deploy_path_nft_default();
    let m = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);
    let to = deploy_receiver();

    // Grants required
    grant_minter_on_nft(@nft, m.addr);
    cheat_caller_address(m.addr, ADMIN(), CheatSpan::TargetCalls(1));
    m.ac.grant_role(SALES_ROLE, ALICE());

    // Watch events on the NFT collection
    let mut spy = spy_events();

    // ALICE mints via minter
    cheat_caller_address(m.addr, ALICE(), CheatSpan::TargetCalls(1));
    let minted = m.minter.mint_public(to, array![].span());

    // Expect Transfer(0 -> to, tokenId) on PathNFT
    let expected: PathNFTEvent = PathNFTEvent::ERC721Event(
        ERC721Component::Event::Transfer(
            ERC721Component::Transfer { from: ZERO_ADDR(), to, token_id: minted },
        ),
    );
    spy.assert_emitted(@array![(nft.addr, expected)]);
}
