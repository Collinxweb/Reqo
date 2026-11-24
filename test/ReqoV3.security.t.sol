// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "../src/ReqoV3.sol";

// Tests for the findings in docs/SECURITY-REVIEW.md. Each documents current behaviour.
// F1 tests assert what the contract accepts today and flip once the v4 validation ships.
contract ReqoV3SecurityTest is Test {
    WQOR internal wqor;
    MemeFactoryV3 internal fac;
    address internal creator = makeAddr("creator");
    address internal trader;
    uint256 internal traderKey;

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

    function _launch() internal returns (MemeTokenV3 t, PoolV3 p) {
        vm.prank(creator);
        address ta = fac.createToken("Frog", "CROAK", 1000, "a frog coin");
        t = MemeTokenV3(ta);
        p = PoolV3(fac.poolOf(ta));
    }

    function _permit(address token, uint256 key, address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            owner, spender, value, IERC20Permit(token).nonces(owner), deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
        (v, r, s) = vm.sign(key, digest);
    }

    // F1: a non-ASCII symbol (bytes d0 a1, Cyrillic С) is accepted on-chain.
    function test_F1_nonAsciiSymbolAccepted() public {
        vm.prank(creator);
        address t = fac.createToken("Fake USDC", "\xd0\xa1USDC", 1000, "");
        assertTrue(t != address(0));
    }

    // F1: two tokens can share a symbol.
    function test_F1_duplicateSymbolAccepted() public {
        vm.startPrank(creator);
        fac.createToken("Dog", "DOG", 1000, "");
        fac.createToken("Dog Two", "DOG", 1000, "");
        vm.stopPrank();
        assertEq(fac.tokenCount(), 2);
    }

    // F2: a third party submits the creator's signed request and pays the seed.
    function test_F2_thirdPartyRelaysCreatorRequest() public {
        (address c, uint256 ck) = makeAddrAndKey("signedCreator");
        wqor.deposit{value: 20 ether}();
        wqor.approve(address(fac), type(uint256).max);
        uint256 signerWqorBefore = wqor.balanceOf(c);

        MemeFactoryV3.CreateRequest memory req = MemeFactoryV3.CreateRequest({
            creator: c, name: "Relayed", symbol: "RLY", supply: 500, description: "",
            nonce: 1, deadline: block.timestamp + 1 hours
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ck, fac.digest(req));
        // This test contract is the third party: it pays the seed, the signer does not.
        address t = fac.createTokenFor(req, abi.encodePacked(r, s, v));

        assertEq(fac.creatorOf(t), c);
        assertEq(wqor.balanceOf(c), signerWqorBefore, "signer's WQOR untouched");
    }

    // F3: a front-run permit does not break the swap, because the pool then skips its own permit.
    function test_F3_permitFrontRunDoesNotBreakSwap() public {
        (, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: 1 ether}();

        uint256 deadline = block.timestamp + 1 hours;
        uint256 expectedOut = p.quoteOut(true, 1e18);
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, 1e18, 0, 1, deadline);
        (uint8 iv, bytes32 ir, bytes32 is_) = vm.sign(traderKey, p.hashIntent(s));
        bytes memory sig = abi.encodePacked(ir, is_, iv);
        (uint8 v, bytes32 r, bytes32 sv) = _permit(address(wqor), traderKey, trader, address(p), 1e18, deadline);

        // An attacker submits the trader's permit first.
        wqor.permit(trader, address(p), 1e18, deadline, v, r, sv);
        // The trader's swap still succeeds with the same permit data.
        uint256 out = p.swap(s, sig, deadline, v, r, sv);
        assertEq(out, expectedOut);
    }

    // F4: tokens sent straight to a pool do not change the price, and nothing can send them back out.
    function test_F4_donationDoesNotChangePrice() public {
        (MemeTokenV3 t, PoolV3 p) = _launch();
        vm.prank(trader);
        wqor.deposit{value: 1 ether}();
        uint256 deadline = block.timestamp + 1 hours;
        PoolV3.SwapIntent memory s = PoolV3.SwapIntent(trader, true, 1e18, 0, 1, deadline);
        (uint8 iv, bytes32 ir, bytes32 is_) = vm.sign(traderKey, p.hashIntent(s));
        (uint8 v, bytes32 r, bytes32 sv) = _permit(address(wqor), traderKey, trader, address(p), 1e18, deadline);
        p.swap(s, abi.encodePacked(ir, is_, iv), deadline, v, r, sv);

        uint256 tokenReserveBefore = p.tokenReserve();
        uint256 quoteBefore = p.quoteOut(true, 1e18);
        uint256 donated = t.balanceOf(trader) / 2;
        vm.prank(trader);
        t.transfer(address(p), donated);

        assertEq(p.tokenReserve(), tokenReserveBefore, "reserve ignores donation");
        assertEq(p.quoteOut(true, 1e18), quoteBefore, "price ignores donation");
        assertEq(t.balanceOf(address(p)), tokenReserveBefore + donated, "donation sits in the pool");
    }

    // WQOR: deposit and withdraw return the native QOR.
    function test_wqorWithdrawReturnsNative() public {
        vm.prank(trader);
        wqor.deposit{value: 2 ether}();
        uint256 before = trader.balance;
        vm.prank(trader);
        wqor.withdraw(2 ether);
        assertEq(trader.balance, before + 2 ether);
        assertEq(wqor.balanceOf(trader), 0);
    }
}
