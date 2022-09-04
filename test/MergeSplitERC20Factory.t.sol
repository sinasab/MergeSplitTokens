// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/utils/Create2.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/ERC20Ownable.sol";
import "../src/MergeSplitERC20Factory.sol";

contract MergeSplitERC20FactoryTest is Test {
    using stdStorage for StdStorage;

    string public constant NAME = "TestToken";
    string public constant SYMBOL = "TKN";
    uint8 public constant DECIMALS = 18;

    MockERC20 public mockERC20;
    MergeSplitERC20Factory public mergeSplitFactory;
    StdStorage public mergedSlot;

    event NewSplit(
        address indexed underlyingToken,
        address posToken,
        address powToken
    );

    function setUp() public {
        mockERC20 = new MockERC20(NAME, SYMBOL, DECIMALS);
        mergeSplitFactory = new MergeSplitERC20Factory();
        // TODO(sina) I think chainid cheatcode may be broken in setup
        vm.chainId(1);
    }

    function testPosRedeemable(bool set) public {
        setPosRedeemable(set);
        assertEq(mergeSplitFactory.posRedeemable(), set);
    }

    function testPowRedeemable(bool set) public {
        setPowRedeemable(set);
        assertEq(mergeSplitFactory.powRedeemable(), set);
    }

    function testPowRedeemableFuzzedTs(uint256 ts) public {
        setPosRedeemable(false);
        vm.assume(ts > mergeSplitFactory.POS_UPPER_BOUND_TIMESTAMP());
        vm.warp(ts);
        assertEq(mergeSplitFactory.powRedeemable(), true);
    }

    function testPowRedeemableFuzzedChainId(uint256 cid) public {
        setPosRedeemable(false);
        vm.assume(cid != 1);
        vm.chainId(cid);
        assertEq(mergeSplitFactory.powRedeemable(), true);
    }

    function testPowRedeemableFalseWhenMerged() public {
        setPowRedeemable(true);
        setPosRedeemable(true);
        assertEq(mergeSplitFactory.powRedeemable(), false);
    }

    function testPowRedeemableFalseWhenUnderTs() public {
        setPowRedeemable(true);
        vm.chainId(1);
        vm.warp(mergeSplitFactory.POS_UPPER_BOUND_TIMESTAMP());
        assertEq(mergeSplitFactory.powRedeemable(), false);
    }

    function testPowRedeemableFalseFuzzedTs(uint256 ts) public {
        setPowRedeemable(true);
        vm.chainId(1);
        vm.assume(ts <= mergeSplitFactory.POS_UPPER_BOUND_TIMESTAMP());
        vm.warp(ts);
        assertEq(mergeSplitFactory.powRedeemable(), false);
    }

    function testMintRevertsIfAlreadyRedeemable(ERC20 erc20, uint256 amt)
        public
    {
        // Should revert if either pos or pow is redeemable already.
        setPosRedeemable(true);
        setPowRedeemable(false);
        vm.expectRevert(AlreadySettled.selector);
        mergeSplitFactory.mint(erc20, amt);

        setPosRedeemable(false);
        setPowRedeemable(true);
        vm.expectRevert(AlreadySettled.selector);
        mergeSplitFactory.mint(erc20, amt);
    }

    function testMintSucceedsForNewUnderlying(uint256 amt) public {
        setPosRedeemable(false);
        setPowRedeemable(false);
        // Before; assert facts about statevars, token balances,
        // and predict newly deployed token addrs.
        assertEq(address(mergeSplitFactory.posAddrs(mockERC20)), address(0));
        assertEq(address(mergeSplitFactory.powAddrs(mockERC20)), address(0));
        assertEq(mockERC20.balanceOf(address(this)), 0);
        assertEq(mockERC20.balanceOf(address(mergeSplitFactory)), 0);
        bytes32 salt = keccak256(abi.encodePacked(address(mockERC20)));
        address predictedPosTokenAddr = Create2.computeAddress(
            salt,
            keccak256(
                abi.encodePacked(
                    type(ERC20Ownable).creationCode,
                    abi.encode("posTestToken", "posTKN", 18)
                )
            ),
            address(mergeSplitFactory)
        );
        address predictedPowTokenAddr = Create2.computeAddress(
            salt,
            keccak256(
                abi.encodePacked(
                    type(ERC20Ownable).creationCode,
                    abi.encode("powTestToken", "powTKN", 18)
                )
            ),
            address(mergeSplitFactory)
        );
        vm.expectEmit(true, true, true, true, address(mergeSplitFactory));
        emit NewSplit(
            address(mockERC20),
            predictedPosTokenAddr,
            predictedPowTokenAddr
        );

        // Act.
        mockERC20.approve(address(mergeSplitFactory), type(uint256).max);
        mockERC20.mint(address(this), amt);
        assertEq(mockERC20.balanceOf(address(this)), amt);
        mergeSplitFactory.mint(mockERC20, amt);

        // After, assert updated statevars, token balances.
        assertEq(
            address(mergeSplitFactory.posAddrs(mockERC20)),
            predictedPosTokenAddr
        );
        assertEq(
            address(mergeSplitFactory.powAddrs(mockERC20)),
            predictedPowTokenAddr
        );
        assertEq(mockERC20.balanceOf(address(this)), 0);
        assertEq(mockERC20.balanceOf(address(mergeSplitFactory)), amt);
        assertEq(ERC20(predictedPosTokenAddr).balanceOf(address(this)), amt);
        assertEq(ERC20(predictedPowTokenAddr).balanceOf(address(this)), amt);
    }

    function testMintSucceedsForExistingUnderlying(uint256 amt1, uint256 amt2)
        public
    {
        // Prepare.
        vm.assume(amt1 <= type(uint256).max - amt2);
        testMintSucceedsForNewUnderlying(amt1);
        address alice = address(0xABCD);
        mockERC20.mint(alice, amt2);
        assertEq(mockERC20.balanceOf(alice), amt2);
        vm.startPrank(alice);
        mockERC20.approve(address(mergeSplitFactory), amt2);

        // Act.
        mergeSplitFactory.mint(mockERC20, amt2);

        // Assert.
        assertEq(mockERC20.balanceOf(alice), 0);
        assertEq(mockERC20.balanceOf(address(mergeSplitFactory)), amt1 + amt2);
        assertEq(mergeSplitFactory.posAddrs(mockERC20).balanceOf(alice), amt2);
        assertEq(mergeSplitFactory.powAddrs(mockERC20).balanceOf(alice), amt2);
    }

    function testRedeemPair(uint256 amt1, uint256 amt2) public {
        // Prepare.
        vm.assume(amt2 < amt1);
        uint256 amtDiff = amt1 - amt2;
        testMintSucceedsForNewUnderlying(amt1);

        // Act.
        mergeSplitFactory.redeemPair(mockERC20, amt2);

        // Assert.
        assertEq(mockERC20.balanceOf(address(this)), amt2);
        assertEq(mockERC20.balanceOf(address(mergeSplitFactory)), amtDiff);
        assertEq(
            mergeSplitFactory.posAddrs(mockERC20).balanceOf(address(this)),
            amtDiff
        );
        assertEq(
            mergeSplitFactory.powAddrs(mockERC20).balanceOf(address(this)),
            amtDiff
        );
    }

    function testRedeemPosFailsIfNotSettled(uint256 amt) public {
        setPosRedeemable(false);

        vm.expectRevert(NotSettled.selector);
        mergeSplitFactory.redeemPos(mockERC20, amt);
    }

    function testRedeemPos(uint256 amt) public {
        testMintSucceedsForNewUnderlying(amt);
        setPosRedeemable(true);

        mergeSplitFactory.redeemPos(mockERC20, amt);

        assertEq(
            mergeSplitFactory.posAddrs(mockERC20).balanceOf(address(this)),
            0
        );
        assertEq(
            mergeSplitFactory.powAddrs(mockERC20).balanceOf(address(this)),
            amt
        );
        assertEq(mockERC20.balanceOf(address(this)), amt);
        assertEq(mockERC20.balanceOf(address(mergeSplitFactory)), 0);
    }

    function testRedeemPowFailsIfNotSettled(uint256 amt) public {
        setPowRedeemable(false);

        vm.expectRevert(NotSettled.selector);
        mergeSplitFactory.redeemPow(mockERC20, amt);
    }

    function testRedeemPow(uint256 amt) public {
        testMintSucceedsForNewUnderlying(amt);
        setPowRedeemable(true);

        mergeSplitFactory.redeemPow(mockERC20, amt);

        assertEq(
            mergeSplitFactory.posAddrs(mockERC20).balanceOf(address(this)),
            amt
        );
        assertEq(
            mergeSplitFactory.powAddrs(mockERC20).balanceOf(address(this)),
            0
        );
        assertEq(mockERC20.balanceOf(address(this)), amt);
        assertEq(mockERC20.balanceOf(address(mergeSplitFactory)), 0);
    }

    // Helpers
    function setPosRedeemable(bool set) internal {
        uint256 newDiff = 2 ** (set ? 65 : 63);
        vm.difficulty(newDiff);
    }

    function setPowRedeemable(bool set) internal {
        if (set) {
            setPosRedeemable(false);
        } else {
            vm.chainId(1);
        }
        uint256 offset = set ? 1 : 0;
        vm.warp(mergeSplitFactory.POS_UPPER_BOUND_TIMESTAMP() + offset);
    }
}
