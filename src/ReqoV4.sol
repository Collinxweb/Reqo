// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ReqoV3.sol"; // WQOR, MemeTokenV3 and PoolV3 are unchanged and already deployed

// Key registry at 0x...0A02.
// UNCONFIRMED: the signature below is a placeholder until QoreChain confirms the real
// pqcKeyStatus call and its return fields. Do not deploy with this interface unverified.
interface IPqcKeyStatus {
    function keyStatus(address account) external view returns (bool possessionProven, bytes32 keyHash);
}

// Launch gate. A token is created only when the caller's registered ML-DSA-87 key signs
// the exact request, checked on chain with pqcVerify at 0x...0A01. The check fails closed:
// a missing precompile, a malformed call, or a false result all revert.
contract MemeFactoryV4 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant PQC = 0x0000000000000000000000000000000000000a01;
    bytes4 public constant PQC_SELECTOR = bytes4(keccak256("pqcVerify(bytes,bytes,bytes)"));
    // Signed payload prefix from QoreSign message-signing-v1: "qorechain-msg-v1|" + chainId + "|".
    bytes public constant MSG_PREFIX = "qorechain-msg-v1|qorechain-diana|";
    bytes32 public constant DOMAIN_TAG = keccak256("ReqoV4.createToken");

    uint256 public constant DECIMALS = 1e18;
    uint256 public constant MAX_WHOLE_SUPPLY = 1e12;
    uint256 public constant MAX_DESCRIPTION = 280;
    uint256 public constant SEED_WQOR = 10e18;

    WQOR public immutable wqor;
    IPqcKeyStatus public immutable keyRegistry;

    address[] public tokens;
    mapping(address => address) public creatorOf;
    mapping(address => address) public poolOf;
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    event TokenCreated(
        address indexed token,
        address indexed pool,
        address indexed creator,
        string name,
        string symbol,
        uint256 supply
    );
    event PqcVerified(address indexed creator, bytes32 digest, bytes32 keyHash);

    constructor(address wqor_, address keyRegistry_) {
        wqor = WQOR(payable(wqor_));
        keyRegistry = IPqcKeyStatus(keyRegistry_);
    }

    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }

    // The exact bytes the creator's key must sign. The frontend builds the same bytes.
    function messageFor(
        address creator,
        uint256 nonce,
        uint256 deadline,
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description
    ) public view returns (bytes memory) {
        return bytes.concat(
            MSG_PREFIX,
            abi.encode(
                DOMAIN_TAG,
                block.chainid,
                address(this),
                creator,
                nonce,
                deadline,
                name,
                symbol,
                supply,
                keccak256(bytes(description))
            )
        );
    }

    function createToken(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description,
        uint256 nonce,
        uint256 deadline,
        bytes calldata pubKey,
        bytes calldata signature
    ) external nonReentrant returns (address) {
        require(block.timestamp <= deadline, "expired");
        require(!nonceUsed[msg.sender][nonce], "nonce used");
        _checkFields(name, symbol, supply, description);

        // The key must be registered to the caller, and the supplied key must be that key.
        (bool proven, bytes32 keyHash) = keyRegistry.keyStatus(msg.sender);
        require(proven, "key not proven");
        require(keyHash == keccak256(pubKey), "key not owned");

        bytes memory message = messageFor(msg.sender, nonce, deadline, name, symbol, supply, description);
        require(_pqcVerify(pubKey, signature, message), "pqc: bad signature");

        nonceUsed[msg.sender][nonce] = true;
        emit PqcVerified(msg.sender, keccak256(message), keyHash);
        return _create(name, symbol, supply, description, msg.sender);
    }

    // staticcall, a 32-byte result, and a decoded bool. Anything else reverts (fail closed).
    function _pqcVerify(bytes calldata pk, bytes calldata sig, bytes memory message) internal view returns (bool) {
        (bool ok, bytes memory out) = PQC.staticcall(abi.encodeWithSelector(PQC_SELECTOR, pk, sig, message));
        require(ok && out.length == 32, "pqc unavailable");
        return abi.decode(out, (bool));
    }

    // Finding F1: names are printable ASCII and tickers are A-Z or 0-9 on chain.
    function _checkFields(string calldata name, string calldata symbol, uint256 supply, string calldata description)
        internal
        pure
    {
        bytes memory n = bytes(name);
        require(n.length > 0 && n.length <= 32, "bad name");
        for (uint256 i = 0; i < n.length; i++) {
            require(n[i] >= 0x20 && n[i] <= 0x7e, "name must be printable ASCII");
        }
        bytes memory s = bytes(symbol);
        require(s.length > 0 && s.length <= 10, "bad symbol");
        for (uint256 i = 0; i < s.length; i++) {
            bytes1 c = s[i];
            require((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a), "symbol must be A-Z or 0-9");
        }
        require(supply > 0, "zero supply");
        require(supply <= MAX_WHOLE_SUPPLY, "supply too large");
        require(bytes(description).length <= MAX_DESCRIPTION, "bad description");
    }

    function _create(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description,
        address creator
    ) internal returns (address) {
        uint256 units = supply * DECIMALS;
        MemeTokenV3 t = new MemeTokenV3(name, symbol, units, creator, description);
        PoolV3 p = new PoolV3(address(t), address(wqor));

        IERC20(address(t)).safeTransfer(address(p), units);
        IERC20(address(wqor)).safeTransferFrom(msg.sender, address(p), SEED_WQOR);
        p.seed(units, SEED_WQOR);

        tokens.push(address(t));
        creatorOf[address(t)] = creator;
        poolOf[address(t)] = address(p);

        emit TokenCreated(address(t), address(p), creator, name, symbol, supply);
        return address(t);
    }
}
