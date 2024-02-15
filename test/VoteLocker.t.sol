// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {VoteLocker} from "src/tokenomics/VoteLocker.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";
import {MockedERC20} from "src/mocks/MockedERC20.sol";
import {CONTRACT_REGISTRY_ACCESS} from "src/utils/constants.sol";

/*
Balancer GEM-ETH BPT can be locked for a period of sixteen weeks. In exchange for locking a user will receive $vlGEM. This is a non-transferrable token (e.g. vlAura). After the lock period has expired, the user can withdraw the underlying LP tokens or relock it.
Voting takes place via Snapshot.
MultipleLocks: No. Similar to how holders can lock Aura during a specific duration of 16 weeks for vlAura, Opal has a unique lock duration. 
*/

contract VoteLockerTest is Test {
    VoteLocker voteLocker;
    uint256 constant _LOCK_DURATION = 17 weeks;

    function setUp() public {
        RegistryAccess registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(address(this));
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        MockedERC20 token = new MockedERC20("80GEM-20ETH BPT", "gemBPT");

        voteLocker =
        new VoteLocker("Vote Locker 80GEM-20ETH BPT", "vlGEM", address(token), address(registryContract));
    }

    /**
     * @notice Test that the first lock works as expected
     */
    function test_firstLock() public {
        MockedERC20 token = MockedERC20(address(voteLocker.stakingToken()));
        uint256 lockAmount = 10 ether;
        uint256 epoch = 1;
        uint256 blockTimestamp = epoch * 1 weeks + 1 weeks / 2;

        // Mint 10 GEM-ETH BPT and approve the vote locker to spend it
        token.mint(address(this), lockAmount);
        token.approve(address(voteLocker), lockAmount);

        // Tokens should be pulled
        vm.expectCall(
            address(token),
            abi.encodeCall(token.transferFrom, (address(this), address(voteLocker), lockAmount)),
            1
        );
        // Set the block.timestamp
        vm.warp(blockTimestamp);

        voteLocker.lock(address(this), lockAmount);
        (uint208 locked,) = voteLocker.balances(address(this));
        (uint208 amount, uint48 unlockTime) = voteLocker.userLocks(address(this), 0);
        VoteLocker.Epoch memory epochObject = voteLocker.epochs(epoch);

        // Balance should be locked
        assertEq(locked, lockAmount);
        assertEq(amount, lockAmount);
        assertEq(epochObject.supply, lockAmount);
        assertEq(voteLocker.lockedSupply(), lockAmount);
        assertEq(unlockTime, epoch * 1 weeks + _LOCK_DURATION);
        assertEq(epochObject.date, epoch * 1 weeks);
        assert(unlockTime >= blockTimestamp + 16 weeks);

        vm.expectRevert();
        voteLocker.userLocks(address(this), 1);
    }

    /**
     * @notice Locking during the same epoch should add to the existing lock
     */
    function test_lockSameEpoch() public {
        MockedERC20 token = MockedERC20(address(voteLocker.stakingToken()));
        uint256 lockAmount = 1 ether;
        uint256 blockTimestamp = 1 weeks + 1 weeks / 2;

        // Mint 10 GEM-ETH BPT and approve the vote locker to spend it
        token.mint(address(this), lockAmount * 2);
        token.approve(address(voteLocker), lockAmount * 2);

        vm.warp(blockTimestamp);

        voteLocker.lock(address(this), lockAmount);
        voteLocker.lock(address(this), lockAmount);

        (uint208 locked,) = voteLocker.balances(address(this));
        (uint208 amount, uint48 unlockTime) = voteLocker.userLocks(address(this), 0);

        // Balance should be locked
        assertEq(locked, lockAmount * 2);
        assertEq(amount, lockAmount * 2);
        assertEq(unlockTime, 1 weeks + _LOCK_DURATION);

        vm.expectRevert();
        voteLocker.userLocks(address(this), 1);
    }

    /**
     * @notice Test that we can withdraw the locked tokens after the lock period has expired
     */
    function test_withdrawAfterUnlock() public {
        MockedERC20 token = MockedERC20(address(voteLocker.stakingToken()));
        uint256 lockAmount = 10 ether;
        uint256 blockTimestamp = 1 weeks + 1 weeks / 2;

        token.mint(address(this), lockAmount);
        token.approve(address(voteLocker), lockAmount);
        vm.warp(blockTimestamp);

        voteLocker.lock(address(this), lockAmount);

        vm.warp(blockTimestamp + _LOCK_DURATION);

        vm.expectCall(
            address(token), abi.encodeCall(token.transfer, (address(this), lockAmount)), 1
        );

        voteLocker.processExpiredLocks(false);

        (uint208 locked, uint48 nextUnlockIndex) = voteLocker.balances(address(this));

        assertEq(locked, 0);
        assertEq(nextUnlockIndex, 1);
    }

    /**
     * @notice Test that we can relock the locked tokens after the lock period has expired
     */
    function test_relockAfterUnlock() public {
        MockedERC20 token = MockedERC20(address(voteLocker.stakingToken()));
        uint256 lockAmount = 10 ether;
        uint256 blockTimestamp = 1 weeks + 1 weeks / 2;

        token.mint(address(this), lockAmount);
        token.approve(address(voteLocker), lockAmount);
        vm.warp(blockTimestamp);

        voteLocker.lock(address(this), lockAmount);

        vm.warp(blockTimestamp + _LOCK_DURATION);

        voteLocker.processExpiredLocks(true);

        (uint208 locked,) = voteLocker.balances(address(this));
        // New epoch
        (uint208 amount,) = voteLocker.userLocks(address(this), 1);

        assertEq(locked, lockAmount);
        assertEq(amount, lockAmount);
    }

    /**
     * @notice Test that we can withdraw the locked tokens after the lock period has expired for X locks but not for the last one
     */
    function test_withdrawAfterUnlockMultipleLocks() public {
        MockedERC20 token = MockedERC20(address(voteLocker.stakingToken()));
        uint256 lockAmount = 1 ether;
        uint256 blockTimestamp = 1 weeks + 1 weeks / 2;

        token.mint(address(this), lockAmount * 3);
        token.approve(address(voteLocker), lockAmount * 3);

        vm.warp(blockTimestamp);

        voteLocker.lock(address(this), lockAmount);
        vm.warp(blockTimestamp + _LOCK_DURATION);

        voteLocker.lock(address(this), lockAmount);
        vm.warp(blockTimestamp + _LOCK_DURATION * 2);

        voteLocker.lock(address(this), lockAmount);

        voteLocker.processExpiredLocks(false);

        (uint208 locked, uint48 nextUnlockIndex) = voteLocker.balances(address(this));

        assertEq(locked, lockAmount);
        assertEq(nextUnlockIndex, 2);
    }

    /**
     * @notice Test that we can kick expired locks after the grace period of 3 weeks
     * Kicking expired locks gives rewards to the kicker
     */
    function test_kickExpiredLocks() public {
        MockedERC20 token = MockedERC20(address(voteLocker.stakingToken()));
        uint256 lockAmount = 1 ether;
        uint256 kickRewards = 0.02 ether;
        uint256 blockTimestamp = 1 weeks + 1 weeks / 2;
        uint256 gracePeriod = 3 weeks;
        address kicker = address(0x1);

        token.mint(address(this), lockAmount);
        token.approve(address(voteLocker), lockAmount);

        vm.warp(blockTimestamp);

        voteLocker.lock(address(this), lockAmount);
        vm.warp(blockTimestamp + _LOCK_DURATION + gracePeriod + 1 weeks);

        vm.prank(kicker);
        voteLocker.kickExpiredLocks(address(this));

        (uint208 locked, uint48 nextUnlockIndex) = voteLocker.balances(address(this));
        uint256 balanceOfKicker = token.balanceOf(kicker);
        uint256 balanceOfOwner = token.balanceOf(address(this));

        assertEq(locked, 0);
        assertEq(nextUnlockIndex, 1);
        assertEq(balanceOfKicker, kickRewards);
        assertEq(balanceOfOwner, lockAmount - kickRewards);
    }
}
