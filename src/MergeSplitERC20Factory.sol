// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./ERC20Ownable.sol";
import "./MergeChecker.sol";
import "./Spawner.sol";

error AlreadySettled();
error NotSettled();

contract MergeSplitERC20Factory is MergeChecker, Spawner {
    using SafeTransferLib for ERC20;

    // Dec 15 2022 midnight GMT, converted to unix timestamp.
    uint256 public constant POS_UPPER_BOUND_TIMESTAMP = 1671062400;
    string public constant POW_PREFIX = "pow";
    string public constant POS_PREFIX = "pos";

    mapping(ERC20 => ERC20Ownable) public powAddrs;
    mapping(ERC20 => ERC20Ownable) public posAddrs;

    event NewSplit(
        ERC20 indexed underlyingToken,
        ERC20Ownable posToken,
        ERC20Ownable powToken
    );

    constructor() {
        ERC20Ownable impl = new ERC20Ownable();
        impl.init("impl", "impl", 18);

        _setLogicContract(address(impl));
    }

    function posRedeemable() public view returns (bool) {
        return getIsMerged();
    }

    function powRedeemable() public view returns (bool) {
        bool redeemableViaTimeout = block.timestamp > POS_UPPER_BOUND_TIMESTAMP;
        bool redeemableViaDetectedFork = block.chainid != 1;
        bool redeemable = redeemableViaTimeout || redeemableViaDetectedFork;
        return !posRedeemable() && redeemable;
    }

    function mint(ERC20 underlyingToken, uint256 amount) external {
        if (posRedeemable() || powRedeemable()) {
            revert AlreadySettled();
        }
        underlyingToken.safeTransferFrom(msg.sender, address(this), amount);
        ERC20Ownable pos = posAddrs[underlyingToken];
        ERC20Ownable pow;
        if (address(pos) == address(0)) {
            string memory name = underlyingToken.name();
            string memory symbol = underlyingToken.symbol();
            pos = ERC20Ownable(_cloneMergeSplitToken(
                address(underlyingToken),
                string.concat(POS_PREFIX, name),
                string.concat(POS_PREFIX, symbol),
                underlyingToken.decimals()
            ));
            pow = ERC20Ownable(_cloneMergeSplitToken(
                address(underlyingToken),
                string.concat(POW_PREFIX, name),
                string.concat(POW_PREFIX, symbol),
                underlyingToken.decimals()
            ));
            posAddrs[underlyingToken] = pos;
            powAddrs[underlyingToken] = pow;
            emit NewSplit(underlyingToken, pos, pow);
        } else {
            pow = powAddrs[underlyingToken];
        }
        ERC20Ownable(pos).mint(msg.sender, amount);
        ERC20Ownable(pow).mint(msg.sender, amount);
    }

    function redeemPair(ERC20 underlyingToken, uint256 amount) external {
        // Burn equal units of each token from the user,
        // and send them a corresponding amount of the underlying.
        posAddrs[underlyingToken].burn(msg.sender, amount);
        powAddrs[underlyingToken].burn(msg.sender, amount);
        ERC20(underlyingToken).safeTransfer(msg.sender, amount);
    }

    function redeemPos(ERC20 underlyingToken, uint256 amount) external {
        if (!posRedeemable()) {
            revert NotSettled();
        }
        posAddrs[underlyingToken].burn(msg.sender, amount);
        underlyingToken.safeTransfer(msg.sender, amount);
    }

    function redeemPow(ERC20 underlyingToken, uint256 amount) external {
        if (!powRedeemable()) {
            revert NotSettled();
        }
        powAddrs[underlyingToken].burn(msg.sender, amount);
        underlyingToken.safeTransfer(msg.sender, amount);
    }
}
