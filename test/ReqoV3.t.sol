// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "../src/ReqoV3.sol";

contract ReqoV3Test is Test {
    WQOR internal wqor;
    MemeFactoryV3 internal fac;

    address internal creator = makeAddr("creator");
    address internal trader;
    uint256 internal traderKey;

    uint256 internal constant EXPECTED_QUOTE_1_WQOR = 90661089388014913158; // matches Diana testnet quote

    function setUp() public {
        (trader, traderKey) = makeAddrAndKey("trader");
        wqor = new WQOR();
        fac = new MemeFactoryV3(address(wqor));

        vm.deal(creator, 100 ether);
        vm.deal(trader, 100 ether);
        vm.deal(address(this), 100 ether);

        vm.startPrank(creator);
        wqor.deposit{value: 50 ether}();
        wqor.approve(address(fac), type(uint256).max);
        vm.stopPrank();
    }

    // ---------- helpers ----------

    function _launch() internal returns (MemeTokenV3 t, PoolV3 p) {
        vm.prank(creator);
        address ta = fac.createToken("Frog", "CROAK", 1000, "a frog coin");
        t = MemeTokenV3(ta);
        p = PoolV3(fac.poolOf(ta));
    }

    function _signIntent(PoolV3 p, uint256 key, PoolV3.SwapIntent memory s) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 sv) = vm.sign(key, p.hashIntent(s));
        return abi.encodePacked(r, sv, v);
    }

    // EIP-2612 permit for the input token, signed by the owner.
    function _permit(address token, uint256 key, address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                IERC20Permit(token).nonces(owner),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(key, digest);
    }

    // ---------- launch ----------

    function test_createToken_mintsWholeSupplyToPoolAndSeedsReserves() public {
        (MemeTokenV3 t, PoolV3 p) = _launch();
        assertEq(t.balanceOf(address(p)), 1000e18);
        assertEq(t.balanceOf(creator), 0, "creator gets no tokens");
        assertEq(wqor.balanceOf(address(p)), 10e18, "seed is 10 WQOR");
        assertTrue(p.seeded());
        assertEq(p.tokenReserve(), 1000e18);
        assertEq(p.wqorReserve(), 10e18);
        assertEq(fac.creatorOf(address(t)), creator);
        assertEq(fac.tokenCount(), 1);
        assertEq(t.description(), "a frog coin");
    }

    function test_createToken_rejectsBadInput() public {
        vm.startPrank(creator);
        vm.expectRevert(bytes("bad name"));
        fac.createToken("", "X", 1, "");
        vm.expectRevert(bytes("bad symbol"));
        fac.createToken("Name", "ELEVENCHARS", 1, "");
        vm.expectRevert(bytes("zero supply"));
        fac.createToken("Name", "X", 0, "");
        vm.expectRevert(bytes("supply too large"));
        fac.createToken("Name", "X", 1e12 + 1, "");
        vm.expectRevert(bytes("bad description"));
        fac.createToken("Name", "X", 1, _repeat("a", 281));
        vm.stopPrank();
    }

    function test_createToken_needsTheWqorSeed() public {
        address poor = makeAddr("poor");
        vm.prank(poor);
        vm.expectRevert();
        fac.createToken("Name", "X", 1, "");
    }

    function test_seed_onlyFactory_andOnlyOnce() public {
        (, PoolV3 p) = _launch();
        vm.expectRevert(bytes("not factory"));
        p.seed(1, 1);
        vm.prank(address(fac));
        vm.expectRevert(bytes("already seeded"));
        p.seed(1, 1);
    }

    // ---------- pricing ----------

    function test_quoteOut_matchesTestnetQuote() public {
        (, PoolV3 p) = _launch();
        assertEq(p.quoteOut(true, 1e18), EXPECTED_QUOTE_1_WQOR);
    }

    function test_quoteOut_feeStaysInPool() public {
        (, PoolV3 p) = _launch();
        uint256 out = p.quoteOut(true, 1e18);
        // without the fee the output would be larger: 1000e18 * 1e18 / (10e18 + 1e18)
        uint256 noFee = (1000e18 * uint256(1e18)) / 11e18;
        assertLt(out, noFee);
    }

    // ---------- trading ----------

    function test_swapBuy_paysOutAndKeepsFeeInPool() public {
        (MemeTokenV3 t, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: 1 ether}();

        uint256 deadline = block.timestamp + 1 hours;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent({
            trader: trader, buy: true, amountIn: 1e18, minOut: p.quoteOut(true, 1e18), nonce: 1, deadline: deadline
        });
        bytes memory sig = _signIntent(p, traderKey, s);
        (uint8 v, bytes32 r, bytes32 sv) = _permit(address(wqor), traderKey, trader, address(p), 1e18, deadline);

        // Anyone can submit the signed intent, so the trader pays no gas for the swap itself.
        uint256 out = p.swap(s, sig, deadline, v, r, sv);

        assertEq(out, EXPECTED_QUOTE_1_WQOR);
        assertEq(t.balanceOf(trader), out);
        assertEq(p.wqorReserve(), 11e18, "full amount in stays in the pool, fee included");
        assertEq(p.tokenReserve(), 1000e18 - out);
    }

    function test_swapSell_paysWqorOut() public {
        (MemeTokenV3 t, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: 1 ether}();
        uint256 deadline = block.timestamp + 1 hours;

        // buy first to get tokens
        PoolV3.SwapIntent memory b = PoolV3.SwapIntent(trader, true, 1e18, 0, 1, deadline);
        (uint8 v1, bytes32 r1, bytes32 s1) = _permit(address(wqor), traderKey, trader, address(p), 1e18, deadline);
        p.swap(b, _signIntent(p, traderKey, b), deadline, v1, r1, s1);

        uint256 sellIn = t.balanceOf(trader) / 2;
        uint256 wqorBefore = wqor.balanceOf(trader);
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, false, sellIn, 0, 2, deadline);
        (uint8 v2, bytes32 r2, bytes32 s2) = _permit(address(t), traderKey, trader, address(p), sellIn, deadline);
        uint256 out = p.swap(s, _signIntent(p, traderKey, s), deadline, v2, r2, s2);

        assertGt(out, 0);
        assertEq(wqor.balanceOf(trader) - wqorBefore, out);
    }

    function test_swap_replayReverts() public {
        (, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: 1 ether}();
        uint256 deadline = block.timestamp + 1 hours;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, 1e18, 0, 9, deadline);
        bytes memory sig = _signIntent(p, traderKey, s);
        (uint8 v, bytes32 r, bytes32 sv) = _permit(address(wqor), traderKey, trader, address(p), 1e18, deadline);
        p.swap(s, sig, deadline, v, r, sv);
        vm.expectRevert(bytes("nonce used"));
        p.swap(s, sig, deadline, v, r, sv);
    }

    function test_swap_expiredReverts() public {
        (, PoolV3 p) = _launch();
        uint256 deadline = block.timestamp - 1;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, 1e18, 0, 3, deadline);
        bytes memory sig = _signIntent(p, traderKey, s);
        vm.expectRevert(bytes("expired"));
        p.swap(s, sig, deadline, 0, bytes32(0), bytes32(0));
    }

    function test_swap_wrongSignerReverts() public {
        (, PoolV3 p) = _launch();
        (, uint256 otherKey) = makeAddrAndKey("other");
        uint256 deadline = block.timestamp + 1 hours;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, 1e18, 0, 4, deadline);
        bytes memory sig = _signIntent(p, otherKey, s);
        vm.expectRevert(bytes("bad signature"));
        p.swap(s, sig, deadline, 0, bytes32(0), bytes32(0));
    }

    function test_swap_slippageReverts() public {
        (, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: 1 ether}();
        uint256 deadline = block.timestamp + 1 hours;
        uint256 tooHigh = p.quoteOut(true, 1e18) + 1;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, 1e18, tooHigh, 5, deadline);
        bytes memory sig = _signIntent(p, traderKey, s);
        (uint8 v, bytes32 r, bytes32 sv) = _permit(address(wqor), traderKey, trader, address(p), 1e18, deadline);
        vm.expectRevert(bytes("slippage"));
        p.swap(s, sig, deadline, v, r, sv);
    }

    // ---------- liquidity is locked ----------

    function test_poolHasNoLiquidityWithdrawal() public {
        (, PoolV3 p) = _launch();
        (bool ok1,) = address(p).call(abi.encodeWithSignature("withdrawLiquidity(uint256)", 1));
        (bool ok2,) = address(p).call(abi.encodeWithSignature("removeLiquidity(uint256)", 1));
        (bool ok3,) = address(p).call(abi.encodeWithSignature("skim(address)", address(this)));
        assertFalse(ok1);
        assertFalse(ok2);
        assertFalse(ok3);
    }

    // ---------- relayed creation (signature path) ----------

    function test_createTokenFor_acceptsCreatorSignature() public {
        (address c, uint256 ck) = makeAddrAndKey("relayedCreator");
        wqor.deposit{value: 20 ether}();
        wqor.approve(address(fac), type(uint256).max);

        MemeFactoryV3.CreateRequest memory req = MemeFactoryV3.CreateRequest({
            creator: c, name: "Relay", symbol: "RLY", supply: 500, description: "relayed", nonce: 7, deadline: block.timestamp + 1 hours
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ck, fac.digest(req));
        address ta = fac.createTokenFor(req, abi.encodePacked(r, s, v));

        assertEq(fac.creatorOf(ta), c);
        vm.expectRevert(bytes("nonce used"));
        fac.createTokenFor(req, abi.encodePacked(r, s, v));
    }

    function test_createTokenFor_rejectsOtherSigner() public {
        (address c, ) = makeAddrAndKey("claimedCreator");
        (, uint256 otherKey) = makeAddrAndKey("attacker");
        wqor.deposit{value: 20 ether}();
        wqor.approve(address(fac), type(uint256).max);

        MemeFactoryV3.CreateRequest memory req = MemeFactoryV3.CreateRequest({
            creator: c, name: "Fake", symbol: "FAKE", supply: 1, description: "", nonce: 1, deadline: block.timestamp + 1 hours
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(otherKey, fac.digest(req));
        vm.expectRevert(bytes("bad signature"));
        fac.createTokenFor(req, abi.encodePacked(r, s, v));
    }

    // ---------- fuzz ----------

    function testFuzz_buyNeverLowersTheProduct(uint64 raw) public {
        uint256 amountIn = bound(uint256(raw), 1e15, 5e18);
        (, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: amountIn}();
        uint256 kBefore = p.wqorReserve() * p.tokenReserve();

        uint256 deadline = block.timestamp + 1 hours;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, amountIn, 0, uint256(raw) + 1000, deadline);
        bytes memory sig = _signIntent(p, traderKey, s);
        (uint8 v, bytes32 r, bytes32 sv) = _permit(address(wqor), traderKey, trader, address(p), amountIn, deadline);
        p.swap(s, sig, deadline, v, r, sv);

        assertGe(p.wqorReserve() * p.tokenReserve(), kBefore);
    }

    // ---------- helpers ----------

    function _repeat(string memory s, uint256 n) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * n);
        for (uint256 i = 0; i < n; i++) {
            for (uint256 j = 0; j < b.length; j++) out[i * b.length + j] = b[j];
        }
        return string(out);
    }
}
