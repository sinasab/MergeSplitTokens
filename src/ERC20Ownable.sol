// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// import "solmate/auth/Owned.sol";
import "solmate/tokens/ERC20.sol";

import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ERC20Ownable is OwnableUpgradeable, ERC20Upgradeable {

    uint8 private _decimals;

    function init(string memory name, string memory symbol, uint8 decimals_) external initializer {
        _decimals = decimals_;
        __ERC20_init(name, symbol);
        __Ownable_init();
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}
