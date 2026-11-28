// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ReqoV5Registry {
    address public immutable factory;

    mapping(bytes32 => address) public tokenByTicker;
    mapping(address => address) public poolOf;
    mapping(address => address) public creatorOf;

    event CanonicalTokenRegistered(
        bytes32 indexed ticker,
        address indexed token,
        address indexed pool,
        address creator
    );

    constructor() {
        factory = msg.sender;
    }

    function tickerKey(string memory symbol)
        public pure returns (bytes32)
    {
        bytes memory s = bytes(symbol);
        require(s.length > 0 && s.length <= 10, "bad ticker");

        for (uint256 i; i < s.length; ++i) {
            bytes1 c = s[i];
            require(
                (c >= 0x30 && c <= 0x39) ||
                (c >= 0x41 && c <= 0x5a),
                "ticker must be A-Z or 0-9"
            );
        }

        return keccak256(s);
    }

    function register(
        string calldata symbol,
        address token,
        address pool,
        address creator
    ) external {
        require(msg.sender == factory, "factory only");
        require(
            token != address(0) &&
            pool != address(0) &&
            creator != address(0),
            "zero address"
        );

        bytes32 key = tickerKey(symbol);
        require(tokenByTicker[key] == address(0), "ticker taken");
        require(creatorOf[token] == address(0), "token registered");

        tokenByTicker[key] = token;
        poolOf[token] = pool;
        creatorOf[token] = creator;

        emit CanonicalTokenRegistered(key, token, pool, creator);
    }
}
