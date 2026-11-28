// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ReqoV5Registry.sol";

contract ReqoV5RegistryTest is Test {
    ReqoV5Registry registry;

    address token = address(0x1001);
    address pool = address(0x1002);
    address creator = address(0x1003);

    function setUp() public {
        registry = new ReqoV5Registry();
    }

    function test_factoryRegistersCanonicalToken() public {
        registry.register("REQO", token, pool, creator);

        assertEq(
            registry.tokenByTicker(keccak256("REQO")),
            token
        );
        assertEq(registry.poolOf(token), pool);
        assertEq(registry.creatorOf(token), creator);
    }

    function test_nonFactoryCannotRegister() public {
        vm.prank(creator);
        vm.expectRevert("factory only");
        registry.register("REQO", token, pool, creator);
    }

    function test_duplicateTickerRejected() public {
        registry.register("REQO", token, pool, creator);

        vm.expectRevert("ticker taken");
        registry.register(
            "REQO", address(0x2001), address(0x2002), creator
        );
    }

    function test_invalidTickersRejected() public {
        vm.expectRevert("bad ticker");
        registry.tickerKey("");

        vm.expectRevert("ticker must be A-Z or 0-9");
        registry.tickerKey("reqo");

        vm.expectRevert("bad ticker");
        registry.tickerKey("ABCDEFGHIJK");
    }

    function test_zeroAddressRejected() public {
        vm.expectRevert("zero address");
        registry.register("REQO", address(0), pool, creator);
    }

    function testFuzz_validTickerKey(
        uint8 a,
        uint8 b
    ) public {
        bytes memory s = new bytes(2);
        s[0] = bytes1(uint8(65 + a % 26));
        s[1] = bytes1(uint8(48 + b % 10));

        assertEq(registry.tickerKey(string(s)), keccak256(s));
    }
}
