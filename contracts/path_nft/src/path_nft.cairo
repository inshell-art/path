// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^1.0.0

pub use PathNFT::Event as PathNFTEvent;
#[starknet::contract]
mod PathNFT {
    use core::array::SpanTrait;
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
    use path_interfaces::{
        IPathLookDispatcher, IPathLookDispatcherTrait, IPathNFT,
    };
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

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
        path_look_addr: ContractAddress,
        thought_rank: Map<u256, u8>,
        will_rank: Map<u256, u8>,
        awa_rank: Map<u256, u8>,
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
        path_look_addr: ContractAddress,
    ) {
        self.erc721.initializer(name, symbol, base_uri);
        self.access_control.initializer();
        if initial_admin.is_zero() {
            panic_with_felt252('ZERO_ADMIN')
        }
        if path_look_addr.is_zero() {
            panic_with_felt252('ZERO_PATH_LOOK')
        }
        self.access_control._grant_role(DEFAULT_ADMIN_ROLE, initial_admin);
        self.path_look_addr.write(path_look_addr);

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
            store_movement_ranks(ref self, token_id, data);
            self.erc721.safe_mint(recipient, token_id, data);
        }

        fn safeMint(
            ref self: ContractState, recipient: ContractAddress, tokenId: u256, data: Span<felt252>,
        ) {
            self.safe_mint(recipient, tokenId, data);
        }

        fn set_path_look(ref self: ContractState, path_look: ContractAddress) {
            self.access_control.assert_only_role(DEFAULT_ADMIN_ROLE);
            if path_look.is_zero() {
                panic_with_felt252('ZERO_PATH_LOOK')
            }
            self.path_look_addr.write(path_look);
        }

        fn get_path_look(self: @ContractState) -> ContractAddress {
            self.path_look_addr.read()
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
            let look_addr = self.path_look_addr.read();
            if look_addr.is_zero() {
                panic_with_felt252('ZERO_PATH_LOOK')
            }
            // PathLook expects felt252; use the low limb as a stable seed.
            let token_seed = token_id.low.into();
            let thought = self.thought_rank.read(token_id);
            let will = self.will_rank.read(token_id);
            let awa = self.awa_rank.read(token_id);
            let look = IPathLookDispatcher { contract_address: look_addr };
            let metadata = look.get_token_metadata(token_seed, thought, will, awa);
            format!("data:application/json,{}", metadata)
        }
    }

    #[abi(embed_v0)]
    impl ERC721CamelMetadataImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.token_uri(tokenId)
        }
    }

    fn store_movement_ranks(
        ref self: ContractState, token_id: u256, data: Span<felt252>,
    ) {
        if data.len() < 3_usize {
            return;
        }
        let thought = rank_from_felt(*data.at(0_usize));
        let will = rank_from_felt(*data.at(1_usize));
        let awa = rank_from_felt(*data.at(2_usize));
        self.thought_rank.write(token_id, thought);
        self.will_rank.write(token_id, will);
        self.awa_rank.write(token_id, awa);
    }

    fn rank_from_felt(value: felt252) -> u8 {
        let rank: u8 = value.try_into().unwrap();
        if rank > 3_u8 {
            panic_with_felt252('BAD_RANK')
        }
        rank
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
