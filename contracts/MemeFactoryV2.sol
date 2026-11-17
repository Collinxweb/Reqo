// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Reqo MemeFactory v2
// Changes from v1:
//  - supply is whole tokens; the factory mints supply * 1e18 base units (decimals = 18)
//  - createTokenFor lets a relayer submit a token that the user signed (EIP-712),
//    so the signer is recorded as creator and the user needs no EVM window
//  - per-creator nonces prevent replay, deadlines limit signature lifetime
//
// Status: NOT YET COMPILED OR TESTED. See test-v2.js for the test plan.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MemeToken is ERC20 {
    address public immutable creator;
    string public description;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supplyUnits,
        address creator_,
        string memory description_
    ) ERC20(name_, symbol_) {
        creator = creator_;
        description = description_;
        _mint(creator_, supplyUnits);
    }
}

contract MemeFactoryV2 is EIP712 {
    uint256 public constant DECIMALS = 1e18;
    uint256 public constant MAX_WHOLE_SUPPLY = 1e12;
    uint256 public constant MAX_DESCRIPTION = 280;

    bytes32 public constant CREATE_TYPEHASH = keccak256(
        "CreateToken(address creator,string name,string symbol,uint256 supply,string description,uint256 nonce,uint256 deadline)"
    );

    struct CreateRequest {
        address creator;
        string name;
        string symbol;
        uint256 supply;        // whole tokens
        string description;
        uint256 nonce;
        uint256 deadline;      // unix seconds
    }

    address[] public tokens;
    mapping(address => address) public creatorOf;
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    event TokenCreated(
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
        uint256 supply
    );

    constructor() EIP712("Reqo MemeFactory", "2") {}

    // Direct path: the sender is the creator (needs the sender's own EVM window).
    function createToken(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description
    ) external returns (address) {
        return _create(msg.sender, name, symbol, supply, description);
    }

    // Relayed path: anyone may submit, but the token is created for the signer.
    function createTokenFor(CreateRequest calldata r, bytes calldata signature)
        external
        returns (address)
    {
        require(block.timestamp <= r.deadline, "expired");
        require(!nonceUsed[r.creator][r.nonce], "nonce used");

        address signer = ECDSA.recover(_hashTypedDataV4(_structHash(r)), signature);
        require(signer == r.creator, "bad signature");

        nonceUsed[r.creator][r.nonce] = true;
        return _create(r.creator, r.name, r.symbol, r.supply, r.description);
    }

    // Lets the frontend and tests check the exact digest the wallet must sign.
    function digest(CreateRequest calldata r) external view returns (bytes32) {
        return _hashTypedDataV4(_structHash(r));
    }

    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }

    function _structHash(CreateRequest calldata r) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CREATE_TYPEHASH,
                r.creator,
                keccak256(bytes(r.name)),
                keccak256(bytes(r.symbol)),
                r.supply,
                keccak256(bytes(r.description)),
                r.nonce,
                r.deadline
            )
        );
    }

    function _create(
        address creator_,
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description
    ) internal returns (address) {
        require(bytes(name).length > 0 && bytes(name).length <= 32, "bad name");
        require(bytes(symbol).length > 0 && bytes(symbol).length <= 10, "bad symbol");
        require(supply > 0, "zero supply");
        require(supply <= MAX_WHOLE_SUPPLY, "supply too large");
        require(bytes(description).length <= MAX_DESCRIPTION, "bad description");

        MemeToken t = new MemeToken(name, symbol, supply * DECIMALS, creator_, description);
        tokens.push(address(t));
        creatorOf[address(t)] = creator_;

        emit TokenCreated(address(t), creator_, name, symbol, supply);
        return address(t);
    }
}
