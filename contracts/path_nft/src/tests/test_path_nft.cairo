use core::array::ArrayTrait;
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait, IAccessControlSafeDispatcher,
    IAccessControlSafeDispatcherTrait,
};
use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
use openzeppelin::introspection::interface::{ISRC5DispatcherTrait, ISRC5_ID};
use openzeppelin::token::erc721::ERC721Component;
use openzeppelin::token::erc721::interface::{
    IERC721DispatcherTrait, IERC721MetadataCamelOnlyDispatcherTrait, IERC721MetadataDispatcherTrait,
    IERC721SafeDispatcherTrait, IERC721_ID, IERC721_METADATA_ID,
};
use path_interfaces::{IPathNFTDispatcherTrait, IPathNFTSafeDispatcherTrait};
use path_nft::path_nft::PathNFTEvent;
use path_test_support::prelude::*;
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{
    EventSpyAssertionsTrait, cheat_account_contract_address, cheat_caller_address, spy_events,
};

//
// Setup
//

const T1: u256 = 1_u256;
const T2: u256 = 777_u256;

//
// gl_* (global)
//

#[test]
fn gl_constructor_registers_interfaces_and_sets_metadata() {
    let h = deploy_path_nft_default();
    assert_eq!(h.meta.name(), NAME());
    assert_eq!(h.meta.symbol(), SYMBOL());

    assert!(h.src5.supports_interface(IERC721_ID));
    assert!(h.src5.supports_interface(IERC721_METADATA_ID));
    assert!(h.src5.supports_interface(ISRC5_ID));
}

#[test]
fn gl_camelcase_aliases_are_wired() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safeMint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    let snake = h.meta.token_uri(T1);
    let camel = h.camel_meta.tokenURI(T1);
    assert_eq!(snake, camel);
}

#[test]
fn gl_supports_interface_false_for_unknown() {
    let h = deploy_path_nft_default();
    let unknown: felt252 = 'NO_IFACE';
    assert!(!h.src5.supports_interface(unknown));
}

//
// ac_* (access control)
//

#[test]
fn ac_admin_and_MINTER_ROLEs_bootstrap_ok() {
    let h = deploy_path_nft_default();
    let ac = IAccessControlDispatcher { contract_address: h.addr };

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    assert!(ac.has_role(DEFAULT_ADMIN_ROLE, ADMIN()));
    assert!(ac.has_role(MINTER_ROLE, MINTER()));
    assert!(!ac.has_role(MINTER_ROLE, ALICE()));
}

#[test]
#[feature("safe_dispatcher")]
fn ac_admin_cannot_mint_without_MINTER_ROLE() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    // ADMIN is DEFAULT_ADMIN_ROLE, but not MINTER_ROLE
    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(to, T1, array![].span()) {
        Result::Ok(_) => panic!("ADMIN should not be able to mint without MINTER_ROLE"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    // MINTER can mint (sanity)
    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);
}

#[test]
#[feature("safe_dispatcher")]
fn ac_admin_grant_and_revoke_minter_emits_events_and_changes_effect() {
    let h = deploy_path_nft_default();
    let ac = IAccessControlDispatcher { contract_address: h.addr };
    let to = deploy_receiver();

    // --- Grant MINTER to ALICE (admin-only) + event
    let mut spy = spy_events();
    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    ac.grant_role(MINTER_ROLE, ALICE());

    let granted: PathNFTEvent = PathNFTEvent::AccessControlEvent(
        AccessControlComponent::Event::RoleGranted(
            AccessControlComponent::RoleGranted {
                role: MINTER_ROLE, account: ALICE(), sender: ADMIN(),
            },
        ),
    );
    spy.assert_emitted(@array![(h.addr, granted)]);

    // ALICE can now mint
    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    // --- Revoke MINTER from ALICE (admin-only) + event
    let mut spy = spy_events();
    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    ac.revoke_role(MINTER_ROLE, ALICE());

    let revoked: PathNFTEvent = PathNFTEvent::AccessControlEvent(
        AccessControlComponent::Event::RoleRevoked(
            AccessControlComponent::RoleRevoked {
                role: MINTER_ROLE, account: ALICE(), sender: ADMIN(),
            },
        ),
    );
    spy.assert_emitted(@array![(h.addr, revoked)]);

    // ALICE can no longer mint
    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(to, T2, array![].span()) {
        Result::Ok(_) => panic!("revoked minter should not be able to mint"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn ac_non_admin_cannot_grant_or_revoke_minter() {
    let h = deploy_path_nft_default();
    let acs = IAccessControlSafeDispatcher { contract_address: h.addr };

    // Non-admin tries to grant
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match acs.grant_role(MINTER_ROLE, ALICE()) {
        Result::Ok(_) => panic!("non-admin granting MINTER should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }

    // Non-admin tries to revoke (even from a real minter)
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match acs.revoke_role(MINTER_ROLE, MINTER()) {
        Result::Ok(_) => panic!("non-admin revoking MINTER should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }
}

//
// cfg_* (config)
//

#[test]
#[feature("safe_dispatcher")]
fn cfg_set_path_look_admin_only_and_rejects_zero() {
    let h = deploy_path_nft_default();

    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match h.nft_safe.set_path_look(ALICE()) {
        Result::Ok(_) => panic!("non-admin set_path_look should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role'); },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    match h.nft_safe.set_path_look(ZERO_ADDR()) {
        Result::Ok(_) => panic!("zero path_look should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ZERO_PATH_LOOK'); },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.nft.set_path_look(ALICE());
    assert_eq!(h.nft.get_path_look(), ALICE());
}

#[test]
#[feature("safe_dispatcher")]
fn cfg_set_movement_config_admin_only_and_rejects_zero() {
    let h = deploy_path_nft_default();

    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match h.nft_safe.set_movement_config('THOUGHT', ALICE(), 3_u32) {
        Result::Ok(_) => panic!("non-admin set_movement_config should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role'); },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    match h.nft_safe.set_movement_config('THOUGHT', ZERO_ADDR(), 3_u32) {
        Result::Ok(_) => panic!("zero minter should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ZERO_MINTER'); },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    match h.nft_safe.set_movement_config('THOUGHT', ALICE(), 0_u32) {
        Result::Ok(_) => panic!("zero quota should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ZERO_QUOTA'); },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.nft.set_movement_config('THOUGHT', ALICE(), 3_u32);
    assert_eq!(h.nft.get_authorized_minter('THOUGHT'), ALICE());
    assert_eq!(h.nft.get_movement_quota('THOUGHT'), 3_u32);
}

//
// mint_* (minting)
//

#[test]
#[feature("safe_dispatcher")]
fn mint_duplicate_token_id_reverts() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(2)); // call twice
    h.nft.safe_mint(to, T1, array![].span());
    match h.nft_safe.safe_mint(to, T1, array![].span()) {
        Result::Ok(_) => panic!("duplicate token id should revert"),
        Result::Err(_panic_data) => {
            assert_eq!(*_panic_data.at(0), 'ERC721: token already minted');
        } // accept either felt- or string-coded error
    }
}

#[test]
#[feature("safe_dispatcher")]
fn mint_only_minter_can_safe_mint() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(to, T1, array![].span()) {
        Result::Ok(_) => panic!("expected revert: non-minter mint"),
        Result::Err(_panic_data) => {},
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    let mut spy = spy_events();
    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T2, array![].span());

    let expected = PathNFTEvent::ERC721Event(
        ERC721Component::Event::Transfer(
            ERC721Component::Transfer { from: ZERO_ADDR(), to, token_id: T2 },
        ),
    );
    spy.assert_emitted(@array![(h.addr, expected)]);
}

#[test]
#[feature("safe_dispatcher")]
fn mint_mint_to_zero_address_reverts() {
    let h = deploy_path_nft_default();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(ZERO_ADDR(), T1, array![].span()) {
        Result::Ok(_) => panic!("mint to zero should revert"),
        Result::Err(_) => {},
    }
}

#[test]
fn mint_remint_after_burn_works() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    // First mint
    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    // Burn as owner
    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.burn(T1);

    // Re-mint same id: allowed
    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);
}

//
// tr_* (transfer)
//

#[test]
#[feature("safe_dispatcher")]
fn tr_transfer_to_zero_address_reverts() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    match h.erc721_safe.transfer_from(to, ZERO_ADDR(), T1) {
        Result::Ok(_) => panic!("transfer to ZERO address should revert"),
        Result::Err(_) => {},
    }
}


#[test]
fn tr_owner_transfer_from_works() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.transfer_from(to, ALICE(), T1);
    assert_eq!(h.erc721.owner_of(T1), ALICE());
}

#[test]
#[feature("safe_dispatcher")]
fn tr_transfer_unauthorized_reverts() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    // BOB is neither owner nor approved
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match h.erc721_safe.transfer_from(to, ALICE(), T1) {
        Result::Ok(_) => panic!("unauthorized transfer should revert"),
        Result::Err(_) => {},
    }
}

#[test]
fn tr_approved_can_transfer_and_approval_clears() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    // Owner approves BOB
    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.approve(BOB(), T1);
    assert_eq!(h.erc721.get_approved(T1), BOB());

    // BOB transfers to ALICE; approval must clear
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    h.erc721.transfer_from(to, ALICE(), T1);
    assert_eq!(h.erc721.owner_of(T1), ALICE());
    assert_eq!(h.erc721.get_approved(T1), ZERO_ADDR());
}

#[test]
fn tr_operator_transfer_and_event() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    // Watch for ApprovalForAll
    let mut spy = spy_events();
    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.set_approval_for_all(BOB(), true);

    // Expect ApprovalForAll event
    let expected = PathNFTEvent::ERC721Event(
        ERC721Component::Event::ApprovalForAll(
            ERC721Component::ApprovalForAll { owner: to, operator: BOB(), approved: true },
        ),
    );
    spy.assert_emitted(@array![(h.addr, expected)]);

    // Now operator moves the token
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    h.erc721.transfer_from(to, ALICE(), T1);
    assert_eq!(h.erc721.owner_of(T1), ALICE());
}


//
// burn_* (burning)
//

#[test]
#[feature("safe_dispatcher")]
fn burn_reverts_for_non_owner() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match h.nft_safe.burn(T1) {
        Result::Ok(_) => panic!("expected unauthorized burn to revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ERR_NOT_OWNER'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn burn_nonexistent_reverts() {
    let h = deploy_path_nft_default();

    // No mint; any caller should see a revert (owner_of inside burn will fail)
    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    match h.nft_safe.burn(T1) {
        Result::Ok(_) => panic!("burn of nonexistent token should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ERC721: invalid token ID'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn burn_owner_can_burn_and_owner_of_then_reverts() {
    let h: NftHandles = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    let mut spy = spy_events();
    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.burn(T1);
    let expected = PathNFTEvent::ERC721Event(
        ERC721Component::Event::Transfer(
            ERC721Component::Transfer { from: to, to: ZERO_ADDR(), token_id: T1 },
        ),
    );
    spy.assert_emitted(@array![(h.addr, expected)]);

    match h.erc721_safe.owner_of(T1) {
        Result::Ok(_) => panic!("owner_of should revert after burn"),
        Result::Err(panic_data) => {
            let msg = panic_data.at(0);
            assert_eq!(msg, @'ERC721: invalid token ID');
        },
    }
}

#[test]
fn burn_approved_can_burn() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.approve(BOB(), T1);

    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    h.nft.burn(T1);

    assert_eq!(h.erc721.balance_of(to), 0_u256);
}

#[test]
fn burn_operator_can_burn() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.set_approval_for_all(BOB(), true);

    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    h.nft.burn(T1);

    assert_eq!(h.erc721.balance_of(to), 0_u256);
}

#[test]
#[feature("safe_dispatcher")]
fn movement_consume_requires_authorized_minter() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(MINTER_ROLE, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'THOUGHT', to) {
        Result::Ok(_) => panic!("expected unauthorized minter revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ERR_UNAUTHORIZED_MINTER'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn movement_consume_invalid_movement_reverts() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(2));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'DREAM', to) {
        Result::Ok(_) => panic!("invalid movement should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'BAD_MOVEMENT'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn movement_consume_requires_owner_or_approved_claimer() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(2));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'THOUGHT', BOB()) {
        Result::Ok(_) => panic!("unapproved claimer should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'ERR_NOT_OWNER'); },
    }
}

#[test]
fn movement_consume_allows_approved_claimer() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(2));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.approve(BOB(), T1);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    let serial = h.nft.consume_unit(T1, 'THOUGHT', BOB());
    assert_eq!(serial, 0_u32);
    assert_eq!(h.nft.get_stage(T1), 1_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 0_u32);
}

#[test]
#[feature("safe_dispatcher")]
fn movement_consume_requires_claimer_matches_tx_sender() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(2));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'THOUGHT', BOB()) {
        Result::Ok(_) => panic!("expected BAD_CLAIMER"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'BAD_CLAIMER'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn movement_freeze_blocks_config_updates() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(2));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    let _ = h.nft.consume_unit(T1, 'THOUGHT', to);

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    match h.nft_safe.set_movement_config('THOUGHT', BOB(), 2_u32) {
        Result::Ok(_) => panic!("expected MOVEMENT_FROZEN"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'MOVEMENT_FROZEN'); },
    }
}

#[test]
#[feature("safe_dispatcher")]
fn movement_consume_rejects_wrong_stage() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(3));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);
    h.nft.set_movement_config('WILL', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'WILL', to) {
        Result::Ok(_) => panic!("wrong stage should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'BAD_MOVEMENT_ORDER'); },
    }

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'THOUGHT', to);
    assert_eq!(h.nft.get_stage(T1), 1_u8);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'THOUGHT', to) {
        Result::Ok(_) => panic!("repeat movement should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'BAD_MOVEMENT_ORDER'); },
    }
}

#[test]
fn movement_consume_advances_stage_in_order() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(4));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 2_u32);
    h.nft.set_movement_config('WILL', ALICE(), 2_u32);
    h.nft.set_movement_config('AWA', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.nft.get_stage(T1), 0_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 0_u32);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'THOUGHT', to);
    assert_eq!(h.nft.get_stage(T1), 0_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 1_u32);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'THOUGHT', to);
    assert_eq!(h.nft.get_stage(T1), 1_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 0_u32);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'WILL', to);
    assert_eq!(h.nft.get_stage(T1), 1_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 1_u32);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'WILL', to);
    assert_eq!(h.nft.get_stage(T1), 2_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 0_u32);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'AWA', to);
    assert_eq!(h.nft.get_stage(T1), 3_u8);
    assert_eq!(h.nft.get_stage_minted(T1), 0_u32);
}

#[test]
#[feature("safe_dispatcher")]
fn movement_consume_after_final_stage_reverts() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(4));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);
    h.nft.set_movement_config('WILL', ALICE(), 1_u32);
    h.nft.set_movement_config('AWA', ALICE(), 1_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(3));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(3));
    h.nft.consume_unit(T1, 'THOUGHT', to);
    h.nft.consume_unit(T1, 'WILL', to);
    h.nft.consume_unit(T1, 'AWA', to);
    assert_eq!(h.nft.get_stage(T1), 3_u8);

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    match h.nft_safe.consume_unit(T1, 'AWA', to) {
        Result::Ok(_) => panic!("expected BAD_STAGE"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'BAD_STAGE'); },
    }
}

#[test]
fn movement_freeze_is_per_movement() {
    let h = deploy_path_nft_default();
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(3));
    h.ac.grant_role(MINTER_ROLE, MINTER());
    h.nft.set_movement_config('THOUGHT', ALICE(), 1_u32);
    h.nft.set_movement_config('WILL', BOB(), 2_u32);

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    cheat_account_contract_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.nft.consume_unit(T1, 'THOUGHT', to);

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.nft.set_movement_config('WILL', ALICE(), 3_u32);
    assert_eq!(h.nft.get_authorized_minter('WILL'), ALICE());
    assert_eq!(h.nft.get_movement_quota('WILL'), 3_u32);
}
