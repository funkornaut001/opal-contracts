// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VoteLocker} from "src/tokenomics/VoteLocker.sol";
import {MockedERC20} from "src/mocks/MockedERC20.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";
import {GaugeFactory} from "src/tokenomics/GaugeFactory.sol";
import {MockedLiquidityGauge} from "src/mocks/MockedLiquidityGauge.sol";
import {MockedVoteLocker} from "src/mocks/MockedVoteLocker.sol";
import {GaugeController} from "src/tokenomics/GaugeController.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    ROLE_MINT_ESCROW_TOKEN,
    WEEK,
    SCALED_ONE
} from "src/utils/constants.sol";

contract GaugeControllerTest is Test {
    GaugeController gaugeController;
    RegistryAccess registryAccess;

    address public opalTeam = vm.addr(0x99);
    address public alice = vm.addr(0x10);
    address public bob = vm.addr(0x11);

    MockedVoteLocker voteLocker;
    MockedERC20 token;

    error NotAuthorized();
    error AddressZero();
    error InvalidGaugeType();
    error GaugeAlreadyAdded();
    error NoLocks();
    error NoActiveLocks();
    error InvalidVoteWeight();
    error VoteCooldown();
    error InvalidGauge();
    error VoteWeightOverflow();

    function setUp() public virtual {
        registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(opalTeam);
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        token = new MockedERC20("TOKEN", "TKN");
        voteLocker = new MockedVoteLocker();

        gaugeController =
            new GaugeController(address(token), address(voteLocker), address(registryContract));
    }
}

contract GaugeControllerContructorTest is GaugeControllerTest {}

contract GaugeControllerAddGaugeTest is GaugeControllerTest {
    function initialize() internal {
        string memory name = "Type 1";
        uint256 weight = uint256(1);
        vm.warp(WEEK * 10);

        vm.prank(opalTeam);
        gaugeController.addType(name, weight);
    }

    /**
     * @notice  Should revert if the caller has not the Opal Team role
     */
    function test_shouldRevertIfCallerHasNotOpalTeamRole() external {
        vm.expectRevert(NotAuthorized.selector);
        int128 gaugeType = 1;
        uint256 gaugeWeight = uint256(1e18);
        vm.prank(alice);
        gaugeController.addGauge(address(0x123), gaugeType, gaugeWeight);
    }

    /**
     * @notice  Should revert if the gaugeType is zero or less
     */
    function test_shouldRevertIfGaugeTypeIsLowerThanZero() external {
        initialize();
        vm.expectRevert(InvalidGaugeType.selector);
        int128 gaugeType = -1;
        uint256 gaugeWeight = uint256(1e18);
        vm.prank(opalTeam);
        gaugeController.addGauge(address(0x123), gaugeType, gaugeWeight);
    }

    /**
     * @notice  Should revert if the gaugeType is greator than the number of gauge types
     */
    function test_shouldRevertIfGaugeTypeIsGreatorThanNumberOfGaugeTypes() external {
        vm.expectRevert(InvalidGaugeType.selector);
        int128 gaugeType = 3;
        uint256 gaugeWeight = uint256(1e18);
        vm.prank(opalTeam);
        gaugeController.addGauge(address(0x123), gaugeType, gaugeWeight);
    }

    /**
     * @notice  Should revert if the gauge already exists
     */
    function test_shouldRevertIfGaugeAlreadyExists() external {
        initialize();
        int128 gaugeType = 0;
        uint256 gaugeWeight = uint256(1e18);
        address gauge = address(0x123);
        vm.prank(opalTeam);
        gaugeController.addGauge(gauge, gaugeType, gaugeWeight);
        vm.expectRevert(GaugeAlreadyAdded.selector);
        vm.prank(opalTeam);
        gaugeController.addGauge(gauge, gaugeType, gaugeWeight);
    }

    /**
     * @notice  Should add a new gauge
     */
    function test_addNewGauge() external {
        initialize();
        int128 gaugeType = 0;
        uint256 gaugeWeight = uint256(1e18);
        address gauge = address(0x123);
        uint256 nextTimestamp = block.timestamp + WEEK;
        vm.prank(opalTeam);
        gaugeController.addGauge(gauge, gaugeType, gaugeWeight);

        assertEq(gaugeController.numberGauges(), 1);
        assertEq(gaugeController.gauges(0), gauge);
        assertEq(gaugeController.gaugeTypes(gauge), gaugeType + 1);
        assertEq(gaugeController.typeVotes(gaugeType, nextTimestamp), gaugeWeight);
        assertEq(gaugeController.lastTypeUpdate(gaugeType), nextTimestamp);
        assertEq(gaugeController.totalVotes(nextTimestamp), gaugeWeight);
        assertEq(gaugeController.lastUpdate(), nextTimestamp);
        assertEq(gaugeController.gaugeVotes(gauge, nextTimestamp), gaugeWeight);
    }
}

contract GaugeControllerAddTypeTest is GaugeControllerTest {
    /**
     * @notice  Should revert if the caller has not the Opal Team role
     */
    function test_shouldRevertIfCallerHasNotOpalTeamRole() external {
        vm.expectRevert(NotAuthorized.selector);
        string memory name = "Type 1";
        uint256 weight = uint256(1e18);
        vm.prank(alice);
        gaugeController.addType(name, weight);
    }

    /**
     * @notice  Should add a new gauge type
     */
    function test_shouldAddNewGaugeType() external {
        string memory name = "Type 1";
        uint256 weight = uint256(1e18);
        vm.warp(WEEK * 10);
        uint256 currentTimestamp = block.timestamp;
        uint256 nextTimestamp = currentTimestamp + WEEK;

        vm.prank(opalTeam);
        gaugeController.addType(name, weight);

        int128 expectedGaugeType = 0;

        assertEq(gaugeController.numberGaugeTypes(), 1);
        assertEq(gaugeController.gaugeTypeNames(expectedGaugeType), name);
        assertEq(gaugeController.typeWeights(expectedGaugeType, nextTimestamp), weight);
        assertEq(gaugeController.lastUpdate(), nextTimestamp);
        assertEq(gaugeController.lastTypeWeightUpdate(expectedGaugeType), nextTimestamp);
    }
}

contract GaugeControllerChangeTypeWeightTest is GaugeControllerTest {
    function initialize(uint256 weight) internal {
        string memory name = "Type 1";
        vm.warp(WEEK * 10);

        vm.prank(opalTeam);
        gaugeController.addType(name, weight);
    }

    /**
     * @notice  Should revert if the caller has not the Opal Team role
     */
    function test_shouldRevertIfCallerHasNotOpalTeamRole() external {
        vm.expectRevert(NotAuthorized.selector);
        int128 gaugeType = 0;
        uint256 weight = uint256(1e18);
        vm.prank(alice);
        gaugeController.changeTypeWeight(gaugeType, weight);
    }

    /**
     * Should change the weight of a gauge type
     */
    function test_shouldChangeTypeWeight() external {
        uint256 weight = uint256(1e18);
        initialize(weight);
        int128 gaugeType = 0;
        uint256 newWeight = uint256(2e18);
        uint256 nextTimestamp = block.timestamp + WEEK;
        vm.prank(opalTeam);
        gaugeController.changeTypeWeight(gaugeType, newWeight);

        assertEq(gaugeController.typeWeights(gaugeType, nextTimestamp), newWeight);
        assertEq(gaugeController.lastUpdate(), nextTimestamp);
        assertEq(gaugeController.lastTypeWeightUpdate(gaugeType), nextTimestamp);
    }
}

contract GaugeControllerChangeGaugeWeightTest is GaugeControllerTest {}

contract GaugeControllerVoteForGaugeWeightTest is GaugeControllerTest {
    
    string name = "Type 1";
    uint256 typeWeight = uint256(1e18);
    uint256 gaugeWeight = uint256(0);
    int128 gaugeType = 0;
    address gauge = address(0x123);

    function setUp() public override {
        GaugeControllerTest.setUp();

        vm.warp(block.timestamp + WEEK * 10 + 55);

        vm.startPrank(opalTeam);
        gaugeController.addType(name, typeWeight);
        gaugeController.addGauge(gauge, gaugeType, gaugeWeight);
        vm.stopPrank();

        uint256 currentPeriod = (block.timestamp / WEEK) * WEEK;
        MockedVoteLocker.LockedBalance[] memory userLocks = new MockedVoteLocker.LockedBalance[](3);
        userLocks[0] = MockedVoteLocker.LockedBalance(uint112(200e18), uint32(currentPeriod + WEEK * 4));
        userLocks[1] = MockedVoteLocker.LockedBalance(uint112(150e18), uint32(currentPeriod + WEEK * 6));
        userLocks[2] = MockedVoteLocker.LockedBalance(uint112(75e18), uint32(currentPeriod + WEEK * 9));
        voteLocker.setUserLocks(alice, userLocks);
    }

    function test_shouldCastVote(uint256 voteWeight) external {
        vm.assume(voteWeight > 0 && voteWeight <= 10000);
        
        uint256 nextPeriod = ((block.timestamp + WEEK) / WEEK) * WEEK;
        (,,,MockedVoteLocker.LockedBalance[] memory userLocks) = voteLocker.lockedBalances(alice);

        uint256 prevGaugeVotes = gaugeController.gaugeVotes(gauge, nextPeriod);
        uint256 prevTypeVotes = gaugeController.typeVotes(gaugeType, nextPeriod);

        uint256[] memory prevGaugeChanges = new uint256[](userLocks.length);
        uint256[] memory prevTypeChanges = new uint256[](userLocks.length);
        for(uint256 i = 0; i < userLocks.length; i++) {
            prevGaugeChanges[i] = gaugeController.gaugeVoteChanges(gauge, userLocks[i].unlockTime);
            prevTypeChanges[i] = gaugeController.typeVoteChanges(gaugeType, userLocks[i].unlockTime);
        }
        
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, voteWeight);

        assertEq(gaugeController.lastUserVote(alice, gauge), block.timestamp);
        assertEq(gaugeController.userVotePower(alice), voteWeight);

        uint256 expectedUserVote;
        for (uint256 i = 0; i < userLocks.length; i++) {
            if (userLocks[i].unlockTime > block.timestamp) {
                uint256 _votes = (userLocks[i].amount * voteWeight) / 10000;
                expectedUserVote += _votes;

                (uint208 unlockAmount, uint48 unlockDate) = gaugeController.userVoteUnlocks(alice, gauge, i);

                assertEq(unlockAmount, _votes);
                assertEq(unlockDate, userLocks[i].unlockTime);

                assertEq(gaugeController.gaugeVoteChanges(gauge, userLocks[i].unlockTime), prevGaugeChanges[i] + _votes);
                assertEq(gaugeController.typeVoteChanges(gaugeType, userLocks[i].unlockTime), prevTypeChanges[i] + _votes);
            }
        }
        
        (uint256 userVoteAmount, uint256 userVoteWeight) = gaugeController.userVote(alice, gauge);
        assertEq(userVoteAmount, expectedUserVote);
        assertEq(userVoteWeight, voteWeight);

        assertEq(gaugeController.gaugeVotes(gauge, nextPeriod), prevGaugeVotes + expectedUserVote);
        assertEq(gaugeController.typeVotes(gaugeType, nextPeriod), prevTypeVotes + expectedUserVote);
    }

    function test_shouldRemoveVotesOnGauge() external {
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, 5000);

        vm.warp(block.timestamp + WEEK * 2);
        uint256 nextPeriod = ((block.timestamp + WEEK) / WEEK) * WEEK;

        (,,,MockedVoteLocker.LockedBalance[] memory userLocks) = voteLocker.lockedBalances(alice);

        vm.prank(alice);
        gaugeController.checkpointGauge(gauge);

        uint256 prevGaugeVotes = gaugeController.gaugeVotes(gauge, nextPeriod);
        uint256 prevTypeVotes = gaugeController.typeVotes(gaugeType, nextPeriod);

        (uint256 oldUserVotes,) = gaugeController.userVote(alice, gauge);

        uint256[] memory prevGaugeChanges = new uint256[](userLocks.length);
        uint256[] memory prevTypeChanges = new uint256[](userLocks.length);
        for(uint256 i = 0; i < userLocks.length; i++) {
            prevGaugeChanges[i] = gaugeController.gaugeVoteChanges(gauge, userLocks[i].unlockTime);
            prevTypeChanges[i] = gaugeController.typeVoteChanges(gaugeType, userLocks[i].unlockTime);
        }
        
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, 0);

        assertEq(gaugeController.lastUserVote(alice, gauge), block.timestamp);
        assertEq(gaugeController.userVotePower(alice), 0);

        for (uint256 i = 0; i < userLocks.length; i++) {
            if (userLocks[i].unlockTime > block.timestamp) {
                uint256 oldVotes = (userLocks[i].amount * 5000) / 10000;

                (uint208 unlockAmount, uint48 unlockDate) = gaugeController.userVoteUnlocks(alice, gauge, i);

                assertEq(unlockAmount, 0);
                assertEq(unlockDate, userLocks[i].unlockTime);

                assertEq(gaugeController.gaugeVoteChanges(gauge, userLocks[i].unlockTime), prevGaugeChanges[i] - oldVotes);
                assertEq(gaugeController.typeVoteChanges(gaugeType, userLocks[i].unlockTime), prevTypeChanges[i] - oldVotes);
            }
        }
        
        (uint256 userVoteAmount, uint256 userVoteWeight) = gaugeController.userVote(alice, gauge);
        assertEq(userVoteAmount, 0);
        assertEq(userVoteWeight, 0);

        assertEq(gaugeController.gaugeVotes(gauge, nextPeriod), prevGaugeVotes - oldUserVotes);
        assertEq(gaugeController.typeVotes(gaugeType, nextPeriod), prevTypeVotes - oldUserVotes);
    }

    function test_shouldFailNoLocks() external {
        vm.expectRevert(NoLocks.selector);
        vm.prank(bob);
        gaugeController.voteForGaugeWeight(gauge, 10000);
    }

    function test_shouldFailLocksExpired() external {
        vm.warp(block.timestamp + WEEK * 10);
        vm.expectRevert(NoLocks.selector);
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, 10000);
    }

    function test_shouldFailInvalidVoteWeight(uint256 voteWeight) external {
        vm.assume(voteWeight > 10000);

        vm.expectRevert(InvalidVoteWeight.selector);
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, voteWeight);
    }

    function test_shouldFailVoteCooldown() external {
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, 10000);

        vm.expectRevert(VoteCooldown.selector);
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, 0);
    }

    function test_shouldFailVoteOverflow() external {
        address gauge2 = address(0x456);
        vm.startPrank(opalTeam);
        gaugeController.addGauge(gauge2, gaugeType, 0);
        vm.stopPrank();
        
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge, 5000);

        vm.expectRevert(VoteWeightOverflow.selector);
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge2, 7500);
    }

    function test_shouldFailInvalidGauge() external {
        address gauge2 = address(0x456);
        vm.expectRevert(InvalidGauge.selector);
        vm.prank(alice);
        gaugeController.voteForGaugeWeight(gauge2, 7500);
    }

}

contract GaugeControllerCheckpointTest is GaugeControllerTest {
    function initialize() internal {
        string memory name = "Type 1";
        uint256 weight = uint256(1e18);
        address gauge = address(0x123);
        int128 gaugeType = 0;
        uint256 gaugeWeight = uint256(1e18);
        vm.warp(WEEK * 10);

        vm.prank(opalTeam);
        gaugeController.addType(name, weight);
        gaugeController.addGauge(gauge, gaugeType, gaugeWeight);
    }

    /**
     * @notice  Should checkpoint (two weeks to checkpoint)
     */
    function shouldCheckpoint() external {
        vm.warp(block.timestamp + WEEK + 1);
        uint256 nextTimestamp = (block.timestamp + WEEK) / WEEK * WEEK;

        gaugeController.checkpoint();

        assertEq(gaugeController.lastUpdate(), nextTimestamp);
    }
}
