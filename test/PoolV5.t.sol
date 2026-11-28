// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ReqoV5.sol";
import "../src/PoolV5.sol";

contract PoolV5Test is Test {
    MemeFactoryV5 factory;
    WQOR wqor;
    PoolV5 pool;
    IERC20 token;

    address creator = address(0xBEEF);
    address stranger = address(0xBAD);
    bytes pk = hex"1234";
    bytes sig = hex"5678";

    function setUp() public {
        wqor = new WQOR();
        factory = new MemeFactoryV5(address(wqor));

        vm.deal(creator, 100 ether);
        vm.startPrank(creator);
        wqor.deposit{value: 20 ether}();
        wqor.approve(address(factory), type(uint256).max);
        vm.stopPrank();

        vm.mockCall(
            factory.PQC_KEY_STATUS(),
            abi.encodeWithSelector(factory.KEY_SELECTOR(), creator),
            abi.encode(true, uint8(1), pk, true)
        );
        vm.mockCall(
            factory.PQC_VERIFY(),
            bytes4(factory.VERIFY_SELECTOR()),
            abi.encode(true)
        );

        vm.prank(creator);
        address t = factory.createToken(
            "Test Token", "TEST", 1000, "test",
            1, block.timestamp + 1 hours, pk, sig
        );

        token = IERC20(t);
        pool = PoolV5(factory.poolOf(t));

        // Test-only funding: simulate the creator having acquired
        // tokens from the pool. This is not a production withdrawal.
        vm.prank(address(pool));
        token.transfer(creator, 100e18);

        vm.startPrank(creator);
        token.approve(address(pool), type(uint256).max);
        wqor.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testCreatorAndCanonicalPool() public view {
        assertEq(pool.creator(), creator);
        assertEq(pool.token(), address(token));
        assertEq(pool.wqor(), address(wqor));
        assertTrue(pool.seeded());
    }

    function testProportionalTopUp() public {
        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();

        // Use an exact ratio based on the current recorded reserves.
        uint256 ta = tr / 100;
        uint256 wa = wr / 100;

        vm.prank(creator);
        pool.topUp(ta, wa);

        assertEq(pool.tokenReserve(), tr + ta);
        assertEq(pool.wqorReserve(), wr + wa);
        assertEq(token.balanceOf(address(pool)), tr + ta - 100e18);
    }

    function testUnauthorizedTopUp() public {
        vm.prank(stranger);
        vm.expectRevert("creator only");
        pool.topUp(1e18, 1e18);
    }

    function testZeroAmounts() public {
        vm.prank(creator);
        vm.expectRevert("zero amount");
        pool.topUp(0, 1e18);
    }

    function testIncorrectRatio() public {
        vm.prank(creator);
        vm.expectRevert("incorrect ratio");
        pool.topUp(1e18, 1e18);
    }

    function testInsufficientAllowanceRollsBack() public {
        vm.prank(creator);
        token.approve(address(pool), 0);

        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();

        vm.prank(creator);
        vm.expectRevert();
        pool.topUp(tr / 100, wr / 100);

        assertEq(pool.tokenReserve(), tr);
        assertEq(pool.wqorReserve(), wr);
    }

    function testDonationDoesNotChangeReserves() public {
        uint256 tr = pool.tokenReserve();
        uint256 wr = pool.wqorReserve();

        vm.prank(creator);
        token.transfer(address(pool), 1e18);

        assertEq(pool.tokenReserve(), tr);
        assertEq(pool.wqorReserve(), wr);
    }
}
