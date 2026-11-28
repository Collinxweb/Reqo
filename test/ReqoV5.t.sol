// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ReqoV5.sol";

contract ReqoV5Test is Test {
    MemeFactoryV5 factory;
    WQOR wqor;
    address creator = address(0xBEEF);
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
    }

    function launch(string memory symbol, uint256 nonce)
        internal returns (address)
    {
        vm.prank(creator);
        return factory.createToken(
            "Test Token", symbol, 1000, "test",
            nonce, block.timestamp + 1 hours, pk, sig
        );
    }

    function testCanonicalLaunch() public {
        address token = launch("REQO", 1);
        bytes32 key = factory.registry().tickerKey("REQO");
        assertEq(factory.registry().tokenByTicker(key), token);
        assertEq(factory.registry().creatorOf(token), creator);
        assertEq(factory.registry().poolOf(token), factory.poolOf(token));
        assertTrue(factory.nonceUsed(creator, 1));
        assertEq(factory.tokenCount(), 1);
    }

    function testDuplicateTicker() public {
        launch("REQO", 1);
        vm.expectRevert("ticker taken");
        launch("REQO", 2);
        assertFalse(factory.nonceUsed(creator, 2));
    }

    function testReplay() public {
        launch("REQO", 1);
        vm.expectRevert("nonce used");
        launch("OTHER", 1);
    }

    function testExpired() public {
        vm.warp(100);
        vm.prank(creator);
        vm.expectRevert("expired");
        factory.createToken("Test", "TEST", 1000, "", 1, 99, pk, sig);
    }

    function testInvalidTicker() public {
        vm.expectRevert("symbol must be A-Z or 0-9");
        launch("bad", 1);
    }

    function testUnprovenKey() public {
        vm.mockCall(
            factory.PQC_KEY_STATUS(),
            abi.encodeWithSelector(factory.KEY_SELECTOR(), creator),
            abi.encode(false, uint8(1), pk, false)
        );
        vm.expectRevert("key not proven");
        launch("REQO", 1);
    }
}
