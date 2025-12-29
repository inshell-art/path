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
    use path_interfaces::{IPathLookDispatcher, IPathLookDispatcherTrait, IPathNFT};
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };

    const MINTER_ROLE: felt252 = selector!("MINTER_ROLE");
    const MOVEMENT_THOUGHT: felt252 = 'THOUGHT';
    const MOVEMENT_WILL: felt252 = 'WILL';
    const MOVEMENT_AWA: felt252 = 'AWA';

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
        stage: Map<u256, u8>,
        stage_minted: Map<u256, u32>,
        movement_quota: Map<felt252, u32>,
        movement_frozen: Map<felt252, bool>,
        authorized_minter: Map<felt252, ContractAddress>,
    }

    #[derive(Drop, starknet::Event)]
    struct MovementConsumed {
        path_token_id: u256,
        movement: felt252,
        claimer: ContractAddress,
        serial: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct MovementFrozen {
        movement: felt252,
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
        MovementConsumed: MovementConsumed,
        MovementFrozen: MovementFrozen,
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
            self.erc721.safe_mint(recipient, token_id, data);
            self.stage.write(token_id, 0_u8);
            self.stage_minted.write(token_id, 0_u32);
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

        fn set_authorized_minter(
            ref self: ContractState, movement: felt252, minter: ContractAddress,
        ) {
            self.access_control.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert_valid_movement(movement);
            if self.movement_frozen.read(movement) {
                panic_with_felt252('MOVEMENT_FROZEN')
            }
            if minter.is_zero() {
                panic_with_felt252('ZERO_MINTER')
            }
            self.authorized_minter.write(movement, minter);
        }

        fn get_authorized_minter(self: @ContractState, movement: felt252) -> ContractAddress {
            self.authorized_minter.read(movement)
        }

        fn get_stage(self: @ContractState, token_id: u256) -> u8 {
            self.erc721._require_owned(token_id);
            self.stage.read(token_id)
        }

        fn get_stage_minted(self: @ContractState, token_id: u256) -> u32 {
            self.erc721._require_owned(token_id);
            self.stage_minted.read(token_id)
        }

        fn set_movement_quota(ref self: ContractState, movement: felt252, quota: u32) {
            self.access_control.assert_only_role(DEFAULT_ADMIN_ROLE);
            assert_valid_movement(movement);
            if self.movement_frozen.read(movement) {
                panic_with_felt252('MOVEMENT_FROZEN')
            }
            if quota == 0_u32 {
                panic_with_felt252('ZERO_QUOTA')
            }
            self.movement_quota.write(movement, quota);
        }

        fn get_movement_quota(self: @ContractState, movement: felt252) -> u32 {
            self.movement_quota.read(movement)
        }

        fn consume_movement_unit(
            ref self: ContractState,
            path_token_id: u256,
            movement: felt252,
            claimer: ContractAddress,
        ) -> u32 {
            assert_valid_movement(movement);
            let authorized = self.authorized_minter.read(movement);
            let caller = starknet::get_caller_address();
            if authorized.is_zero() || caller != authorized {
                panic_with_felt252('ERR_UNAUTHORIZED_MINTER');
            }

            let tx = starknet::get_tx_info().unbox();
            if claimer != tx.account_contract_address {
                panic_with_felt252('BAD_CLAIMER');
            }

            let owner = self.erc721.owner_of(path_token_id);
            if !self.erc721._is_authorized(owner, claimer, path_token_id) {
                panic_with_felt252('ERR_NOT_OWNER');
            }

            let current = self.stage.read(path_token_id);
            let expected = expected_movement_for_stage(current);
            if movement != expected {
                panic_with_felt252('BAD_MOVEMENT_ORDER');
            }

            if !self.movement_frozen.read(movement) {
                self.movement_frozen.write(movement, true);
                self.emit(MovementFrozen { movement });
            }

            let quota = self.movement_quota.read(movement);
            if quota == 0_u32 {
                panic_with_felt252('ZERO_QUOTA');
            }

            let minted = self.stage_minted.read(path_token_id);
            if minted >= quota {
                panic_with_felt252('QUOTA_EXHAUSTED');
            }

            let serial = minted;
            let minted_next = minted + 1_u32;
            if minted_next == quota {
                self.stage.write(path_token_id, current + 1_u8);
                self.stage_minted.write(path_token_id, 0_u32);
            } else {
                self.stage_minted.write(path_token_id, minted_next);
            }

            self.emit(MovementConsumed { path_token_id, movement, claimer, serial });
            serial
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
            let look = IPathLookDispatcher { contract_address: look_addr };
            let metadata = look.get_token_metadata(starknet::get_contract_address(), token_id);
            format!("data:application/json,{}", metadata)
        }
    }

    #[abi(embed_v0)]
    impl ERC721CamelMetadataImpl of IERC721MetadataCamelOnly<ContractState> {
        fn tokenURI(self: @ContractState, tokenId: u256) -> ByteArray {
            self.token_uri(tokenId)
        }
    }

    fn assert_valid_movement(movement: felt252) {
        if movement != MOVEMENT_THOUGHT && movement != MOVEMENT_WILL && movement != MOVEMENT_AWA {
            panic_with_felt252('BAD_MOVEMENT')
        }
    }

    fn expected_movement_for_stage(stage: u8) -> felt252 {
        if stage == 0_u8 {
            return MOVEMENT_THOUGHT;
        }
        if stage == 1_u8 {
            return MOVEMENT_WILL;
        }
        if stage == 2_u8 {
            return MOVEMENT_AWA;
        }
        panic_with_felt252('BAD_STAGE')
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
