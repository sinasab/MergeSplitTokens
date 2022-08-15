// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "solmate/test/utils/mocks/MockERC20.sol";
import "../src/MergeChecker.sol";

contract MergeCheckerTest is Test {
    MergeChecker public checker;

    function setUp() public {
        checker = new MergeChecker();
    }

    function testGetIsMergedEip3675() public {
        vm.difficulty(0);
        assertEq(checker.getIsMergedEip3675(), true);
    }

    function testGetIsMergedEip3675False(uint256 diff) public {
        vm.assume(diff != 0);
        vm.difficulty(diff);
        assertEq(checker.getIsMergedEip3675(), false);
    }

    function testGetIsMergedEip4399(uint256 diff) public {
        vm.assume(diff > 2 ** 64);
        vm.difficulty(diff);
        assertEq(checker.getIsMergedEip4399(), true);
    }

    function testGetIsMergedEip4399False(uint256 diff) public {
        vm.assume(diff <= 2 ** 64);
        vm.difficulty(diff);
        assertEq(checker.getIsMergedEip4399(), false);
    }

    function testGetIsMerged(uint256 diff) public {
        vm.difficulty(0);
        assertEq(checker.getIsMerged(), true);

        vm.assume(diff > 2 ** 64);
        vm.difficulty(diff);
        assertEq(checker.getIsMerged(), true);
    }

    function testGetIsMergedFalse(uint256 diff) public {
        diff = bound(diff, 1, 2 ** 64);
        vm.difficulty(diff);
        assertEq(checker.getIsMerged(), false);
    }
}
