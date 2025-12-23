// One shared helper module for Path test suites (NFT, Minter, and E2E).

use core::array::ArrayTrait;
use openzeppelin::access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait, IAccessControlSafeDispatcher,
};
use openzeppelin::introspection::interface::ISRC5Dispatcher;
use openzeppelin::token::erc721::interface::{
    IERC721Dispatcher, IERC721MetadataCamelOnlyDispatcher, IERC721MetadataDispatcher,
    IERC721SafeDispatcher,
};
use path_interfaces::interfaces::{
    IPathMinterDispatcher, IPathMinterSafeDispatcher, IPathNFTDispatcher, IPathNFTSafeDispatcher,
};
use path_minter_adapter::path_minter_adapter::{
    IAdapterAdminDispatcher, IAdapterAdminDispatcherTrait,
};
use pulse_adapter::interface::{IPulseAdapterDispatcher, IPulseAdapterSafeDispatcher};
use pulse_auction::interface::{IPulseAuctionDispatcher, IPulseAuctionSafeDispatcher};
use snforge_std::cheatcodes::CheatSpan;
use snforge_std::{ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
use starknet::ContractAddress;

// =======================================================
//                   Test constants
// =======================================================

/// Deterministic addresses for tests (string-literal → address).
pub fn ZERO_ADDR() -> ContractAddress {
    0.try_into().unwrap()
}
pub fn ADMIN() -> ContractAddress {
    'ADMIN'.try_into().unwrap()
}
pub fn MINTER() -> ContractAddress {
    'MINTER'.try_into().unwrap()
}
pub fn ALICE() -> ContractAddress {
    'ALICE'.try_into().unwrap()
}
pub fn BOB() -> ContractAddress {
    'BOB'.try_into().unwrap()
}
pub fn TREASURY() -> ContractAddress {
    'TREASURY'.try_into().unwrap()
}
pub fn PAYTOKEN() -> ContractAddress {
    'PAYTOKEN'.try_into().unwrap()
} // for e2e mocks

/// ERC-721 metadata defaults (PathNFT)
pub fn NAME() -> ByteArray {
    "PATH NFT"
}
pub fn SYMBOL() -> ByteArray {
    "PATH"
}
pub fn BASE_URI() -> ByteArray {
    ""
} // your NFT builds JSON+SVG; base URI optional

/// Common roles
pub const MINTER_ROLE: felt252 = selector!("MINTER_ROLE");
pub const SALES_ROLE: felt252 = selector!("SALES_ROLE");
pub const RESERVED_ROLE: felt252 = selector!("RESERVED_ROLE");
pub const FIRST_PUBLIC_ID: u256 = 0_u256;
pub const RESERVED_CAP: u64 = 3_u64;

// =======================================================
//            A minimal ERC-721 receiver for tests
// =======================================================

#[starknet::contract]
mod TestERC721Receiver {
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721ReceiverComponent;

    component!(path: ERC721ReceiverComponent, storage: erc721_receiver, event: ERC721ReceiverEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl ERC721ReceiverImpl =
        ERC721ReceiverComponent::ERC721ReceiverImpl<ContractState>;
    impl ERC721ReceiverInternalImpl = ERC721ReceiverComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721_receiver: ERC721ReceiverComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721ReceiverEvent: ERC721ReceiverComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc721_receiver.initializer();
    }
}

#[starknet::contract]
mod TestPathLook {
    use core::byte_array::ByteArrayTrait;
    use core::to_byte_array::AppendFormattedToByteArray;
    use core::traits::TryInto;
    use core::zeroable::NonZero;
    use path_interfaces::interfaces::{IPathLook, IPathNFTDispatcher, IPathNFTDispatcherTrait};
    use starknet::ContractAddress;

    #[storage]
    struct Storage {}

    #[constructor]
    fn constructor(ref self: ContractState) {}

    #[abi(embed_v0)]
    impl TestPathLookImpl of IPathLook<ContractState> {
        fn generate_svg(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            let stage = stage_from_nft(path_nft, token_id);
            let token_id_str = u256_to_string(token_id);
            let mut out: ByteArray = Default::default();
            out.append(@"<svg data-token='");
            out.append(@token_id_str);
            out.append(@"' data-stage='");
            out.append(@stage_label(stage));
            out.append(@"'/>");
            out
        }

        fn generate_svg_data_uri(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            let svg = self.generate_svg(path_nft, token_id);
            let mut out: ByteArray = Default::default();
            out.append(@"data:image/svg+xml,");
            out.append(@svg);
            out
        }

        fn get_token_metadata(
            self: @ContractState, path_nft: ContractAddress, token_id: u256,
        ) -> ByteArray {
            let stage = stage_from_nft(path_nft, token_id);
            let (thought, will, awa) = stage_flags(stage);
            let token_id_str = u256_to_string(token_id);
            let mut out: ByteArray = Default::default();
            out.append(@"{\"token\":");
            out.append(@token_id_str);
            out.append(@",\"stage\":\"");
            out.append(@stage_label(stage));
            out.append(@"\",\"thought\":\"");
            out.append(@manifest_string(thought));
            out.append(@"\",\"will\":\"");
            out.append(@manifest_string(will));
            out.append(@"\",\"awa\":\"");
            out.append(@manifest_string(awa));
            out.append(@"\"}");
            out
        }
    }

    fn stage_from_nft(path_nft: ContractAddress, token_id: u256) -> u8 {
        let nft = IPathNFTDispatcher { contract_address: path_nft };
        nft.get_stage(token_id)
    }

    fn stage_flags(stage: u8) -> (bool, bool, bool) {
        (stage >= 1_u8, stage >= 2_u8, stage >= 3_u8)
    }

    fn stage_label(stage: u8) -> ByteArray {
        match stage {
            0_u8 => "IDEAL",
            1_u8 => "THOUGHT",
            2_u8 => "WILL",
            3_u8 => "AWA",
            _ => "UNKNOWN",
        }
    }

    fn manifest_string(minted: bool) -> ByteArray {
        if minted {
            "Manifested"
        } else {
            "Latent"
        }
    }

    fn u256_to_string(value: u256) -> ByteArray {
        let base: NonZero<u256> = 10_u256.try_into().unwrap();
        let mut out: ByteArray = Default::default();
        value.append_formatted_to_byte_array(ref out, base);
        out
    }
}

/// Deploys the minimal ERC-721 receiver used in safe mints/transfers.
pub fn deploy_receiver() -> ContractAddress {
    let class = declare("TestERC721Receiver").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

/// Deploys the minimal PathLook mock used in PathNFT tests.
pub fn deploy_path_look_mock() -> ContractAddress {
    let class = declare("TestPathLook").unwrap().contract_class();
    let (addr, _) = class.deploy(@array![]).unwrap();
    addr
}

// =======================================================
//                      PathNFT helpers
// =======================================================

#[derive(Drop)]
pub struct NftHandles {
    pub addr: ContractAddress,
    pub nft: IPathNFTDispatcher,
    pub nft_safe: IPathNFTSafeDispatcher,
    pub erc721: IERC721Dispatcher,
    pub erc721_safe: IERC721SafeDispatcher,
    pub meta: IERC721MetadataDispatcher,
    pub camel_meta: IERC721MetadataCamelOnlyDispatcher,
    pub src5: ISRC5Dispatcher,
    pub ac: IAccessControlDispatcher,
    pub ac_safe: IAccessControlSafeDispatcher,
}

/// Deploy PathNFT with explicit constructor args.
/// PathNFT constructor *(as in your repo)*:
/// (initial_admin, name, symbol, base_uri, path_look)
pub fn deploy_path_nft_with(
    initial_admin: ContractAddress,
    name: ByteArray,
    symbol: ByteArray,
    base_uri: ByteArray,
    path_look: ContractAddress,
) -> NftHandles {
    let class = declare("PathNFT").unwrap().contract_class();

    let mut calldata = ArrayTrait::new();
    initial_admin.serialize(ref calldata);
    name.serialize(ref calldata);
    symbol.serialize(ref calldata);
    base_uri.serialize(ref calldata);
    path_look.serialize(ref calldata);

    let (addr, _) = class.deploy(@calldata).unwrap();

    NftHandles {
        addr,
        nft: IPathNFTDispatcher { contract_address: addr },
        nft_safe: IPathNFTSafeDispatcher { contract_address: addr },
        erc721: IERC721Dispatcher { contract_address: addr },
        erc721_safe: IERC721SafeDispatcher { contract_address: addr },
        meta: IERC721MetadataDispatcher { contract_address: addr },
        camel_meta: IERC721MetadataCamelOnlyDispatcher { contract_address: addr },
        src5: ISRC5Dispatcher { contract_address: addr },
        ac: IAccessControlDispatcher { contract_address: addr },
        ac_safe: IAccessControlSafeDispatcher { contract_address: addr },
    }
}

/// Convenience: deploy PathNFT (admin = ADMIN, minter = ZERO, default name/symbol/base).
pub fn deploy_path_nft_default() -> NftHandles {
    let look = deploy_path_look_mock();
    deploy_path_nft_with(ADMIN(), NAME(), SYMBOL(), BASE_URI(), look)
}

/// Grant `MINTER_ROLE` on the NFT to `minter_addr` (uses cheat_caller as ADMIN).
pub fn grant_minter_on_nft(nft: @NftHandles, minter_addr: ContractAddress) {
    cheat_caller_address(*nft.addr, ADMIN(), CheatSpan::TargetCalls(1));
    nft.ac.grant_role(MINTER_ROLE, minter_addr);
}

// =======================================================
//                    PathMinter helpers
// =======================================================

#[derive(Drop)]
pub struct MinterHandles {
    pub addr: ContractAddress,
    pub minter: IPathMinterDispatcher,
    pub minter_safe: IPathMinterSafeDispatcher,
    pub ac: IAccessControlDispatcher,
    pub ac_safe: IAccessControlSafeDispatcher,
    pub nft_addr: ContractAddress,
    pub erc721: IERC721Dispatcher,
    pub erc721_safe: IERC721SafeDispatcher,
}

pub fn deploy_path_minter(
    nft: @NftHandles, first_public_id: u256, reserved_cap: u64,
) -> MinterHandles {
    let class = declare("PathMinter").unwrap().contract_class();

    let mut calldata = ArrayTrait::new();
    ADMIN().serialize(ref calldata);
    nft.addr.serialize(ref calldata);
    first_public_id.serialize(ref calldata);
    reserved_cap.serialize(ref calldata);

    let (addr, _) = class.deploy(@calldata).unwrap();

    MinterHandles {
        addr,
        minter: IPathMinterDispatcher { contract_address: addr },
        minter_safe: IPathMinterSafeDispatcher { contract_address: addr },
        ac: IAccessControlDispatcher { contract_address: addr },
        ac_safe: IAccessControlSafeDispatcher { contract_address: addr },
        nft_addr: *nft.addr,
        erc721: IERC721Dispatcher { contract_address: *nft.addr },
        erc721_safe: IERC721SafeDispatcher { contract_address: *nft.addr },
    }
}

// =======================================================
//               PathMinterAdapter (Pulse) helpers
// =======================================================

#[derive(Drop)]
pub struct AdapterHandles {
    pub addr: ContractAddress,
    pub adapter: IPulseAdapterDispatcher,
    pub adapter_safe: IPulseAdapterSafeDispatcher,
    pub admin: IAdapterAdminDispatcher,
}

/// Deploy PathMinterAdapter(owner, auction, minter)
pub fn deploy_path_minter_adapter(
    owner: ContractAddress, auction: ContractAddress, minter: ContractAddress,
) -> AdapterHandles {
    let class = declare("PathMinterAdapter").unwrap().contract_class();
    let mut cd = ArrayTrait::new();
    owner.serialize(ref cd);
    auction.serialize(ref cd);
    minter.serialize(ref cd);
    let (addr, _) = class.deploy(@cd).unwrap();

    AdapterHandles {
        addr,
        adapter: IPulseAdapterDispatcher { contract_address: addr },
        adapter_safe: IPulseAdapterSafeDispatcher { contract_address: addr },
        admin: IAdapterAdminDispatcher { contract_address: addr },
    }
}

// =======================================================
//                PulseAuction e2e helpers (optional)
// =======================================================

#[derive(Drop)]
pub struct AuctionHandles {
    pub addr: ContractAddress,
    pub auction: IPulseAuctionDispatcher,
    pub auction_safe: IPulseAuctionSafeDispatcher,
}

/// Deploy PulseAuction with explicit params:
/// (start_delay_sec, k, genesis_price, genesis_floor, pts, payment_token, treasury, mint_adapter)
pub fn deploy_pulse_auction_with(
    start_delay_sec: u64,
    k: u256,
    genesis_price: u256,
    genesis_floor: u256,
    pts: felt252,
    payment_token: ContractAddress,
    treasury: ContractAddress,
    mint_adapter: ContractAddress,
) -> AuctionHandles {
    let class = declare("PulseAuction").unwrap().contract_class();
    let mut cd = ArrayTrait::new();
    start_delay_sec.serialize(ref cd);
    k.serialize(ref cd);
    genesis_price.serialize(ref cd);
    genesis_floor.serialize(ref cd);
    pts.serialize(ref cd);
    payment_token.serialize(ref cd);
    treasury.serialize(ref cd);
    mint_adapter.serialize(ref cd);
    let (addr, _) = class.deploy(@cd).unwrap();

    AuctionHandles {
        addr,
        auction: IPulseAuctionDispatcher { contract_address: addr },
        auction_safe: IPulseAuctionSafeDispatcher { contract_address: addr },
    }
}

// =======================================================
//                 Composed environments (quick)
// =======================================================

/// Full E2E: NFT + Minter + Adapter + Auction. Wires roles and adapter.
#[derive(Drop)]
pub struct E2EEnv {
    pub nft: NftHandles,
    pub minter: MinterHandles,
    pub adapter: AdapterHandles,
    pub auction: AuctionHandles,
}

pub fn deploy_e2e_env() -> E2EEnv {
    let nft = deploy_path_nft_default();

    // Use the variant that matches your PathMinter right now:
    let minter = deploy_path_minter(@nft, FIRST_PUBLIC_ID, RESERVED_CAP);

    // adapter with auction unknown yet (ZERO), then we set it after auction deploy
    let adapter = deploy_path_minter_adapter(ADMIN(), ZERO_ADDR(), minter.addr);

    // auction (you’ll mock ERC-20 in tests)
    let auction = deploy_pulse_auction_with(
        0_u64,
        10_000_u128.into(), // k
        1_000_u128.into(), // genesis price
        800_u128.into(), // genesis floor
        10, // pts (felt252)
        PAYTOKEN(), // payment token (mocked)
        TREASURY(), // treasury
        adapter.addr // mint adapter = PathMinterAdapter
    );

    // finalize wiring: adapter.set_auction(auction)
    cheat_caller_address(adapter.addr, ADMIN(), CheatSpan::TargetCalls(1));
    adapter.admin.set_auction(auction.addr);

    // allow PathMinter to mint in PathNFT
    grant_minter_on_nft(@nft, minter.addr);

    E2EEnv { nft, minter, adapter, auction }
}
