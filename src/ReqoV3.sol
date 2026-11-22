// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Reqo v3: swap-ready launches.
// Each launch mints the whole supply once, creates a constant-product pool holding
// all tokens plus a fixed WQOR seed, and records no creator allocation.
// There is no mint after launch, no owner, no upgrade path, and no function to withdraw pool liquidity.
// Status: deployed on QoreChain Diana testnet and used for live launches and trades.
// Foundry tests: test/ReqoV3.t.sol.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Wrapped QOR. Every unit is backed by native QOR held by the contract.
contract WQOR is ERC20, ERC20Permit, ReentrancyGuard {
    constructor() ERC20("Wrapped QOR", "WQOR") ERC20Permit("Wrapped QOR") {}

    receive() external payable {
        _wrap(msg.sender, msg.value);
    }

    function deposit() external payable {
        _wrap(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _burn(msg.sender, amount); // effects before interaction
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
    }

    function _wrap(address to, uint256 amount) internal {
        require(amount > 0, "zero amount");
        _mint(to, amount);
    }
}

// Launched token. Supply is minted once to the factory, which moves it into the pool.
contract MemeTokenV3 is ERC20, ERC20Permit {
    address public immutable factory;
    address public immutable creator;
    string public description;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 units,
        address creator_,
        string memory description_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        factory = msg.sender;
        creator = creator_;
        description = description_;
        _mint(msg.sender, units);
    }
}

// Constant-product pool with signed, relayable swaps.
// Trades need the trader's signed intent (amount, minimum out, deadline) and an EIP-2612
// permit for the input token, so no trader transaction or window is needed.
contract PoolV3 is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant SWAP_TYPEHASH = keccak256(
        "Swap(address trader,bool buy,uint256 amountIn,uint256 minOut,uint256 nonce,uint256 deadline)"
    );

    struct SwapIntent {
        address trader;
        bool buy;            // true: WQOR in, token out. false: token in, WQOR out.
        uint256 amountIn;
        uint256 minOut;
        uint256 nonce;
        uint256 deadline;
    }

    address public immutable factory;
    address public immutable token;
    address public immutable wqor;
    bool public seeded;
    uint256 public tokenReserve;
    uint256 public wqorReserve;
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    event Seeded(uint256 tokenAmount, uint256 wqorAmount);
    event Swapped(address indexed trader, bool buy, uint256 amountIn, uint256 amountOut);

    constructor(address token_, address wqor_) EIP712("Reqo Pool", "1") {
        factory = msg.sender;
        token = token_;
        wqor = wqor_;
    }

    // Called once by the factory after the tokens and the WQOR seed have been transferred in.
    // Reserves are set from the amounts passed in, so later donations never change pool pricing.
    function seed(uint256 tokenAmount, uint256 wqorAmount) external {
        require(msg.sender == factory, "not factory");
        require(!seeded, "already seeded");
        require(IERC20(token).balanceOf(address(this)) >= tokenAmount, "tokens not received");
        require(IERC20(wqor).balanceOf(address(this)) >= wqorAmount, "wqor not received");
        tokenReserve = tokenAmount;
        wqorReserve = wqorAmount;
        seeded = true;
        emit Seeded(tokenAmount, wqorAmount);
    }

    function quoteOut(bool buy, uint256 amountIn) public view returns (uint256) {
        uint256 rIn = buy ? wqorReserve : tokenReserve;
        uint256 rOut = buy ? tokenReserve : wqorReserve;
        uint256 inWithFee = amountIn * 997; // 0.3% fee, kept in the pool
        return (inWithFee * rOut) / (rIn * 1000 + inWithFee);
    }

    function hashIntent(SwapIntent calldata s) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SWAP_TYPEHASH,
                    s.trader,
                    s.buy,
                    s.amountIn,
                    s.minOut,
                    s.nonce,
                    s.deadline
                )
            )
        );
    }

    function swap(
        SwapIntent calldata s,
        bytes calldata signature,
        uint256 permitDeadline,
        uint8 v,
        bytes32 r,
        bytes32 sv
    ) external nonReentrant returns (uint256 out) {
        require(seeded, "not seeded");
        require(block.timestamp <= s.deadline, "expired");
        require(s.amountIn > 0, "zero amount");
        require(!nonceUsed[s.trader][s.nonce], "nonce used");
        require(ECDSA.recover(hashIntent(s), signature) == s.trader, "bad signature");
        nonceUsed[s.trader][s.nonce] = true;

        IERC20 inToken = IERC20(s.buy ? wqor : token);
        IERC20Permit permitToken = IERC20Permit(address(inToken));
        if (inToken.allowance(s.trader, address(this)) < s.amountIn) {
            permitToken.permit(s.trader, address(this), s.amountIn, permitDeadline, v, r, sv);
        }

        uint256 kBefore = wqorReserve * tokenReserve;
        out = quoteOut(s.buy, s.amountIn);
        require(out > 0 && out >= s.minOut, "slippage");
        require(out < (s.buy ? tokenReserve : wqorReserve), "insufficient liquidity");

        inToken.safeTransferFrom(s.trader, address(this), s.amountIn);
        if (s.buy) {
            wqorReserve += s.amountIn;
            tokenReserve -= out;
            IERC20(token).safeTransfer(s.trader, out);
        } else {
            tokenReserve += s.amountIn;
            wqorReserve -= out;
            IERC20(wqor).safeTransfer(s.trader, out);
        }
        require(wqorReserve * tokenReserve >= kBefore, "invariant");

        emit Swapped(s.trader, s.buy, s.amountIn, out);
    }
}

contract MemeFactoryV3 is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMALS = 1e18;
    uint256 public constant MAX_WHOLE_SUPPLY = 1e12;
    uint256 public constant MAX_DESCRIPTION = 280;
    uint256 public constant SEED_WQOR = 10e18; // fixed seed per launch, paid by the sender

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
        uint256 deadline;
    }

    WQOR public immutable wqor;
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

    constructor(address wqor_) EIP712("Reqo MemeFactory", "3") {
        wqor = WQOR(payable(wqor_));
    }

    // Direct path: the sender is the creator and pays the WQOR seed.
    function createToken(
        string calldata name,
        string calldata symbol,
        uint256 supply,
        string calldata description
    ) external nonReentrant returns (address) {
        CreateRequest memory r = CreateRequest({
            creator: msg.sender,
            name: name,
            symbol: symbol,
            supply: supply,
            description: description,
            nonce: 0,
            deadline: 0
        });
        return _create(r, msg.sender);
    }

    // Relayed path: the signer is the creator. The relayer pays the WQOR seed.
    function createTokenFor(CreateRequest calldata r, bytes calldata signature)
        external
        nonReentrant
        returns (address)
    {
        require(block.timestamp <= r.deadline, "expired");
        require(!nonceUsed[r.creator][r.nonce], "nonce used");
        address signer = ECDSA.recover(_hashTypedDataV4(_structHash(r)), signature);
        require(signer == r.creator, "bad signature");
        nonceUsed[r.creator][r.nonce] = true;

        CreateRequest memory m = r;
        return _create(m, msg.sender);
    }

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

    function _create(CreateRequest memory r, address payer) internal returns (address) {
        require(bytes(r.name).length > 0 && bytes(r.name).length <= 32, "bad name");
        require(bytes(r.symbol).length > 0 && bytes(r.symbol).length <= 10, "bad symbol");
        require(r.supply > 0, "zero supply");
        require(r.supply <= MAX_WHOLE_SUPPLY, "supply too large");
        require(bytes(r.description).length <= MAX_DESCRIPTION, "bad description");

        uint256 units = r.supply * DECIMALS;
        MemeTokenV3 t = new MemeTokenV3(r.name, r.symbol, units, r.creator, r.description);
        PoolV3 p = new PoolV3(address(t), address(wqor));

        IERC20(address(t)).safeTransfer(address(p), units);
        IERC20(address(wqor)).safeTransferFrom(payer, address(p), SEED_WQOR);
        p.seed(units, SEED_WQOR);

        tokens.push(address(t));
        creatorOf[address(t)] = r.creator;
        poolOf[address(t)] = address(p);

        emit TokenCreated(address(t), address(p), r.creator, r.name, r.symbol, r.supply);
        return address(t);
    }
}
