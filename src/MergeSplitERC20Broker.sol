// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./ERC20Ownable.sol";
import "./MergeChecker.sol";

error AlreadySettled();
error NotSettled();

contract MergeSplitERC20Broker is MergeChecker {
    using SafeTransferLib for ERC20;

    // Dec 15 2022, converted to unix timestamp.
    // TODO(sina) model with someone to double-check this is a reasonable timestamp
    uint256 public constant UPPER_BOUND_TIMESTAMP = 1671062400;
    string public constant POW_PREFIX = "pow";
    string public constant POS_PREFIX = "pos";

    bool public merged = false;
    mapping(address => address) public powAddrs;
    mapping(address => address) public posAddrs;

    event NewSplit(
        address indexed underlyingToken,
        address posToken,
        address powToken
    );

    function posRedeemable() public view returns (bool) {
        return merged;
    }

    function powRedeemable() public view returns (bool) {
        bool redeemableViaTimeout = block.timestamp > UPPER_BOUND_TIMESTAMP;
        bool redeemableViaDetectedFork = block.chainid != 1;
        bool redeemable = redeemableViaTimeout || redeemableViaDetectedFork;
        return !merged && redeemable;
    }

    // TODO(sina) should this be incentivized?
    //  Maybe this contract gets deployed with a small amount of ETH, which gets paid out to whoever pokes this?
    function activateMerge() external {
        if (posRedeemable() || powRedeemable()) {
            revert AlreadySettled();
        }
        merged = getIsMerged();
    }

    function mint(address underlyingToken, uint256 amount) external {
        if (posRedeemable() || powRedeemable()) {
            revert AlreadySettled();
        }
        ERC20 token = ERC20(underlyingToken);
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (posAddrs[underlyingToken] == address(0)) {
            bytes32 salt = keccak256(abi.encodePacked(underlyingToken));
            posAddrs[underlyingToken] = address(
                new ERC20Ownable{salt: salt}(
                    string.concat(POS_PREFIX, token.name()),
                    string.concat(POS_PREFIX, token.symbol()),
                    token.decimals()
                )
            );
            powAddrs[underlyingToken] = address(
                new ERC20Ownable{salt: salt}(
                    string.concat(POW_PREFIX, token.name()),
                    string.concat(POW_PREFIX, token.symbol()),
                    token.decimals()
                )
            );
            emit NewSplit(
                underlyingToken,
                posAddrs[underlyingToken],
                powAddrs[underlyingToken]
            );
        }
        ERC20Ownable(powAddrs[underlyingToken]).mint(msg.sender, amount);
        ERC20Ownable(posAddrs[underlyingToken]).mint(msg.sender, amount);
    }

    function redeemPair(address underlyingToken, uint256 amount) external {
        // Burn equal units of each token from the user,
        // and send them a corresponding amount of the underlying.
        ERC20Ownable(powAddrs[underlyingToken]).burn(msg.sender, amount);
        ERC20Ownable(posAddrs[underlyingToken]).burn(msg.sender, amount);
        ERC20(underlyingToken).safeTransfer(msg.sender, amount);
    }

    function redeemPos(address underlyingToken, uint256 amount) external {
        if (!posRedeemable()) {
            revert NotSettled();
        }
        ERC20Ownable(posAddrs[underlyingToken]).burn(msg.sender, amount);
        ERC20(underlyingToken).safeTransfer(msg.sender, amount);
    }

    function redeemPow(address underlyingToken, uint256 amount) external {
        if (!powRedeemable()) {
            revert NotSettled();
        }
        ERC20Ownable(powAddrs[underlyingToken]).burn(msg.sender, amount);
        ERC20(underlyingToken).safeTransfer(msg.sender, amount);
    }
}
