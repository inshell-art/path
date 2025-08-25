use core::array::ArrayTrait;
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait, IAccessControlSafeDispatcher,
    IAccessControlSafeDispatcherTrait,
};
use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
use openzeppelin::introspection::interface::{ISRC5Dispatcher, ISRC5DispatcherTrait, ISRC5_ID};
use openzeppelin::token::erc721::ERC721Component;
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721DispatcherTrait, IERC721MetadataCamelOnlyDispatcher,
    IERC721MetadataCamelOnlyDispatcherTrait, IERC721MetadataDispatcher,
    IERC721MetadataDispatcherTrait, IERC721SafeDispatcher, IERC721SafeDispatcherTrait, IERC721_ID,
    IERC721_METADATA_ID,
};
use path_interfaces::{
    IPathNFTDispatcher, IPathNFTDispatcherTrait, IPathNFTSafeDispatcher,
    IPathNFTSafeDispatcherTrait,
};
use path_nft::path_nft::PathNFTEvent;
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, cheat_caller_address, declare,
    spy_events,
};
use starknet::ContractAddress;

//
// Setup
//

fn NAME() -> ByteArray {
    "PATH NFT"
}
fn SYMBOL() -> ByteArray {
    "PATH"
}
fn BASE_URI() -> ByteArray {
    ""
} // PathNFT builds JSON+SVG; no need for base URI

fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}
fn MINTER() -> ContractAddress {
    'MINTER'.try_into().unwrap()
}
fn ALICE() -> ContractAddress {
    'ALICE'.try_into().unwrap()
}
fn BOB() -> ContractAddress {
    'BOB'.try_into().unwrap()
}

const T1: u256 = 1_u256;
const T2: u256 = 777_u256;
const minter_role: felt252 = selector!("MINTER_ROLE");

fn ZERO_ADDR() -> ContractAddress {
    0.try_into().unwrap()
}

#[starknet::contract]
mod TestERC721Receiver {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721ReceiverComponent;

    component!(path: ERC721ReceiverComponent, storage: erc721_receiver, event: ERC721ReceiverEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721ReceiverImpl =
        ERC721ReceiverComponent::ERC721ReceiverImpl<ContractState>;
    impl ERC721ReceiverInternalImpl = ERC721ReceiverComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_receiver: ERC721ReceiverComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721ReceiverEvent: ERC721ReceiverComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc721_receiver.initializer();
    }
}

//
// Helpers
//
#[derive(Drop)]
struct Handles {
    addr: ContractAddress,
    nft: IPathNFTDispatcher,
    nft_safe: IPathNFTSafeDispatcher,
    erc721: IERC721Dispatcher,
    erc721_safe: IERC721SafeDispatcher,
    meta: IERC721MetadataDispatcher,
    camel_meta: IERC721MetadataCamelOnlyDispatcher,
    src5: ISRC5Dispatcher,
    ac: IAccessControlDispatcher,
}

fn deploy_path_nft(admin: ContractAddress) -> Handles {
    let class = declare("PathNFT").unwrap().contract_class();

    let mut calldata = ArrayTrait::new();
    admin.serialize(ref calldata);
    NAME().serialize(ref calldata);
    SYMBOL().serialize(ref calldata);
    BASE_URI().serialize(ref calldata);

    let (addr, _) = class.deploy(@calldata).unwrap();

    Handles {
        addr,
        nft: IPathNFTDispatcher { contract_address: addr },
        nft_safe: IPathNFTSafeDispatcher { contract_address: addr },
        erc721: IERC721Dispatcher { contract_address: addr },
        erc721_safe: IERC721SafeDispatcher { contract_address: addr },
        meta: IERC721MetadataDispatcher { contract_address: addr },
        camel_meta: IERC721MetadataCamelOnlyDispatcher { contract_address: addr },
        src5: ISRC5Dispatcher { contract_address: addr },
        ac: IAccessControlDispatcher { contract_address: addr },
    }
}

fn deploy_receiver() -> ContractAddress {
    let class = declare("TestERC721Receiver").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

//
// gl_* (global)
//

#[test]
fn gl_constructor_registers_interfaces_and_sets_metadata() {
    let h = deploy_path_nft(ADMIN());
    assert_eq!(h.meta.name(), NAME());
    assert_eq!(h.meta.symbol(), SYMBOL());

    assert!(h.src5.supports_interface(IERC721_ID));
    assert!(h.src5.supports_interface(IERC721_METADATA_ID));
    assert!(h.src5.supports_interface(ISRC5_ID));
}

#[test]
fn gl_camelcase_aliases_are_wired() {
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safeMint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);

    let snake = h.meta.token_uri(T1);
    let camel = h.camel_meta.tokenURI(T1);
    assert_eq!(snake, camel);
}

#[test]
fn gl_supports_interface_false_for_unknown() {
    let h = deploy_path_nft(ADMIN());
    let unknown: felt252 = 'NO_IFACE';
    assert!(!h.src5.supports_interface(unknown));
}

//
// ac_* (access control)
//

#[test]
fn ac_admin_and_minter_roles_bootstrap_ok() {
    let h = deploy_path_nft(ADMIN());
    let ac = IAccessControlDispatcher { contract_address: h.addr };

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

    assert!(ac.has_role(DEFAULT_ADMIN_ROLE, ADMIN()));
    assert!(ac.has_role(minter_role, MINTER()));
    assert!(!ac.has_role(minter_role, ALICE()));
}

#[test]
#[feature("safe_dispatcher")]
fn ac_admin_cannot_mint_without_minter_role() {
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    // ADMIN is DEFAULT_ADMIN_ROLE, but not MINTER_ROLE
    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(to, T1, array![].span()) {
        Result::Ok(_) => panic!("ADMIN should not be able to mint without MINTER_ROLE"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

    // MINTER can mint (sanity)
    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());
    assert_eq!(h.erc721.owner_of(T1), to);
}

#[test]
#[feature("safe_dispatcher")]
fn ac_admin_grant_and_revoke_minter_emits_events_and_changes_effect() {
    let h = deploy_path_nft(ADMIN());
    let ac = IAccessControlDispatcher { contract_address: h.addr };
    let minter_role = selector!("MINTER_ROLE");
    let to = deploy_receiver();

    // --- Grant MINTER to ALICE (admin-only) + event
    let mut spy = spy_events();
    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    ac.grant_role(minter_role, ALICE());

    let granted: PathNFTEvent = PathNFTEvent::AccessControlEvent(
        AccessControlComponent::Event::RoleGranted(
            AccessControlComponent::RoleGranted {
                role: minter_role, account: ALICE(), sender: ADMIN(),
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
    ac.revoke_role(minter_role, ALICE());

    let revoked: PathNFTEvent = PathNFTEvent::AccessControlEvent(
        AccessControlComponent::Event::RoleRevoked(
            AccessControlComponent::RoleRevoked {
                role: minter_role, account: ALICE(), sender: ADMIN(),
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
    let h = deploy_path_nft(ADMIN());
    let acs = IAccessControlSafeDispatcher { contract_address: h.addr };
    let minter_role = selector!("MINTER_ROLE");

    // Non-admin tries to grant
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match acs.grant_role(minter_role, ALICE()) {
        Result::Ok(_) => panic!("non-admin granting MINTER should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }

    // Non-admin tries to revoke (even from a real minter)
    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    match acs.revoke_role(minter_role, MINTER()) {
        Result::Ok(_) => panic!("non-admin revoking MINTER should revert"),
        Result::Err(panic_data) => { assert_eq!(*panic_data.at(0), 'Caller is missing role') },
    }
}

//
// mint_* (minting)
//

#[test]
#[feature("safe_dispatcher")]
fn mint_duplicate_token_id_reverts() {
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ALICE(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(to, T1, array![].span()) {
        Result::Ok(_) => panic!("expected revert: non-minter mint"),
        Result::Err(_panic_data) => {},
    }

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    match h.nft_safe.safe_mint(ZERO_ADDR(), T1, array![].span()) {
        Result::Ok(_) => panic!("mint to zero should revert"),
        Result::Err(_) => {},
    }
}

#[test]
fn mint_remint_after_burn_works() {
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());

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
    let h: Handles = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

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
    let h = deploy_path_nft(ADMIN());
    let to = deploy_receiver();

    cheat_caller_address(h.addr, ADMIN(), CheatSpan::TargetCalls(1));
    h.ac.grant_role(minter_role, MINTER());

    cheat_caller_address(h.addr, MINTER(), CheatSpan::TargetCalls(1));
    h.nft.safe_mint(to, T1, array![].span());

    cheat_caller_address(h.addr, to, CheatSpan::TargetCalls(1));
    h.erc721.set_approval_for_all(BOB(), true);

    cheat_caller_address(h.addr, BOB(), CheatSpan::TargetCalls(1));
    h.nft.burn(T1);

    assert_eq!(h.erc721.balance_of(to), 0_u256);
}
