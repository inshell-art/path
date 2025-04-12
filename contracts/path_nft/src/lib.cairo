#[starknet::contract]
mod BasicPathNFT {
    use starknet::ContractAddress;
    
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::token::erc721::ERC721HooksEmptyImpl;
    use openzeppelin::access::ownable::OwnableComponent;
    
    const IERC721_ID: felt252 = 0x33eb2f84c309543403fd69f0d0f363781ef06ef6faeb0131ff16ea3175bd943;
    const IERC721_METADATA_ID: felt252 = 0xabbcd595a567dce909050a1038e055daccb3c42af06f0add544fa90ee91f25;
    const IOWNABLE_ID: felt252 = 0x047581f005147e35634194b3543927d9b59e86f76859b181c58f951b5193481;
    const ISRC5_ID: felt252 = selector!("supports_interface");

    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
   
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

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
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        base_uri: ByteArray,
        initial_owner: ContractAddress // This is the owner of the CONTRACT now
    ) {
        OwnableInternalImpl::initializer(ref self.ownable, initial_owner);

        ERC721InternalImpl::initializer(ref self.erc721, name, symbol, base_uri);
        
        SRC5InternalImpl::register_interface(ref self.src5, IERC721_ID);
        SRC5InternalImpl::register_interface(ref self.src5, IERC721_METADATA_ID);
        SRC5InternalImpl::register_interface(ref self.src5, IOWNABLE_ID);
        SRC5InternalImpl::register_interface(ref self.src5, ISRC5_ID);
        
    }

    #[external(v0)]
    fn mint(ref self: ContractState, recipient: ContractAddress, token_id: u256) {
        OwnableInternalImpl::assert_only_owner(@ self.ownable);

        ERC721InternalImpl::mint(ref self.erc721, recipient, token_id);
    }
}