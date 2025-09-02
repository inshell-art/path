use core::array::ArrayTrait;
use openzeppelin::token::erc721::interface::{IERC721Dispatcher, IERC721MetadataDispatcher};
use path_interfaces::interfaces::{IPathMinterDispatcher, IPathNFTDispatcher};
use path_minter_adapter::path_minter_adapter::{
    IAdapterAdminDispatcher, IAdapterAdminDispatcherTrait,
};
use pulse_adapter::interface::{IPulseAdapterDispatcher, IPulseAdapterSafeDispatcher};
use pulse_auction::interface::{IPulseAuctionDispatcher, IPulseAuctionSafeDispatcher};
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
use starknet::ContractAddress;

#[derive(Drop)]
pub struct Env {
    pub nft_addr: ContractAddress,
    pub minter_addr: ContractAddress,
    pub adapter_addr: ContractAddress,
    pub auction_addr: ContractAddress,
    pub nft: IPathNFTDispatcher,
    pub erc721: IERC721Dispatcher,
    pub meta: IERC721MetadataDispatcher,
    pub minter: IPathMinterDispatcher,
    pub adapter: IPulseAdapterDispatcher,
    pub adapter_safe: IPulseAdapterSafeDispatcher,
    pub adapter_admin: IAdapterAdminDispatcher,
    pub auction: IPulseAuctionDispatcher,
    pub auction_safe: IPulseAuctionSafeDispatcher,
}

/// simple addresses for tests
fn ZERO() -> ContractAddress {
    0.try_into().unwrap()
}
fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}
fn MINTER() -> ContractAddress {
    'MINTER'.try_into().unwrap()
}
fn ALICE() -> ContractAddress {
    'ALICE'.try_into().unwrap()
}

/// constants you likely have — adjust to your Path config
const FIRST_PUBLIC_ID: u256 = 1000_u128.into();

/// Deploy PathNFT, PathMinter, Adapter, Auction and wire them up
pub fn deploy_env() -> Env {
    // --- NFT
    let nft_class = declare("PathNFT").unwrap().contract_class();
    let (nft_addr, _) = nft_class
        .deploy(
            @{
                let mut cd = ArrayTrait::new();
                ADMIN().serialize(ref cd); // admin
                MINTER().serialize(ref cd); // initial minter (will use PathMinter later)
                'PATH'.serialize(ref cd); // NAME()
                'PATH'.serialize(ref cd); // SYMBOL()
                ''.serialize(ref cd); // BASE_URI()
                cd
            },
        )
        .unwrap();
    let nft = IPathNFTDispatcher { contract_address: nft_addr };
    let erc721 = IERC721Dispatcher { contract_address: nft_addr };
    let meta = IERC721MetadataDispatcher { contract_address: nft_addr };

    // --- Minter
    let minter_class = declare("PathMinter").unwrap().contract_class();
    let (minter_addr, _) = minter_class
        .deploy(
            @{
                let mut cd = ArrayTrait::new();
                nft_addr.serialize(ref cd);
                FIRST_PUBLIC_ID.serialize(ref cd);
                0_u128.serialize(ref cd); // RESERVED_CAP, adjust
                cd
            },
        )
        .unwrap();
    let minter = IPathMinterDispatcher { contract_address: minter_addr };

    // --- Adapter (PathMinterAdapter)
    let adapter_class = declare("PathMinterAdapter").unwrap().contract_class();
    let (adapter_addr, _) = adapter_class
        .deploy(
            @{
                let mut cd = ArrayTrait::new();
                ZERO().serialize(ref cd); // auction (unknown yet)
                minter_addr.serialize(ref cd); // minter
                cd
            },
        )
        .unwrap();
    let adapter = IPulseAdapterDispatcher { contract_address: adapter_addr };
    let adapter_safe = IPulseAdapterSafeDispatcher { contract_address: adapter_addr };
    let adapter_admin = IAdapterAdminDispatcher { contract_address: adapter_addr };

    // --- Auction (PulseAuction)
    let auction_class = declare("PulseAuction").unwrap().contract_class();
    let (auction_addr, _) = auction_class
        .deploy(
            @{
                let mut cd = ArrayTrait::new();
                0_u64.serialize(ref cd); // start_delay_sec
                10_000_u128.into().serialize(ref cd); // K (example)
                1_000_u128.into().serialize(ref cd); // GENESIS_PRICE
                800_u128.into().serialize(ref cd); // GENESIS_FLOOR
                10_u128.into().serialize(ref cd); // PTS
                ZERO().serialize(ref cd); // PAY_TOKEN (mocked in tests)
                ADMIN().serialize(ref cd); // TREASURY
                adapter_addr.serialize(ref cd); // adapter
                cd
            },
        )
        .unwrap();
    let auction = IPulseAuctionDispatcher { contract_address: auction_addr };
    let auction_safe = IPulseAuctionSafeDispatcher { contract_address: auction_addr };

    // --- Finish wiring: adapter.auction = auction_addr
    cheat_caller_address(adapter_addr, ADMIN(), CheatSpan::TargetCalls(1));
    adapter_admin.set_auction(auction_addr);

    Env {
        nft_addr,
        minter_addr,
        adapter_addr,
        auction_addr,
        nft,
        erc721,
        meta,
        minter,
        adapter,
        adapter_safe,
        adapter_admin,
        auction,
        auction_safe,
    }
}
