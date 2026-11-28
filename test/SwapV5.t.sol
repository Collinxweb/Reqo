// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./PoolV5.t.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract SwapV5Test is PoolV5Test {
    uint256 traderKey = 0xA11CE;
    address trader;

    function setUp() public override {
        super.setUp();
        trader = vm.addr(traderKey);

        vm.deal(trader, 10 ether);
        vm.startPrank(trader);
        wqor.deposit{value: 5 ether}();
        wqor.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function topUpLiquidity() internal {
        uint256 ta = pool.tokenReserve() / 100;
        uint256 wa = pool.wqorReserve() / 100;
        vm.prank(creator);
        pool.topUp(ta, wa);
    }

    function intent(
        bool buy,
        uint256 amount,
        uint256 minOut,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (PoolV3.SwapIntent memory s) {
        s = PoolV3.SwapIntent({
            trader: trader,
            buy: buy,
            amountIn: amount,
            minOut: minOut,
            nonce: nonce,
            deadline: deadline
        });
    }

    function signIntent(PoolV3.SwapIntent memory s)
        internal view returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 ss) =
            vm.sign(traderKey, pool.hashIntent(s));
        return abi.encodePacked(r, ss, v);
    }

    function execute(
        PoolV3.SwapIntent memory s,
        bytes memory signature
    ) internal returns (uint256) {
        return pool.swap(s, signature, 0, 0, bytes32(0), bytes32(0));
    }

    function testSignedBuyAfterTopUp() public {
        topUpLiquidity();
        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();
        uint256 k = tr * wr;

        uint256 quote = pool.quoteOut(true, 1 ether);
        PoolV3.SwapIntent memory s =
            intent(true, 1 ether, quote, 1, block.timestamp + 1 hours);

        uint256 out = execute(s, signIntent(s));

        assertEq(out, quote);
        assertEq(pool.tokenReserve(), tr - out);
        assertEq(pool.wqorReserve(), wr + 1 ether);
        assertEq(token.balanceOf(trader), out);
        assertTrue(pool.nonceUsed(trader, 1));
        assertGe(pool.tokenReserve() * pool.wqorReserve(), k);
    }

    function testSignedSellAfterTopUp() public {
        topUpLiquidity();

        uint256 buyQuote = pool.quoteOut(true, 1 ether);
        PoolV3.SwapIntent memory buy =
            intent(true, 1 ether, buyQuote, 1, block.timestamp + 1 hours);
        execute(buy, signIntent(buy));

        vm.prank(trader);
        token.approve(address(pool), type(uint256).max);

        uint256 amount = token.balanceOf(trader) / 2;
        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();
        uint256 k = tr * wr;
        uint256 quote = pool.quoteOut(false, amount);

        PoolV3.SwapIntent memory sell =
            intent(false, amount, quote, 2, block.timestamp + 1 hours);

        uint256 out = execute(sell, signIntent(sell));

        assertEq(out, quote);
        assertEq(pool.tokenReserve(), tr + amount);
        assertEq(pool.wqorReserve(), wr - out);
        assertTrue(pool.nonceUsed(trader, 2));
        assertGe(pool.tokenReserve() * pool.wqorReserve(), k);
    }

    function testReplayRejected() public {
        PoolV3.SwapIntent memory s =
            intent(true, 1 ether, 0, 3, block.timestamp + 1 hours);
        bytes memory signature = signIntent(s);
        execute(s, signature);

        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();

        vm.expectRevert(bytes("nonce used"));
        execute(s, signature);

        assertEq(pool.tokenReserve(), tr);
        assertEq(pool.wqorReserve(), wr);
    }

    function testExpiredSignatureRejected() public {
        PoolV3.SwapIntent memory s =
            intent(true, 1 ether, 0, 4, block.timestamp + 1);
        bytes memory signature = signIntent(s);
        vm.warp(block.timestamp + 2);

        vm.expectRevert(bytes("expired"));
        execute(s, signature);
        assertFalse(pool.nonceUsed(trader, 4));
    }

    function testSlippageRollsBack() public {
        topUpLiquidity();
        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();

        PoolV3.SwapIntent memory s = intent(
            true, 1 ether, pool.quoteOut(true, 1 ether) + 1,
            5, block.timestamp + 1 hours
        );

        bytes memory signature = signIntent(s);
        vm.expectRevert(bytes("slippage"));
        execute(s, signature);

        assertEq(pool.tokenReserve(), tr);
        assertEq(pool.wqorReserve(), wr);
        assertFalse(pool.nonceUsed(trader, 5));
    }

    function testTamperedIntentRejected() public {
        PoolV3.SwapIntent memory s =
            intent(true, 1 ether, 0, 6, block.timestamp + 1 hours);
        bytes memory signature = signIntent(s);

        s.amountIn = 2 ether;

        vm.expectRevert(bytes("bad signature"));
        execute(s, signature);
        assertFalse(pool.nonceUsed(trader, 6));
    }

    function permitSignature(
        IERC20Permit input,
        uint256 amount,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 ss) {
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                trader,
                address(pool),
                amount,
                input.nonces(trader),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                input.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        return vm.sign(traderKey, digest);
    }

    function testBuyWithZeroAllowancePermit() public {
        vm.prank(trader);
        wqor.approve(address(pool), 0);

        uint256 amount = 1 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonceBefore = wqor.nonces(trader);

        assertEq(wqor.allowance(trader, address(pool)), 0);

        PoolV3.SwapIntent memory s = intent(
            true, amount, pool.quoteOut(true, amount),
            101, deadline
        );

        (uint8 v, bytes32 r, bytes32 ss) = permitSignature(
            IERC20Permit(address(wqor)), amount, deadline
        );

        uint256 out = pool.swap(
            s, signIntent(s), deadline, v, r, ss
        );

        assertGt(out, 0);
        assertEq(token.balanceOf(trader), out);
        assertEq(wqor.nonces(trader), nonceBefore + 1);
        assertEq(wqor.allowance(trader, address(pool)), 0);
        assertTrue(pool.nonceUsed(trader, 101));
    }

    function testSellWithZeroAllowancePermit() public {
        PoolV3.SwapIntent memory buy = intent(
            true, 1 ether, 0, 102, block.timestamp + 1 hours
        );
        execute(buy, signIntent(buy));

        uint256 amount = token.balanceOf(trader) / 2;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonceBefore = IERC20Permit(address(token)).nonces(trader);

        assertEq(token.allowance(trader, address(pool)), 0);

        PoolV3.SwapIntent memory sell = intent(
            false, amount, pool.quoteOut(false, amount),
            103, deadline
        );

        (uint8 v, bytes32 r, bytes32 ss) = permitSignature(
            IERC20Permit(address(token)), amount, deadline
        );

        uint256 out = pool.swap(
            sell, signIntent(sell), deadline, v, r, ss
        );

        assertGt(out, 0);
        assertEq(IERC20Permit(address(token)).nonces(trader), nonceBefore + 1);
        assertEq(token.allowance(trader, address(pool)), 0);
        assertTrue(pool.nonceUsed(trader, 103));
    }
}
