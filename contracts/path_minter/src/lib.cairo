// contracts/path_minter/src/lib.cairo

#[starknet::contract]
mod PathMinter {
    // --- Imports ---
    use starknet::{ContractAddress, get_caller_address};
    
    // --- Import Interfaces from shared package ---
    // Assumes an 'interfaces' package exists at '../../interfaces' relative to this file's package
    use interfaces::ipath_nft::{IPathNFTDispatcher, IPathNFTDispatcherTrait};
    use interfaces::ipulse_auction::{IPulseAuctionDispatcher, IPulseAuctionDispatcherTrait};

    // --- Constants for Error Messages ---
    mod Errors {
        const ALREADY_CLAIMED: felt252 = 'Minter: Item already claimed';
        const NOT_ELIGIBLE: felt252 = 'PathMinter: Not eligible winner';
    }

    // --- Storage ---
    #[storage]
    struct Storage {
        // Address of the PathNFT contract this minter controls
        path_nft_address: ContractAddress,
        // Address of the Pulse Auction contract to verify winners
        pulse_auction_address: ContractAddress,
        // Counter for the next PathNFT token ID to be minted
        next_token_id: u256,
        // Mapping to track if an auction prize has been claimed
        // Key: auction_id (u64), Value: claimed (bool)
        claimed_auctions: LegacyMap<u64, bool>,
    }

    // --- Events ---
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PathNftClaimed: PathNftClaimed,
        // Add other events if needed
    }

    #[derive(Drop, starknet::Event)]
    struct PathNftClaimed {
        #[key]
        auction_id: u64,
        #[key]
        winner: ContractAddress,
        token_id: u256,
    }

    // --- Constructor ---
    #[constructor]
    fn constructor(
        ref self: ContractState,
        path_nft_addr: ContractAddress,    // Address of the deployed PathNFT contract
        pulse_auction_addr: ContractAddress, // Address of the deployed PulseAuction contract
        start_token_id: u256           // The first token ID this minter should issue
    ) {
        // Set immutable addresses
        self.path_nft_address.write(path_nft_addr);
        self.pulse_auction_address.write(pulse_auction_addr);
        // Initialize the token ID counter
        self.next_token_id.write(start_token_id);
        // Note: claimed_auctions map starts empty (default is false/0)
    }

    // --- External Functions ---

    /// Allows the verified winner of a Pulse Auction to claim their Path NFT.
    #[external(v0)]
    fn claim_nft_for_auction(ref self: ContractState, auction_id: u64) {
        let caller_address = get_caller_address();

        // --- 1. Checks ---
        // Ensure this auction prize hasn't been claimed yet
        let already_claimed = self.claimed_auctions.read(auction_id);
        assert(!already_claimed, Errors::ALREADY_CLAIMED);

        // Verify with the Pulse Auction contract that the caller is eligible
        let auction_dispatcher = IPulseAuctionDispatcher {
            contract_address: self.pulse_auction_address.read()
        };
        let is_eligible = auction_dispatcher.is_eligible_to_claim(auction_id, caller_address);
        assert(is_eligible, Errors::NOT_ELIGIBLE);

        // --- 2. Effects (Update State BEFORE external mint call) ---
        // Determine the token ID for the new NFT
        let token_id_to_mint = self.next_token_id.read();

        // Mark this auction as claimed to prevent double minting
        self.claimed_auctions.write(auction_id, true);
        // Increment the counter for the next mint
        self.next_token_id.write(token_id_to_mint + 1_u256);

        // --- 3. Interaction ---
        // Call the mint function on the PathNFT contract
        // (Assumes this PathMinter contract is the owner of PathNFT)
        let path_nft_dispatcher = IPathNFTDispatcher {
            contract_address: self.path_nft_address.read()
        };
        // Mint the token directly to the auction winner (the caller)
        path_nft_dispatcher.mint(recipient: caller_address, token_id: token_id_to_mint);

        // --- 4. Emit Event ---
        self.emit(
            PathNftClaimed { auction_id: auction_id, winner: caller_address, token_id: token_id_to_mint }
        );
    }

    // --- Optional View Functions ---

    #[external(v0)]
    fn get_path_nft_address(self: @ContractState) -> ContractAddress {
        self.path_nft_address.read()
    }

    #[external(v0)]
    fn get_pulse_auction_address(self: @ContractState) -> ContractAddress {
        self.pulse_auction_address.read()
    }

    #[external(v0)]
    fn get_next_token_id(self: @ContractState) -> u256 {
        self.next_token_id.read()
    }

    #[external(v0)]
    fn has_auction_been_claimed(self: @ContractState, auction_id: u64) -> bool {
        self.claimed_auctions.read(auction_id)
    }
}