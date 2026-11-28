// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ReqoV3.sol"; // WQOR, MemeTokenV3 and PoolV3 are unchanged and already deployed
import "./ReqoV5Registry.sol";
import "./PoolV5.sol";

// Launch gate. A token is created only when the caller's registered ML-DSA-87 key signs the
// exact request, checked on chain with pqcVerify (0x...0A01). The key itself comes from
// pqcKeyStatus (0x...0A02). Every failure reverts: the gate fails closed.
contract MemeFactoryV5 is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant PQC_VERIFY = 0x0000000000000000000000000000000000000a01;
    address public constant PQC_KEY_STATUS = 0x0000000000000000000000000000000000000a02;
    bytes4 public constant VERIFY_SELECTOR = bytes4(keccak256("pqcVerify(bytes,bytes,bytes)"));
    bytes4 public constant KEY_SELECTOR = bytes4(keccak256("pqcKeyStatus(address)"));
    uint8 public constant ALG_ML_DSA_87 = 1;

    // QoreSign message-signing-v1 prefix: "qorechain-msg-v1|" + chainId + "|".
    bytes public constant MSG_PREFIX = "qorechain-msg-v1|qorechain-diana|";
    bytes32 public constant DOMAIN_TAG = keccak256("ReqoV5.createToken");

    uint256 public constant DECIMALS = 1e18;
    uint256 public constant MAX_WHOLE_SUPPLY = 1e12;
    uint256 public constant MAX_DESCRIPTION = 280;
    uint256 public constant SEED_WQOR = 10e18;

    WQOR public immutable wqor;
    ReqoV5Registry public immutable registry;

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
    event PqcVerified(address indexed creator, bytes32 digest);

    constructor(address wqor_) {
        wqor = WQOR(payable(wqor_));
        registry = new ReqoV5Registry();
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
        require(registry.tokenByTicker(registry.tickerKey(symbol)) == address(0), "ticker taken");

        // The caller must have a registered, possession-proven ML-DSA-87 key, and the
        // submitted key must be that registered key.
        (bool registered, uint8 algorithmId, bytes memory registeredKey, bool possessionProven) =
            _keyStatus(msg.sender);
        require(registered && algorithmId == ALG_ML_DSA_87 && possessionProven, "key not proven");
        require(keccak256(registeredKey) == keccak256(pubKey), "key not owned");

        bytes memory message = messageFor(msg.sender, nonce, deadline, name, symbol, supply, description);
        require(_pqcVerify(pubKey, signature, message), "pqc: bad signature");

        nonceUsed[msg.sender][nonce] = true;
        emit PqcVerified(msg.sender, keccak256(message));
        return _create(name, symbol, supply, description, msg.sender);
    }

    // staticcall to pqcKeyStatus. A failed call or an undecodable result reverts.
    function _keyStatus(address account)
        internal
        view
        returns (bool registered, uint8 algorithmId, bytes memory pubkey, bool possessionProven)
    {
        (bool ok, bytes memory out) = PQC_KEY_STATUS.staticcall(abi.encodeWithSelector(KEY_SELECTOR, account));
        require(ok, "key status unavailable");
        (registered, algorithmId, pubkey, possessionProven) = abi.decode(out, (bool, uint8, bytes, bool));
    }

    // staticcall to pqcVerify. Requires a 32-byte result and decodes it as a bool.
    function _pqcVerify(bytes calldata pk, bytes calldata sig, bytes memory message) internal view returns (bool) {
        (bool ok, bytes memory out) = PQC_VERIFY.staticcall(abi.encodeWithSelector(VERIFY_SELECTOR, pk, sig, message));
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
        PoolV5 p = new PoolV5(address(t), address(wqor), creator);

        IERC20(address(t)).safeTransfer(address(p), units);
        IERC20(address(wqor)).safeTransferFrom(msg.sender, address(p), SEED_WQOR);
        p.seed(units, SEED_WQOR);

        registry.register(symbol, address(t), address(p), creator);
        tokens.push(address(t));
        creatorOf[address(t)] = creator;
        poolOf[address(t)] = address(p);

        emit TokenCreated(address(t), address(p), creator, name, symbol, supply);
        return address(t);
    }
}
