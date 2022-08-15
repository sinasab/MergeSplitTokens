// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Stateless contract that aggregates a few methods to check whether or not the merge has occurred.
contract MergeChecker {
    // See https://eips.ethereum.org/EIPS/eip-3675#replacing-difficulty-with-0.
    function getIsMergedEip3675() public view returns (bool) {
        return block.difficulty == 0;
    }

    // See https://eips.ethereum.org/EIPS/eip-4399#using-264-threshold-to-determine-pos-blocks.
    function getIsMergedEip4399() public view returns (bool) {
        // TODO(sina) model with someone to double-check it should work
        return block.difficulty > 2 ** 64;
    }

    // True if either method indicates the merge has taken place.
    function getIsMerged() public view returns (bool) {
        return getIsMergedEip3675() || getIsMergedEip4399();
    }
}
