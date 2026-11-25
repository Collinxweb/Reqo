// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// Runs QoreChain's official ML-DSA-87 vectors (qorechain/qorechain-pqc, vectors/ml-dsa-87.json,
// Apache-2.0, copied unmodified into test/vectors/) against the live pqcVerify precompile on
// Diana, and checks the documented pqcKeyStatus result for an unregistered account.
// Run: forge test --match-contract MlDsaVectorsForkTest -vv
contract MlDsaVectorsForkTest is Test {
    address constant PQC_VERIFY = 0x0000000000000000000000000000000000000a01;
    address constant PQC_KEY_STATUS = 0x0000000000000000000000000000000000000a02;
    bytes4 constant VERIFY_SELECTOR = bytes4(keccak256("pqcVerify(bytes,bytes,bytes)"));
    bytes4 constant KEY_SELECTOR = bytes4(keccak256("pqcKeyStatus(address)"));

    string internal json;

    function setUp() public {
        vm.createSelectFork("https://evm-testnet.qore.host");
        json = vm.readFile("test/vectors/ml-dsa-87.json");
    }

    // The safe pattern from QoreChain: staticcall, require a 32-byte bool, then decode it.
    function _verify(bytes memory pk, bytes memory sig, bytes memory msg_) internal view returns (bool) {
        (bool ok, bytes memory out) = PQC_VERIFY.staticcall(abi.encodeWithSelector(VERIFY_SELECTOR, pk, sig, msg_));
        require(ok && out.length == 32, "pqc call failed");
        return abi.decode(out, (bool));
    }

    function _case(uint256 i, string memory field) internal view returns (bytes memory) {
        return vm.parseJsonBytes(json, string.concat(".cases[", vm.toString(i), "].", field));
    }

    function test_vectorFileHasFiveCasesWithFipsSizes() public view {
        for (uint256 i = 0; i < 5; i++) {
            assertEq(_case(i, "publicKey").length, 2592, "public key is 2592 bytes");
            assertEq(_case(i, "signature").length, 4627, "signature is 4627 bytes");
        }
    }

    function test_allOfficialVectorsVerifyOnDiana() public view {
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(_verify(_case(i, "publicKey"), _case(i, "signature"), _case(i, "message")), "vector verifies");
        }
    }

    function test_tamperedMessageIsRejectedWithoutRevert() public view {
        bytes memory m = _case(0, "message");
        m[m.length - 1] = bytes1(uint8(m[m.length - 1]) ^ 0x01);
        assertFalse(_verify(_case(0, "publicKey"), _case(0, "signature"), m));
    }

    function test_wrongLengthSignatureIsRejectedWithoutRevert() public view {
        assertFalse(_verify(_case(0, "publicKey"), new bytes(100), _case(0, "message")));
    }

    function test_keyStatusForUnregisteredAccountMatchesDocs() public view {
        (bool ok, bytes memory out) =
            PQC_KEY_STATUS.staticcall(abi.encodeWithSelector(KEY_SELECTOR, address(0x1)));
        assertTrue(ok, "pqcKeyStatus call succeeded");
        (bool registered, uint8 alg, bytes memory pubkey, bool proven) = abi.decode(out, (bool, uint8, bytes, bool));
        assertFalse(registered);
        assertEq(alg, 0);
        assertEq(pubkey.length, 0);
        assertFalse(proven);
    }

    function test_gasOfOneVerification() public {
        uint256 g0 = gasleft();
        _verify(_case(0, "publicKey"), _case(0, "signature"), _case(0, "message"));
        emit log_named_uint("gas for one pqcVerify staticcall", g0 - gasleft());
    }
}
