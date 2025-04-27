#[starknet::contract]
mod PathMinter {
    use pulse::interfaces::IPulseAuction;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        pulse_addr: ContractAddress,
    }

    #[constructor]
    fn constructor(self: ContractState, pulse_addr: ContractAddress) {
        self.pulse_addr.write(pulse_addr);
    }


    #[external(v0)]
    fn current_price(self: @ContractState, auction_id: u64) -> u256 {
        let pulse_addr = self.pulse_addr.read();
        let price = IPulseAuction::get_current_price(pulse_addr, auction_id);
        return price;
    }
}
