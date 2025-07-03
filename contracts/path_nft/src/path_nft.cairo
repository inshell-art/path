// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

#[starknet::contract]
mod PathNFT {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::introspection::interface::ISRC5_ID;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::interface::{
        IERC721MetadataCamelOnly, IERC721_ID, IERC721_METADATA_ID,
    };
    use openzeppelin::token::erc721::{
        ERC721Component, ERC721HooksEmptyImpl, interface as ERC721Interface,
    };
    use starknet::storage::StoragePointerReadAccess;
    use starknet::{ContractAddress, get_caller_address};
    use crate::interface::IPathNFT;

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

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.erc721.initializer("Path", "PTH", "");
        self.ownable.initializer(owner);

        SRC5InternalImpl::register_interface(ref self.src5, IERC721_ID);
        SRC5InternalImpl::register_interface(ref self.src5, IERC721_METADATA_ID);
        SRC5InternalImpl::register_interface(ref self.src5, ISRC5_ID);
    }

    #[abi(embed_v0)]
    impl IPathNFTImpl of IPathNFT<ContractState> {
        fn burn(ref self: ContractState, token_id: u256) {
            self.erc721.update(Zero::zero(), token_id, get_caller_address());
        }

        fn safe_mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            self.ownable.assert_only_owner();
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
}
