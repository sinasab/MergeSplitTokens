// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "openzeppelin-contracts/contracts/utils/Create2.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/ERC20Ownable.sol";
import "../src/MergeSplitERC20Broker.sol";

contract MergeSplitERC20BrokerTest is Test {
    using stdStorage for StdStorage;

    string public constant NAME = "TestToken";
    string public constant SYMBOL = "TKN";
    uint8 public constant DECIMALS = 18;

    MockERC20 public mockERC20;
    MergeSplitERC20Broker public broker;
    StdStorage public mergedSlot;

    event NewSplit(
        address indexed underlyingToken,
        address posToken,
        address powToken
    );

    function setUp() public {
        mockERC20 = new MockERC20(NAME, SYMBOL, DECIMALS);
        broker = new MergeSplitERC20Broker();
        // TODO(sina) does this do anything?
        vm.chainId(1);
    }

    function testPosRedeemable(bool set) public {
        setPosRedeemable(set);
        assertEq(broker.posRedeemable(), set);
        assertEq(broker.merged(), set);
    }

    function testPowRedeemable(bool set) public {
        setPowRedeemable(set);
        assertEq(broker.powRedeemable(), set);
    }

    function testPowRedeemableFuzzed(uint256 ts) public {
        setPowRedeemable(true);
        vm.assume(ts > broker.UPPER_BOUND_TIMESTAMP());
        vm.warp(ts);
        assertEq(broker.powRedeemable(), true);
    }

    function testPowRedeemableFalseWhenMerged() public {
        // False when merged
        setPowRedeemable(true);
        getMergedStorageSlot().checked_write(true);
        assertEq(broker.powRedeemable(), false);
    }

    function testPowRedeemableFalseWhenUnderTs() public {
        setPowRedeemable(true);
        vm.chainId(1);
        vm.warp(broker.UPPER_BOUND_TIMESTAMP());
        console2.log(broker.powRedeemable());
        assertEq(broker.powRedeemable(), false);
    }

    function testPowRedeemableFalseFuzzed(uint256 ts) public {
        setPowRedeemable(true);
        vm.chainId(1);
        vm.assume(ts <= broker.UPPER_BOUND_TIMESTAMP());
        vm.warp(ts);
        assertEq(broker.powRedeemable(), false);
    }

    function testActivateMergeRevertsIfAlreadySettled() public {
        // Reverts if pos is already settled.
        setPowRedeemable(true);
        setPosRedeemable(false);
        vm.expectRevert(AlreadySettled.selector);
        broker.activateMerge();

        // Also reverts if pow is already settled.
        setPowRedeemable(false);
        setPosRedeemable(true);
        vm.expectRevert(AlreadySettled.selector);
        broker.activateMerge();
    }

    function testActivateMergeCanActivate() public {
        setPosRedeemable(false);
        setPowRedeemable(false);

        // merged shouldn't be set here, since difficulty isn't high enough.
        vm.difficulty(1);
        broker.activateMerge();
        assertEq(broker.merged(), false);

        // merged should be set here
        vm.difficulty(2**64 + 1);
        broker.activateMerge();
        assertEq(broker.merged(), true);

        // Attempts to activate should fail after a successful call.
        vm.expectRevert(AlreadySettled.selector);
        broker.activateMerge();
    }

    function testMintRevertsIfAlreadyRedeemable(address addr, uint256 amt)
        public
    {
        // Should revert if either pos or pow is redeemable already.
        setPosRedeemable(true);
        setPowRedeemable(false);
        vm.expectRevert(AlreadySettled.selector);
        broker.mint(address(addr), amt);

        setPosRedeemable(false);
        setPowRedeemable(true);
        vm.expectRevert(AlreadySettled.selector);
        broker.mint(address(addr), amt);
    }

    function testMintSucceedsForNewUnderlying(uint256 amt) public {
        setPosRedeemable(false);
        setPowRedeemable(false);
        // Before; assert facts about statevars, token balances,
        // and predict newly deployed token addrs.
        assertEq(broker.posAddrs(address(mockERC20)), address(0));
        assertEq(broker.powAddrs(address(mockERC20)), address(0));
        assertEq(mockERC20.balanceOf(address(this)), 0);
        assertEq(mockERC20.balanceOf(address(broker)), 0);
        bytes32 salt = keccak256(abi.encodePacked(address(mockERC20)));
        address predictedPosTokenAddr = Create2.computeAddress(
            salt,
            keccak256(
                abi.encodePacked(
                    type(ERC20Ownable).creationCode,
                    abi.encode("posTestToken", "posTKN", 18)
                )
            ),
            address(broker)
        );
        address predictedPowTokenAddr = Create2.computeAddress(
            salt,
            keccak256(
                abi.encodePacked(
                    type(ERC20Ownable).creationCode,
                    abi.encode("powTestToken", "powTKN", 18)
                )
            ),
            address(broker)
        );
        vm.expectEmit(true, true, true, true, address(broker));
        emit NewSplit(
            address(mockERC20),
            predictedPosTokenAddr,
            predictedPowTokenAddr
        );

        // Act.
        mockERC20.approve(address(broker), type(uint256).max);
        mockERC20.mint(address(this), amt);
        assertEq(mockERC20.balanceOf(address(this)), amt);
        broker.mint(address(mockERC20), amt);

        // After, assert updated statevars, token balances.
        assertEq(broker.posAddrs(address(mockERC20)), predictedPosTokenAddr);
        assertEq(broker.powAddrs(address(mockERC20)), predictedPowTokenAddr);
        assertEq(mockERC20.balanceOf(address(this)), 0);
        assertEq(mockERC20.balanceOf(address(broker)), amt);
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
        mockERC20.approve(address(broker), amt2);

        // Act.
        broker.mint(address(mockERC20), amt2);

        // Assert.
        assertEq(mockERC20.balanceOf(alice), 0);
        assertEq(mockERC20.balanceOf(address(broker)), amt1 + amt2);
        assertEq(
            ERC20(broker.posAddrs(address(mockERC20))).balanceOf(alice),
            amt2
        );
        assertEq(
            ERC20(broker.powAddrs(address(mockERC20))).balanceOf(alice),
            amt2
        );
    }

    function testRedeemPair(uint256 amt1, uint256 amt2) public {
        // Prepare.
        vm.assume(amt2 < amt1);
        uint256 amtDiff = amt1 - amt2;
        testMintSucceedsForNewUnderlying(amt1);

        // Act.
        broker.redeemPair(address(mockERC20), amt2);

        // Assert.
        assertEq(mockERC20.balanceOf(address(this)), amt2);
        assertEq(mockERC20.balanceOf(address(broker)), amtDiff);
        assertEq(
            ERC20(broker.posAddrs(address(mockERC20))).balanceOf(address(this)),
            amtDiff
        );
        assertEq(
            ERC20(broker.powAddrs(address(mockERC20))).balanceOf(address(this)),
            amtDiff
        );
    }

    function testRedeemPosFailsIfNotSettled(uint256 amt) public {
        setPosRedeemable(false);

        vm.expectRevert(NotSettled.selector);
        broker.redeemPos(address(mockERC20), amt);
    }

    function testRedeemPos(uint256 amt) public {
        testMintSucceedsForNewUnderlying(amt);
        setPosRedeemable(true);

        broker.redeemPos(address(mockERC20), amt);

        assertEq(
            ERC20(broker.posAddrs(address(mockERC20))).balanceOf(address(this)),
            0
        );
        assertEq(
            ERC20(broker.powAddrs(address(mockERC20))).balanceOf(address(this)),
            amt
        );
        assertEq(mockERC20.balanceOf(address(this)), amt);
        assertEq(mockERC20.balanceOf(address(broker)), 0);
    }

    function testRedeemPowFailsIfNotSettled(uint256 amt) public {
        setPowRedeemable(false);

        vm.expectRevert(NotSettled.selector);
        broker.redeemPow(address(mockERC20), amt);
    }

    function testRedeemPow(uint256 amt) public {
        testMintSucceedsForNewUnderlying(amt);
        setPowRedeemable(true);

        broker.redeemPow(address(mockERC20), amt);

        assertEq(
            ERC20(broker.posAddrs(address(mockERC20))).balanceOf(address(this)),
            amt
        );
        assertEq(
            ERC20(broker.powAddrs(address(mockERC20))).balanceOf(address(this)),
            0
        );
        assertEq(mockERC20.balanceOf(address(this)), amt);
        assertEq(mockERC20.balanceOf(address(broker)), 0);
    }

    // Helper
    function getMergedStorageSlot() internal returns (StdStorage storage) {
        return stdstore.target(address(broker)).sig("merged()");
    }

    function setPosRedeemable(bool set) internal {
        getMergedStorageSlot().checked_write(set);
    }

    function setPowRedeemable(bool set) internal {
        if (set) {
            getMergedStorageSlot().checked_write(false);
        } else {
            vm.chainId(1);
        }
        uint256 offset = set ? 1 : 0;
        vm.warp(broker.UPPER_BOUND_TIMESTAMP() + offset);
    }
}
