use starknet::ContractAddress;

#[starknet::interface]
pub trait IPulseAuction<TContractState> {
    fn is_eligible_to_claim(
        self: @TContractState,
        auction_id: u64,
        potential_winner: ContractAddress,
    ) -> felt252;
 
}