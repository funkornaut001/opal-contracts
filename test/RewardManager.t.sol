// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {RewardManager} from "src/RewardManager.sol";
import {MockedOmnipool} from "src/mocks/MockedOmnipool.sol";
import {MockedERC20} from "src/mocks/MockedERC20.sol";
import {MockedAuraRewarder} from "src/mocks/MockedAuraRewarder.sol";
import {MockedRewardToken} from "src/mocks/MockedRewardToken.sol";
import {Omnipool} from "src/pools/Omnipool.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";
import {
    SCALED_ONE,
    CONTRACT_REGISTRY_ACCESS,
    ROLE_OPAL_TEAM,
    CONTRACT_BAL_TOKEN,
    CONTRACT_AURA_TOKEN,
    CONTRACT_GEM_TOKEN,
    REWARD_FEES,
    CONTRACT_OPAL_TREASURY,
    CONTRACT_VOTE_LOCKER
} from "src/utils/constants.sol";

contract RewardManagerTest is Test {
    RewardManager public rewardManager;
    Omnipool public omnipool;
    address public omnipoolAddr;
    address public treasury;
    address public voteLocker;

    address public opalTeam = address(0x10);

    RegistryContract public registryContract;

    address public balAddr;
    address public auraAddr;
    address public gemAddr;
    address public arbAddr;
    address public ethAddr;
    address[] public extraRewardTokens;

    MockedRewardToken public rtBAL;
    MockedRewardToken public rtAURA;

    MockedAuraRewarder public underlyingPoolOne;
    MockedAuraRewarder public underlyingPoolTwo;

    error OutOfBounds();
    error NotAuthorized();

    /**
     * @dev Set up the test environment
     * ERC20: BAL, AURA, GEM, ARB, ETH, WETH
     * Underlying pools: UP#1 (BAL, AURA, ARB), UP#2 (BAL, AURA, ARB, ETH)
     * -> ARB and ETH are the extra reward tokens
     */
    function setUp() public {
        // Create ERC20 rewards tokens
        MockedERC20 mockedBAL = new MockedERC20("Balancer", "BAL");
        MockedERC20 mockedAURA = new MockedERC20("Aura", "AURA");
        MockedERC20 mockedGEM = new MockedERC20("Gem", "GEM");

        MockedERC20 mockedARB = new MockedERC20("Arbitrum", "ARB");
        MockedERC20 mockedETH = new MockedERC20("Ethereum", "ETH");

        RegistryAccess registryAccess = new RegistryAccess();
        registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(opalTeam);
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_BAL_TOKEN, address(mockedBAL));
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_AURA_TOKEN, address(mockedAURA));
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_GEM_TOKEN, address(mockedGEM));

        balAddr = address(mockedBAL);
        auraAddr = address(mockedAURA);
        gemAddr = address(mockedGEM);
        arbAddr = address(mockedARB);
        ethAddr = address(mockedETH);

        extraRewardTokens.push(address(mockedARB));
        extraRewardTokens.push(address(mockedETH));

        // Create Omnipool and RewardManager
        MockedOmnipool mockedOmnipool = new MockedOmnipool(gemAddr);

        rewardManager =
        new RewardManager(address(mockedOmnipool), address(registryAccess), address(registryContract));

        // The ERC20 tokens are wrapped by Aura.Finance contracts, this mocked contracts are used to simulate the behaviour
        rtBAL = new MockedRewardToken(address(mockedBAL));
        rtAURA = new MockedRewardToken(address(mockedAURA));
        MockedRewardToken rtARB = new MockedRewardToken(address(mockedARB));
        MockedRewardToken rtETH = new MockedRewardToken(address(mockedETH));

        // Create underlying pools
        underlyingPoolOne = new MockedAuraRewarder(
            address(rtBAL),
            address(rtAURA),
            address(rtARB),
            address(0),
            address(0)
        );
        underlyingPoolTwo = new MockedAuraRewarder(
            address(rtBAL),
            address(rtAURA),
            address(rtARB),
            address(rtETH),
            address(0)
        );

        // Add pools to omnipool
        mockedOmnipool.addUnderlyingPool(address(underlyingPoolOne));
        mockedOmnipool.addUnderlyingPool(address(underlyingPoolTwo));

        treasury = address(0x77);
        voteLocker = address(0x88);

        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_OPAL_TREASURY, treasury);
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_VOTE_LOCKER, voteLocker);

        omnipool = Omnipool(address(mockedOmnipool));
        omnipoolAddr = address(omnipool);

        vm.clearMockedCalls();
    }

    /**
     *   @dev It should not revert if the user has not deposited anything
     */
    function test_claimEarnings_shouldRevertBecauseUserDidNotDeposit() public {
        vm.mockCall(
            address(omnipool),
            abi.encodeWithSelector(omnipool.getUserTotalDeposit.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(omnipool),
            abi.encodeWithSelector(omnipool.getTotalDeposited.selector),
            abi.encode(1)
        );
        rewardManager.setExtraRewardTokens();

        rewardManager.claimEarnings();
    }

    /**
     *   @dev It should not revert if the omnipool is empty
     */
    function test_claimEarnings_shouldNotFailIfNothingTheOmnipoolIsEmpty() public {
        vm.mockCall(
            address(omnipool),
            abi.encodeWithSelector(omnipool.getUserTotalDeposit.selector),
            abi.encode(1)
        );
        vm.mockCall(
            address(omnipool),
            abi.encodeWithSelector(omnipool.getTotalDeposited.selector),
            abi.encode(0)
        );
        rewardManager.setExtraRewardTokens();

        rewardManager.claimEarnings();
    }

    /**
     *   @dev It shouldn't call the swapForGem method because the extra reward tokens are not set
     */
    function test_claimEarnings_shouldNotClaimExtraRewardsIfTheyAreNotSet() public {
        bytes memory mess = bytes("Should not be called");
        // Mock the omnipool user deposited value
        vm.mockCall(
            omnipoolAddr,
            abi.encodeWithSelector(omnipool.getUserTotalDeposit.selector, address(this)),
            abi.encode(1)
        );
        vm.mockCall(
            omnipoolAddr, abi.encodeWithSelector(omnipool.getTotalDeposited.selector), abi.encode(1)
        );

        vm.mockCallRevert(
            address(omnipool), abi.encodeWithSelector(omnipool.swapForGem.selector), mess
        );

        rewardManager.claimEarnings();

        // Now it should revert
        rewardManager.setExtraRewardTokens();
        vm.expectRevert(mess);
        rewardManager.claimEarnings();
    }

    /**
     * @dev Test the claimEarnings method
     */
    function test_claimEarnings_shouldNotClaimExtraRewards_simple() public {
        uint256 userTotalDeposit = 1 ether;
        uint256 upOneReward = 1 ether / 100;
        uint256 upTwoReward = 1 ether / 50;
        uint256 upOneExtraReward = 1 ether / 200;
        uint256 upTwoExtraReward = 1 ether / 400;
        uint256 omnipoolTotalDeposited = 100 ether;

        // Mock the omnipool user deposited value
        vm.mockCall(
            omnipoolAddr,
            abi.encodeWithSelector(omnipool.getUserTotalDeposit.selector, address(this)),
            abi.encode(userTotalDeposit)
        );
        // Mock the total deposited value
        vm.mockCall(
            omnipoolAddr,
            abi.encodeWithSelector(omnipool.getTotalDeposited.selector),
            abi.encode(omnipoolTotalDeposited)
        );
        // Mock the UP rewards
        // The MockedAuraRewarder mocks getRewards and use the MockedERC20 mint method to mint the rewards
        mockUnderlyingPoolsRewards(upOneReward, upTwoReward, upOneExtraReward, upTwoExtraReward);
        // Mock the extra reward tokens balance
        rewardManager.setExtraRewardTokens();

        // The getRewards method should be called once for each underlying pool
        vm.expectCall(
            address(underlyingPoolOne),
            abi.encodeCall(underlyingPoolOne.getReward, (omnipoolAddr, true)),
            1
        );
        vm.expectCall(
            address(underlyingPoolTwo),
            abi.encodeCall(underlyingPoolTwo.getReward, (omnipoolAddr, true)),
            1
        );
        // Expect the omnipool.swapForGem to be called twice
        vm.expectCall(
            omnipoolAddr,
            abi.encodeCall(omnipool.swapForGem, (arbAddr, upOneExtraReward + upTwoExtraReward)),
            1
        );
        vm.expectCall(
            omnipoolAddr, abi.encodeCall(omnipool.swapForGem, (ethAddr, upTwoExtraReward)), 1
        );
        // Expect the omnipool to transfer the rewards to the user
        uint256 balReward = userTotalDeposit * SCALED_ONE / omnipoolTotalDeposited
            * (upOneReward + upTwoReward) / SCALED_ONE;
        MockedERC20 bal = MockedERC20(balAddr);
        vm.expectCall(
            balAddr,
            abi.encodeCall(
                bal.transferFrom,
                (omnipoolAddr, address(this), balReward - balReward * REWARD_FEES / SCALED_ONE)
            ),
            1
        );
        uint256 auraReward = userTotalDeposit * SCALED_ONE / omnipoolTotalDeposited
            * (upOneExtraReward + upTwoExtraReward) / SCALED_ONE;
        vm.expectCall(
            auraAddr,
            abi.encodeCall(
                MockedERC20(auraAddr).transferFrom,
                (omnipoolAddr, address(this), auraReward - auraReward * REWARD_FEES / SCALED_ONE)
            ),
            1
        );
        uint256 gemReward = userTotalDeposit * SCALED_ONE / omnipoolTotalDeposited
            * (upOneExtraReward + upTwoExtraReward * 2) / SCALED_ONE;
        vm.expectCall(
            gemAddr,
            abi.encodeCall(
                MockedERC20(gemAddr).transferFrom, (omnipoolAddr, address(this), gemReward)
            ),
            1
        );

        rewardManager.claimEarnings();
    }

    /**
     * @dev Should return the extra reward token corresponding to the index
     */
    function test_getExtraRewardToken() public {
        rewardManager.setExtraRewardTokens();
        assert(rewardManager.getExtraRewardToken(0) == extraRewardTokens[0]);
        assert(rewardManager.getExtraRewardToken(1) == extraRewardTokens[1]);
        vm.expectRevert(abi.encodeWithSelector(OutOfBounds.selector));
        rewardManager.getExtraRewardToken(2);
    }

    /**
     * @dev Should return the reward tokens
     */
    function test_getRewardToken() public {
        assert(rewardManager.getRewardToken(0) == balAddr);
        assert(rewardManager.getRewardToken(1) == auraAddr);
        assert(rewardManager.getRewardToken(2) == gemAddr);
        vm.expectRevert(abi.encodeWithSelector(OutOfBounds.selector));
        rewardManager.getRewardToken(3);
    }

    /**
     * @dev Should change the extra reward tokens
     */
    function test_setExtraRewardTokens() public {
        rewardManager.setExtraRewardTokens();
        assert(rewardManager.getRewardToken(0) == balAddr);
        assert(rewardManager.getRewardToken(1) == auraAddr);
        assert(rewardManager.getExtraRewardToken(0) == extraRewardTokens[0]);
        assert(rewardManager.getExtraRewardToken(1) == extraRewardTokens[1]);
        // Change the extra reward tokens
        MockedERC20 xToken = new MockedERC20("XToken", "X");
        MockedRewardToken rtXTOKEN = new MockedRewardToken(address(xToken));

        underlyingPoolOne.updateRewardTokens(
            address(rtBAL), address(rtAURA), address(rtXTOKEN), address(0), address(0)
        );
        underlyingPoolTwo.updateRewardTokens(
            address(rtBAL), address(rtAURA), address(0), address(0), address(0)
        );

        rewardManager.setExtraRewardTokens();

        assert(rewardManager.getRewardToken(0) == balAddr);
        assert(rewardManager.getRewardToken(1) == auraAddr);
        assert(rewardManager.getExtraRewardToken(0) == address(xToken));
    }

    function mockUnderlyingPoolsRewards(
        uint256 upOneReward,
        uint256 upTwoReward,
        uint256 upOneExtraReward,
        uint256 upTwoExtraReward
    ) public {
        vm.mockCall(
            address(underlyingPoolOne),
            abi.encodeWithSelector(underlyingPoolOne.getMintValue.selector),
            abi.encode(upOneReward)
        );
        vm.mockCall(
            address(underlyingPoolTwo),
            abi.encodeWithSelector(underlyingPoolTwo.getMintValue.selector),
            abi.encode(upTwoReward)
        );
        vm.mockCall(
            address(underlyingPoolOne),
            abi.encodeWithSelector(underlyingPoolOne.getExtraMintValue.selector),
            abi.encode(upOneExtraReward)
        );
        vm.mockCall(
            address(underlyingPoolTwo),
            abi.encodeWithSelector(underlyingPoolTwo.getExtraMintValue.selector),
            abi.encode(upTwoExtraReward)
        );
    }

    /**
     * @dev Should claim the protocol rewards
     */
    function test_claimProtocolRewards() public {
        uint256 userTotalDeposit = 1 ether;
        uint256 upOneReward = 1 ether / 100;
        uint256 upTwoReward = 1 ether / 50;
        uint256 upOneExtraReward = 1 ether / 200;
        uint256 upTwoExtraReward = 1 ether / 400;
        uint256 omnipoolTotalDeposited = 100 ether;

        // Mock the omnipool user deposited value
        vm.mockCall(
            omnipoolAddr,
            abi.encodeWithSelector(omnipool.getUserTotalDeposit.selector, address(this)),
            abi.encode(userTotalDeposit)
        );
        // Mock the total deposited value
        vm.mockCall(
            omnipoolAddr,
            abi.encodeWithSelector(omnipool.getTotalDeposited.selector),
            abi.encode(omnipoolTotalDeposited)
        );
        // Mock the UP rewards
        // The MockedAuraRewarder mocks getRewards and use the MockedERC20 mint method to mint the rewards
        mockUnderlyingPoolsRewards(upOneReward, upTwoReward, upOneExtraReward, upTwoExtraReward);
        // Mock the extra reward tokens balance
        rewardManager.setExtraRewardTokens();

        // Treasury fees
        vm.expectCall(
            balAddr,
            abi.encodeCall(
                MockedERC20(balAddr).transferFrom,
                (omnipoolAddr, treasury, (upOneReward + upTwoReward) * REWARD_FEES / SCALED_ONE / 2)
            ),
            1
        );
        vm.expectCall(
            auraAddr,
            abi.encodeCall(
                MockedERC20(auraAddr).transferFrom,
                (
                    omnipoolAddr,
                    treasury,
                    (upOneExtraReward + upTwoExtraReward) * REWARD_FEES / SCALED_ONE / 2
                )
            ),
            1
        );
        // Vote locker fees
        vm.expectCall(
            balAddr,
            abi.encodeCall(
                MockedERC20(balAddr).transferFrom,
                (
                    omnipoolAddr,
                    voteLocker,
                    ((upOneReward + upTwoReward) * REWARD_FEES / SCALED_ONE)
                        - ((upOneReward + upTwoReward) * REWARD_FEES / SCALED_ONE / 2)
                )
            ),
            1
        );
        vm.expectCall(
            auraAddr,
            abi.encodeCall(
                MockedERC20(auraAddr).transferFrom,
                (
                    omnipoolAddr,
                    voteLocker,
                    ((upOneExtraReward + upTwoExtraReward) * REWARD_FEES / SCALED_ONE)
                        - ((upOneExtraReward + upTwoExtraReward) * REWARD_FEES / SCALED_ONE / 2)
                )
            ),
            1
        );

        rewardManager.claimEarnings();

        // Check that claimable fees are now set to 0
        assertEq(rewardManager.protocolFeesBALBalance(), 0);
        assertEq(rewardManager.protocolFeesAURABalance(), 0);
    }
}
