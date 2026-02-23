use starknet::ContractAddress;

#[starknet::interface]
pub trait IAdapterAdmin<T> {
    fn set_auction(ref self: T, auction: ContractAddress);
    fn set_minter(ref self: T, minter: ContractAddress);
    fn get_config(self: @T) -> (ContractAddress, ContractAddress); // (auction, minter)
}


#[starknet::contract]
mod PathMinterAdapter {
    use core::num::traits::Zero;
    use openzeppelin::access::ownable::OwnableComponent;
    use path_interfaces::{IPathMinterDispatcher, IPathMinterDispatcherTrait};
    use pulse_adapter::interface::IPulseAdapter;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ContractAddress, get_caller_address};
    use super::IAdapterAdmin;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        auction: ContractAddress,
        minter: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        AuctionSet: AuctionSet,
        MinterSet: MinterSet,
    }

    #[derive(Drop, starknet::Event)]
    struct AuctionSet {
        old: ContractAddress,
        new: ContractAddress,
    }
    #[derive(Drop, starknet::Event)]
    struct MinterSet {
        old: ContractAddress,
        new: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        auction: ContractAddress,
        minter: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.auction.write(auction);
        self.minter.write(minter);
    }


    #[abi(embed_v0)]
    impl Admin of IAdapterAdmin<ContractState> {
        fn set_auction(ref self: ContractState, auction: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!auction.is_zero(), 'ZERO_AUCTION');
            let old = self.auction.read();
            self.auction.write(auction);
            self.emit(AuctionSet { old, new: auction });
        }
        fn set_minter(ref self: ContractState, minter: ContractAddress) {
            self.ownable.assert_only_owner();
            assert(!minter.is_zero(), 'ZERO_MINTER');
            let old = self.minter.read();
            self.minter.write(minter);
            self.emit(MinterSet { old, new: minter });
        }
        fn get_config(self: @ContractState) -> (ContractAddress, ContractAddress) {
            (self.auction.read(), self.minter.read())
        }
    }

    // --- Pulse adapter ABI (called by PulseAuction) ---
    #[abi(embed_v0)]
    impl Adapter of IPulseAdapter<ContractState> {
        fn settle(ref self: ContractState, buyer: ContractAddress, data: Span<felt252>) -> u256 {
            // hard gate: only the registered auction can settle
            assert(get_caller_address() == self.auction.read(), 'ONLY_AUCTION');

            let minter = IPathMinterDispatcher { contract_address: self.minter.read() };
            minter.mint_public(buyer, data)
        }
        fn target(self: @ContractState) -> ContractAddress {
            self.auction.read()
        }
    }
}
