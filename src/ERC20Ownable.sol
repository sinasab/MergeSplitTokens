// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "solmate/auth/Owned.sol";
import "solmate/tokens/ERC20.sol";

contract ERC20Ownable is Owned, ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals)
        Owned(msg.sender)
        ERC20(name, symbol, decimals)
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyOwner {
        _burn(from, amount);
    }
}
