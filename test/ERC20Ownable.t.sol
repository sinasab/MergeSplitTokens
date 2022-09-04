// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/ERC20Ownable.sol";

contract ERC20OwnableTest is Test {
    string public constant NAME = "TestToken";
    string public constant SYMBOL = "TKN";
    uint8 public constant DECIMALS = 18;

    ERC20Ownable public erc20Ownable;

    function setUp() public {
        erc20Ownable = new ERC20Ownable();
        erc20Ownable.init(NAME, SYMBOL, DECIMALS);
    }

    function testInitialization() public {
        assertEq(erc20Ownable.owner(), address(this));
    }

    // Test minting
    function testOwnerCanMint(address target, uint256 amount) public {
        vm.assume(target != address(this));
        vm.assume(target != address(0));
        vm.assume(amount != 0);

        erc20Ownable.mint(target, amount);

        assertEq(erc20Ownable.balanceOf(target), amount);
        assertEq(erc20Ownable.totalSupply(), amount);
    }

    function testNonOwnerCantMint(address nonOwner, address target, uint256 amount) public {
        vm.assume(nonOwner != address(this));
        vm.assume(target != address(0));
        vm.assume(amount != 0);

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");

        erc20Ownable.mint(target, amount);
    }

    // Test burning
    function testOwnerCanBurn(address target, uint256 amount) public {
        vm.assume(target != address(this));
        vm.assume(amount != 0);

        erc20Ownable.mint(target, amount);

        assertEq(erc20Ownable.balanceOf(target), amount);
        assertEq(erc20Ownable.totalSupply(), amount);

        erc20Ownable.burn(target, amount);

        assertEq(erc20Ownable.balanceOf(target), 0);
        assertEq(erc20Ownable.totalSupply(), 0);
    }

    function testNonOwnerCantBurn(address nonOwner, address target, uint256 amount) public {
        vm.assume(nonOwner != address(this));
        vm.assume(target != address(0));
        vm.assume(amount != 0);

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");

        erc20Ownable.burn(target, amount);
    }
}
