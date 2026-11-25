// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// Checks that the official ML-DSA-87 vector file is present and well-formed:
// five cases, public keys 2,592 bytes, signatures 4,627 bytes.
// The vector is QoreChain's (qorechain/qorechain-pqc, vectors/ml-dsa-87.json, Apache-2.0),
// copied unmodified to test/vectors/ml-dsa-87.json.
// Live verification against QoreChain's precompiles is done with cast (see scripts/verify-diana.sh),
// because a local Foundry fork cannot run the chain's built-in precompiles.
contract MlDsaVectorsTest is Test {
    string internal json;

    function setUp() public {
        json = vm.readFile("test/vectors/ml-dsa-87.json");
    }

    function _field(uint256 i, string memory name) internal view returns (bytes memory) {
        return vm.parseJsonBytes(json, string.concat(".cases[", vm.toString(i), "].", name));
    }

    function test_vectorFileHasFiveCases() public view {
        for (uint256 i = 0; i < 5; i++) {
            _field(i, "publicKey");
        }
    }

    function test_publicKeysAre2592Bytes() public view {
        for (uint256 i = 0; i < 5; i++) {
            assertEq(_field(i, "publicKey").length, 2592, "public key size");
        }
    }

    function test_signaturesAre4627Bytes() public view {
        for (uint256 i = 0; i < 5; i++) {
            assertEq(_field(i, "signature").length, 4627, "signature size");
        }
    }

    function test_messagesFollowQoreChainPqcNaming() public view {
        for (uint256 i = 0; i < 5; i++) {
            bytes memory m = _field(i, "message");
            bytes memory p = bytes("qorechain-pqc/vector/");
            assertTrue(m.length >= p.length, "message long enough");
            for (uint256 j = 0; j < p.length; j++) {
                assertEq(uint8(m[j]), uint8(p[j]), "message prefix");
            }
        }
    }
}
