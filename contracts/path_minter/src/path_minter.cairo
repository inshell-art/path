//! PathMinter – shared mint proxy for PathNFT
//!
//! * One contract holds the NFT's `MINTER_ROLE` and exposes a thin façade
//!   (`mint_single`, `mint_batch`, `drop_mint`) that any authorised sales
//!   engine can call (PulseAuction, Dutch auction, bridge, airdrop script …).
//! * Granular `SALES_ROLE` limits callers to **mint‑only** functions; the
//!   NFT logic and treasury remain elsewhere.
//! * Upgradable/pausable by the project owner via OpenZeppelin AccessControl.
//!
//! ## Storage layout
//! | Field       | Meaning                                      |
//! |-------------|----------------------------------------------|
//! | access      | OZ AccessControl component                   |
//! | path        | Address of the PathNFT contract              |
//! | next_id     | Counter for the next tokenId to mint         |
//!
//! ## Roles
//! | Constant        | Who should hold it                |
//! |-----------------|------------------------------------|
//! | DEFAULT_ADMIN   | DAO multisig / time lock           |
//! | SALES_ROLE      | PulseAuction + 3 extra sale engines|
//! | MINTER_ROLE_NFT | Granted **to this contract** on PathNFT |

#[starknet::contract]
mod PathMinter {
    use core::integer::u256;

    // ----------------------- Imports -----------------------
    use openzeppelin::access::accesscontrol::AccessControlComponent;
    use openzeppelin::access::accesscontrol::DEFAULT_ADMIN_ROLE;
    use openzeppelin::access::accesscontrol::interface::IAccessControlDispatcherTrait;
    use openzeppelin::introspection::interface::ISRC5_ID;
    use openzeppelin::introspection::src5::SRC5Component;
    use path_nft::i_path_nft::{IPathNFTDispatcher, IPathNFTDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    // ----------------------- Constants ---------------------
    /// Role that allows a contract to call the public mint helpers
    const SALES_ROLE: felt252 = selector!("SALES_ROLE");

    // ----------------------- Components --------------------
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    component!(path: AccessControlComponent, storage: access, event: AccessEvent);
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    // ----------------------- Storage -----------------------
    #[storage]
    struct Storage {
        #[substorage(v0)]
        access: AccessControlComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// Path NFT collection address
        path_nft_addr: ContractAddress,
        /// Next token id to mint (sequential schema)
        next_id: u256,
    }

    // ----------------------- Events ------------------------
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    // ----------------------- Constructor -------------------
    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        path_nft_addr: ContractAddress,
        first_token_id: u256,
    ) {
        // Set up AccessControl (caller is temporary admin until transferred).
        self.access.initializer();

        // Transfer admin role to the provided admin address
        self.access._grant_role(DEFAULT_ADMIN_ROLE, admin);
        self.access._revoke_role(DEFAULT_ADMIN_ROLE, starknet::get_caller_address());

        // Record PathNFT address & starting id
        self.path_nft_addr.write(path_nft_addr);
        self.next_id.write(first_token_id);

        // Acquire mint power on PathNFT (one‑time).
        let path_ac = IAccessControlDispatcher { contract_address: path_addr };
        path_ac.grant_role(MINTER_ROLE_NFT, ContractAddress::from_const());

        SRC5InternalImpl::register_interface(ref self.src5, ISRC5_ID);
    }

    // ----------------------- External API ------------------
    #[abi(embed_v0)]
    impl PathMinterInterface of self::internal::InternalPathMinter<ContractState> {
        /// Mint a single token – used by PulseAuction.
        fn mint_single(ref self: ContractState, to: ContractAddress, data: Span<felt252>) {
            self.assert_only_role(SALES_ROLE);
            self._mint_internal(to, data);
        }

        /// Batch mint – can be used for reserves / airdrops.
        fn mint_batch(ref self: ContractState, tos: Span<ContractAddress>) {
            self.assert_only_role(SALES_ROLE);
            for address in tos.iter() {
                self._mint_internal(*address, array![].span());
            }
        }

        /// Admin‑only helper to add a new sales engine.
        fn grant_sales_role(ref self: ContractState, sales: ContractAddress) {
            self.assert_only_role(DEFAULT_ADMIN_ROLE);
            self._grant_role(SALES_ROLE, sales);
        }

        /// Admin‑only helper to revoke a sales engine.
        fn revoke_sales_role(ref self: ContractState, sales: ContractAddress) {
            self.assert_only_role(DEFAULT_ADMIN_ROLE);
            self._revoke_role(SALES_ROLE, sales);
        }

        /// View next token id (debug / UI helper)
        fn next_token_id(self: @ContractState) -> u256 {
            self.next_id.read()
        }
    }

    // ----------------------- Internal helpers --------------
    mod internal {
        use super::*;
        /// Common mint logic
        fn _mint_internal(ref self: ContractState, to: ContractAddress, data: Span<felt252>) {
            let id = self.next_id.read();
            let nft = IPathNFTDispatcher { contract_address: self.path.read() };
            nft.safe_mint(to, id, data);
            self.next_id.write(id + 1);
        }
    }
}
