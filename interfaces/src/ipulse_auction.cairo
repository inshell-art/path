use starknet::ContractAddress;

// --- Supporting Structs (Define here or in a shared types module) ---

// Read-only parameters of the auction
#[derive(Copy, Drop, Serde)] // Serde needed if returned from external fn
pub struct AuctionParameters {
    bid_token: ContractAddress,
    beneficiary: ContractAddress,
    price_drop_per_second: u256,
    floor_price: u256,
}

// Read-only outcome of a completed beat
#[derive(Copy, Drop, Serde)]
pub struct BeatOutcome {
    winner: ContractAddress,
    price: u256,
    timestamp: u64, // When beat was won
    claimed: bool, // As tracked by the auction contract (optional redundancy)
}

// --- The Interface Trait ---

#[starknet::interface]
pub trait IPulseAuction<TContractState> {
    // --- Bidding Function ---
    /// Places a bid at the current price, winning the current beat if successful.
    /// Requires prior ERC20 approval of the bid_token for the current price.
    /// Emits BeatWon event on success.
    fn bid(ref self: TContractState);

    // --- View Functions (for Bidders, UI, Minters) ---
    /// Gets the current calculated price for the ongoing beat.
    fn get_current_price(self: @TContractState) -> u256;
    /// Gets the static parameters of the auction.
    fn get_auction_parameters(self: @TContractState) -> AuctionParameters;
    /// Gets the outcome details of a previously completed beat (winner, price, claimed status).
    /// Returns None if beat_id is invalid or not yet won.
    fn get_beat_outcome(self: @TContractState, beat_id: u64) -> Option<BeatOutcome>;
    /// Gets the ID that will be assigned to the *next* beat winner upon a successful bid.
    fn get_next_beat_id(self: @TContractState) -> u64;

    // --- Claiming Verification (for PathMinter) ---
    /// Checks if potential_winner won beat_id and it hasn't been marked as claimed *by the minter*.
    /// NOTE: Relies on the auction contract's internal 'beat_claimed' status.
    fn is_eligible_to_claim(self: @TContractState, beat_id: u64, potential_winner: ContractAddress) -> bool;

    // --- Admin Functions (callable by Ownable owner, requires Ownable Component) ---
    /// Updates auction parameters. Pass None for parameters not being changed.
    /// Needs OwnableComponent setup in the implementing contract.
    fn set_parameters(
         ref self: TContractState,
         new_drop_per_sec: Option<u256>,
         new_floor_price: Option<u256>,
         new_beneficiary: Option<ContractAddress>,
         new_minter_address: Option<ContractAddress>
    );
    // Could also expose owner() from OwnableComponent here if desired
    // fn owner(self: @TContractState) -> ContractAddress;
}