// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ReqoV4.sol";

// Stand-in for pqcVerify at 0x...0A01: accepts only messages with the QoreSign prefix,
// and returns a settable answer. The real precompile is exercised by the fork test.
contract MockPqc {
    bool public answer;

    function setAnswer(bool a) external {
        answer = a;
    }

    function pqcVerify(bytes calldata, bytes calldata, bytes calldata message) external view returns (bool) {
        bytes memory p = bytes("qorechain-msg-v1|qorechain-diana|");
        if (message.length < p.length) return false;
        for (uint256 i = 0; i < p.length; i++) {
            if (message[i] != p[i]) return false;
        }
        return answer;
    }
}

// Stand-in for pqcKeyStatus at 0x...0A02, using the documented return fields.
contract MockKeyStatus {
    mapping(address => bool) public registered;
    mapping(address => bytes) public keyOf;
    mapping(address => bool) public possession;

    function setKey(address account, bytes calldata pk, bool proven) external {
        registered[account] = true;
        keyOf[account] = pk;
        possession[account] = proven;
    }

    function pqcKeyStatus(address account) external view returns (bool, uint8, bytes memory, bool) {
        if (!registered[account]) return (false, 0, "", false);
        return (true, 1, keyOf[account], possession[account]);
    }
}

contract ReqoV4Test is Test {
    address internal constant PQC_VERIFY = 0x0000000000000000000000000000000000000a01;
    address internal constant PQC_KEY_STATUS = 0x0000000000000000000000000000000000000a02;

    WQOR internal wqor;
    MemeFactoryV4 internal fac;

    address internal creator = makeAddr("creator");
    bytes internal pk = hex"1234abcd";
    bytes internal sig = hex"beef";

    function setUp() public {
        vm.warp(1000);
        wqor = new WQOR();
        fac = new MemeFactoryV4(address(wqor));

        vm.etch(PQC_VERIFY, type(MockPqc).runtimeCode);
        MockPqc(PQC_VERIFY).setAnswer(true);
        vm.etch(PQC_KEY_STATUS, type(MockKeyStatus).runtimeCode);
        MockKeyStatus(PQC_KEY_STATUS).setKey(creator, pk, true);

        vm.deal(creator, 100 ether);
        vm.startPrank(creator);
        wqor.deposit{value: 50 ether}();
        wqor.approve(address(fac), type(uint256).max);
        vm.stopPrank();
    }

    function _create(uint256 nonce, uint256 deadline, string memory name, string memory symbol)
        internal
        returns (address)
    {
        vm.prank(creator);
        return fac.createToken(name, symbol, 1000, "a frog coin", nonce, deadline, pk, sig);
    }

    // ---------- the gate ----------

    function test_validSignatureLaunches() public {
        address t = _create(1, block.timestamp + 1 hours, "Frog", "CROAK");
        assertEq(fac.creatorOf(t), creator);
        assertEq(fac.tokenCount(), 1);
        assertEq(wqor.balanceOf(fac.poolOf(t)), 10e18, "seed is 10 WQOR");
    }

    function test_forgedSignatureReverts() public {
        MockPqc(PQC_VERIFY).setAnswer(false);
        vm.expectRevert(bytes("pqc: bad signature"));
        _create(1, block.timestamp + 1 hours, "Frog", "CROAK");
    }

    function test_missingPrecompileFailsClosed() public {
        vm.etch(PQC_VERIFY, hex"");
        vm.expectRevert(bytes("pqc unavailable"));
        _create(1, block.timestamp + 1 hours, "Frog", "CROAK");
    }

    function test_unregisteredKeyReverts() public {
        address stranger = makeAddr("stranger");
        vm.deal(stranger, 25 ether);
        vm.startPrank(stranger);
        wqor.deposit{value: 20 ether}();
        wqor.approve(address(fac), type(uint256).max);
        vm.stopPrank();

        vm.expectRevert(bytes("key not proven"));
        vm.prank(stranger);
        fac.createToken("Frog", "CROAK", 1000, "", 1, block.timestamp + 1 hours, pk, sig);
    }

    function test_unprovenPossessionReverts() public {
        // Registered, but the registration never proved possession of the secret key.
        address unproven = makeAddr("unproven");
        vm.deal(unproven, 25 ether);
        vm.startPrank(unproven);
        wqor.deposit{value: 20 ether}();
        wqor.approve(address(fac), type(uint256).max);
        vm.stopPrank();
        MockKeyStatus(PQC_KEY_STATUS).setKey(unproven, pk, false);

        vm.expectRevert(bytes("key not proven"));
        vm.prank(unproven);
        fac.createToken("Frog", "CROAK", 1000, "", 1, block.timestamp + 1 hours, pk, sig);
    }

    function test_keyNotOwnedByCallerReverts() public {
        // The caller's registered key is pk, but the submitted key is different.
        vm.expectRevert(bytes("key not owned"));
        vm.prank(creator);
        fac.createToken("Frog", "CROAK", 1000, "", 1, block.timestamp + 1 hours, hex"99", sig);
    }

    function test_expiredRequestReverts() public {
        vm.expectRevert(bytes("expired"));
        _create(1, block.timestamp - 1, "Frog", "CROAK");
    }

    function test_replayedNonceReverts() public {
        _create(7, block.timestamp + 1 hours, "Frog", "CROAK");
        vm.expectRevert(bytes("nonce used"));
        _create(7, block.timestamp + 1 hours, "Frog Two", "FROG2");
    }

    // ---------- the signed message ----------

    function test_messageStartsWithQoreSignPrefixAndChain() public view {
        bytes memory m = fac.messageFor(creator, 1, 2, "Frog", "CROAK", 1000, "");
        bytes memory expected = bytes("qorechain-msg-v1|qorechain-diana|");
        assertTrue(m.length > expected.length);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(uint8(m[i]), uint8(expected[i]));
        }
    }

    function test_messageBindsCreatorNonceAndDeadline() public view {
        bytes memory a = fac.messageFor(creator, 1, 2, "Frog", "CROAK", 1000, "");
        bytes memory b = fac.messageFor(creator, 2, 2, "Frog", "CROAK", 1000, "");
        bytes memory c = fac.messageFor(address(0xBEEF), 1, 2, "Frog", "CROAK", 1000, "");
        assertTrue(keccak256(a) != keccak256(b), "nonce changes the message");
        assertTrue(keccak256(a) != keccak256(c), "creator changes the message");
    }

    // ---------- F1: names and tickers ----------

    function test_F1_nonAsciiSymbolRejected() public {
        vm.expectRevert(bytes("symbol must be A-Z or 0-9"));
        _create(1, block.timestamp + 1 hours, "Fake", "\xd0\xa1USDC");
    }

    function test_F1_lowercaseSymbolRejected() public {
        vm.expectRevert(bytes("symbol must be A-Z or 0-9"));
        _create(1, block.timestamp + 1 hours, "Frog", "croak");
    }

    function test_F1_nonPrintableNameRejected() public {
        vm.expectRevert(bytes("name must be printable ASCII"));
        _create(1, block.timestamp + 1 hours, string(hex"0141"), "CROAK");
    }

    function test_F1_validTickerWithDigitsAccepted() public {
        address t = _create(1, block.timestamp + 1 hours, "Frog 2", "FROG2");
        assertEq(fac.creatorOf(t), creator);
    }
}
