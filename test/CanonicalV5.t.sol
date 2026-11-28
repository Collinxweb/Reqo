// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ReqoV5.t.sol";

contract CanonicalV5Test is ReqoV5Test {
    function testForeignPoolNotCanonical() public {
        address token = launch("CANON", 1);
        address canonical = factory.poolOf(token);

        PoolV5 foreign = new PoolV5(
            token, address(wqor), creator
        );

        assertTrue(canonical != address(0));
        assertTrue(canonical != address(foreign));
        assertEq(factory.poolOf(token), canonical);
        assertEq(factory.registry().poolOf(token), canonical);
    }

    function testForeignFactoryCannotRegisterHere() public {
        address token = launch("FIRST", 1);
        MemeFactoryV5 other = new MemeFactoryV5(address(wqor));

        assertEq(other.poolOf(token), address(0));
        assertEq(other.registry().poolOf(token), address(0));
        assertEq(factory.registry().poolOf(token), factory.poolOf(token));
    }

    function testDuplicateCannotReplaceCanonicalPool() public {
        address token = launch("UNIQUE", 1);
        address original = factory.poolOf(token);

        vm.expectRevert("ticker taken");
        launch("UNIQUE", 2);

        assertEq(factory.poolOf(token), original);
        assertEq(factory.registry().poolOf(token), original);
        assertFalse(factory.nonceUsed(creator, 2));
    }

    function testUnknownTokenHasNoCanonicalPool() public view {
        address unknown = address(0x123456);
        assertEq(factory.poolOf(unknown), address(0));
        assertEq(factory.registry().poolOf(unknown), address(0));
    }
}
