// SPDX-License-Identifier: MIT
// $PATH Minter: shared mint proxy for PathNFT

/// # PathMinter Contract
/// This contract is a minting proxy for the PathNFT collection.
/// It allows for minting NFTs with specific roles and provides a reserved pool for
/// path sparkers.
/// It is designed to be used in conjunction with the PathNFT contract,
/// which handles the actual NFT logic.
///
/// ## Public Minting
/// The public minting function allows users to mint NFTs by calling the `mint_public`
/// method. This method requires the caller to hold the `SALES_ROLE` role.
/// It mints a new NFT with a sequential token ID, starting from the `first_token_id`
/// specified during contract deployment. The token ID is incremented after each minting.
/// is sold out.
///
/// ## Reserved Minting
/// The reserved minting function allows for minting NFTs from a reserved pool.
/// This is intended for path sparkers and requires the caller to hold the `RESERVED_ROLE`
/// role.

#[starknet::contract]
mod PathMinter {
    use core::integer::u256;
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::interface::ISRC5_ID;
    use openzeppelin::introspection::src5::SRC5Component;
    use path_interfaces::{IPathMinter, IPathNFTDispatcher, IPathNFTDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    /// Role that call to mint_single, sales engines, like PulseAuction
    const SALES_ROLE: felt252 = selector!("SALES_ROLE");
    /// Role that call to mint_reserved, internal management
    const RESERVED_ROLE: felt252 = selector!("RESERVED_ROLE");
    /// The maximum value for a 256-bit unsigned integer minus one.
    /// This is used to calculate the reserved token IDs in descending order.
    const MAX_MINUS_ONE: u256 = u256 {
        // 128-bit halves written in hex for clarity
        low: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE, high: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
    };

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    component!(path: AccessControlComponent, storage: access, event: AccessEvent);
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

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
        /// Reserved minting counter
        reserved_cap: u64,
        reserved_remaining: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        AccessEvent: AccessControlComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin: ContractAddress,
        path_nft_addr: ContractAddress,
        first_token_id: u256,
        reserved_cap: u64,
    ) {
        // Set up AccessControl (caller is temporary admin until transferred).
        self.access.initializer();

        // Transfer admin role to the provided admin address
        self.access._grant_role(DEFAULT_ADMIN_ROLE, admin);

        // Set up the initial state
        self.path_nft_addr.write(path_nft_addr);
        self.next_id.write(first_token_id);
        self.reserved_cap.write(reserved_cap);
        self.reserved_remaining.write(reserved_cap);

        SRC5InternalImpl::register_interface(ref self.src5, ISRC5_ID);
    }

    #[abi(embed_v0)]
    impl IPathMinterImpl of IPathMinter<ContractState> {
        /// View the reserved cap for minting.
        fn get_reserved_cap(ref self: ContractState) -> u64 {
            self.reserved_cap.read()
        }

        /// View the remaining reserved NFTs that can be minted.
        fn get_reserved_remaining(ref self: ContractState) -> u64 {
            self.reserved_remaining.read()
        }

        /// Public mint
        /// - Caller must hold `SALES_ROLE`
        /// - Returns the `tokenId` just minted
        fn mint_public(ref self: ContractState, to: ContractAddress, data: Span<felt252>) -> u256 {
            self.access.assert_only_role(SALES_ROLE);
            let id = self.next_id.read();
            _mint_to_nft(ref self, to, id, data);
            self.next_id.write(id + 1); // Increment the next token ID

            id
        }

        /// Reserved-pool mint (up to `reserved_cap` tokens) for path sparkers
        /// - Caller must hold `RESERVED_ROLE`.
        /// - Reverts once every reserved token has been issued.
        /// - Returns the `tokenId` just minted (2^256 - 2 … 2^256 - reserved_cap).
        //todo: consider the role and the data content to mint latter
        fn mint_sparker(ref self: ContractState, to: ContractAddress, data: Span<felt252>) -> u256 {
            self.access.assert_only_role(RESERVED_ROLE);

            let remaining = self.reserved_remaining.read(); // u64
            assert(remaining > 0, 'NO_RESERVED_LEFT');

            let minted_so_far: u64 = self.reserved_cap.read() - remaining;
            let id: u256 = MAX_MINUS_ONE - minted_so_far.into();

            _mint_to_nft(ref self, to, id, data);

            self.reserved_remaining.write(remaining - 1);

            id
        }
    }

    // ----------------------- Internal helpers --------------
    /// Common mint logic
    fn _mint_to_nft(ref self: ContractState, to: ContractAddress, id: u256, data: Span<felt252>) {
        let nft = IPathNFTDispatcher { contract_address: self.path_nft_addr.read() };
        nft.safe_mint(to, id, data);
    }

    // ----------------------- Tests --------------------------
    #[cfg(test)]
    mod tests {
        use core::num::traits::Bounded;
        use super::*;

        #[test]
        fn max_minus_one_is_biggest_minus_one() {
            let max_u128 = Bounded::<u128>::MAX;
            assert(MAX_MINUS_ONE.high == max_u128, 'high half');
            assert(MAX_MINUS_ONE.low == max_u128 - 1, 'low half');
        }
    }
}
