// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

pub use PathNFT::Event as PathNFTEvent;
#[starknet::contract]
mod PathNFT {
    use core::num::traits::Zero;
    use core::panic_with_felt252;
    use openzeppelin::access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE};
    use openzeppelin::introspection::interface::ISRC5_ID;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::interface::{
        IERC721MetadataCamelOnly, IERC721_ID, IERC721_METADATA_ID,
    };
    use openzeppelin::token::erc721::{
        ERC721Component, ERC721HooksEmptyImpl, interface as ERC721Interface,
    };
    use path_interfaces::IPathNFT;
    use starknet::ContractAddress;
    use starknet::storage::StoragePointerReadAccess;

    const MINTER_ROLE: felt252 = selector!("MINTER_ROLE");

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    #[abi(embed_v0)]
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    component!(path: AccessControlComponent, storage: access_control, event: AccessControlEvent);
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        access_control: AccessControlComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        initial_admin: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
    ) {
        self.erc721.initializer(name, symbol, base_uri);
        self.access_control.initializer();
        if initial_admin.is_zero() {
            panic_with_felt252('ZERO_ADMIN')
        }
        self.access_control._grant_role(DEFAULT_ADMIN_ROLE, initial_admin);

        SRC5InternalImpl::register_interface(ref self.src5, IERC721_ID);
        SRC5InternalImpl::register_interface(ref self.src5, IERC721_METADATA_ID);
        SRC5InternalImpl::register_interface(ref self.src5, ISRC5_ID);
    }

    #[abi(embed_v0)]
    impl IPathNFTImpl of IPathNFT<ContractState> {
        fn burn(ref self: ContractState, token_id: u256) {
            let owner = self.erc721.owner_of(token_id);
            let caller = starknet::get_caller_address();
            if !self.erc721._is_authorized(owner, caller, token_id) {
                panic_with_felt252('ERR_NOT_OWNER');
            }
            self.erc721.burn(token_id);
        }

        fn safe_mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            self.access_control.assert_only_role(MINTER_ROLE);
            self.erc721.safe_mint(recipient, token_id, data);
        }

        fn safeMint(
            ref self: ContractState, recipient: ContractAddress, tokenId: u256, data: Span<felt252>,
        ) {
            self.safe_mint(recipient, tokenId, data);
        }
    }

    // External for token_uri
    #[abi(embed_v0)]
    impl PathMetadataIImpl of ERC721Interface::IERC721Metadata<ContractState> {
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.ERC721_symbol.read()
        }

        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._require_owned(token_id);
            let svg: ByteArray = build_svg(token_id);
            format!(
                "data:application/json,{{\"name\":\"$PATH NFT\",\"description\":\"Inshell PATH.\",\"image\":\"data:image/svg+xml,{svg}\"}}",
            )
        }
    }

    #[abi(embed_v0)]
    impl ERC721CamelMetadataImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.token_uri(tokenId)
        }
    }

    /// Builds: <svg …>$PATH NFT token_id: <id></text></svg>
    fn build_svg(token_id: u256) -> ByteArray {
        format!(
            "<?xml version='1.0' encoding='UTF-8'?><svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1000 1000'><text x='50' y='550' font-family='monospace' font-size='90'>$PATH NFT token_id: {}</text></svg>",
            token_id,
        )
    }
    #[cfg(test)]
    mod unit {
        #[test]
        fn minter_role_selector_is_stable() {
            let expected = selector!("MINTER_ROLE");
            assert_eq!(super::MINTER_ROLE, expected);
        }
    }
}

