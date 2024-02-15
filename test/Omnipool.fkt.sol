// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "src/pools/BPTOracle.sol";
import "src/pools/Omnipool.sol";
import "src/pools/OmnipoolController.sol";
import {IOmnipool} from "src/interfaces/Omnipool/IOmnipool.sol";
import {IOmnipoolController} from "src/interfaces/Omnipool/IOmnipoolController.sol";
import "src/utils/constants.sol";
import "forge-std/console.sol";
import {stdStorage, StdStorage} from "forge-std/Test.sol";
import {SetupTest} from "../test/setup.t.sol";
import {GemMinterRebalancingReward} from "src/tokenomics/GemMinterRebalancingReward.sol";

contract OmnipoolTest is SetupTest {
    uint256 mainnetFork;
    BPTOracle bptPrice;
    address[] pools;
    uint256 balanceTracker;
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address user = 0xDa9CE944a37d218c3302F6B82a094844C6ECEb17;
    address USDC_STG = 0x8bd520Bf5d59F959b25EE7b78811142dDe543134;
    address USDC_DOLA = 0xb139946D2F0E71b38e2c75d03D87C5E16339d2CD;
    address TRI_POOL = 0x2d9d3e3D0655766Aa801Ae0f6dC925db2DF291A1;
    Omnipool omnipool;
    OmnipoolController controller;
    GemMinterRebalancingReward handler;

    mapping(address => uint256) depositAmounts;
    mapping(address => uint256) stakedBalances;

    error NullAddress();
    error NotAuthorized();
    error CannotSetRewardManagerTwice();

    using stdStorage for StdStorage;

    //registry Contract

    function setUp() public override {
        mainnetFork = vm.createFork("eth");
        vm.selectFork(mainnetFork);
        super.setUp();
        deal(address(gem), 0x1234567890123456789012345678901234561234, 1000e18);
        omnipool = new Omnipool(
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            address(0xBA12222222228d8Ba445958a75a0704d566BF2C8),
            address(registryContract),
            address(0xB188b1CB84Fb0bA13cb9ee1292769F903A9feC59),
            "Opal USDC Pool",
            "opalUSDC"
        );

        console.log("Omnipool address: %s", address(omnipool));

        controller = new OmnipoolController(address(omnipool), address(registryContract));

        vm.startPrank(opal);
        registryContract.setContract(CONTRACT_OMNIPOOL_CONTROLLER, address(controller));
        registryAccess.addRole(ROLE_OMNIPOOL_CONTROLLER, address(controller));
        handler = new GemMinterRebalancingReward(address(registryContract));
        registryContract.setContract(CONTRACT_GEM_MINTER_REBALANCING_REWARD, address(handler));
        controller.addOmnipool(address(omnipool));

        // For rebalancing rewards
        gem.approve(address(handler), type(uint256).max);

        controller.addRebalancingRewardHandler(address(omnipool), address(handler));

        // USDC / STG
        omnipool.changeUnderlyingPool(
            0,
            0x8bd520Bf5d59F959b25EE7b78811142dDe543134,
            0x3ff3a210e57cfe679d9ad1e9ba6453a716c56a2e0002000000000000000005d5,
            0,
            0,
            0.4e18,
            PoolType.WEIGHTED
        );
        controller.addRebalancingRewardHandler(
            0x8bd520Bf5d59F959b25EE7b78811142dDe543134, address(handler)
        );

        // DAI / USDC / USDT
        omnipool.changeUnderlyingPool(
            1,
            0x2d9d3e3D0655766Aa801Ae0f6dC925db2DF291A1,
            0x79c58f70905f734641735bc61e45c19dd9ad60bc0000000000000000000004e7,
            2,
            1,
            0.3e18,
            PoolType.STABLE
        );

        controller.addRebalancingRewardHandler(
            0x2d9d3e3D0655766Aa801Ae0f6dC925db2DF291A1, address(handler)
        );

        // USDC / DOLA
        omnipool.changeUnderlyingPool(
            2,
            0xb139946D2F0E71b38e2c75d03D87C5E16339d2CD,
            0xff4ce5aaab5a627bf82f4a571ab1ce94aa365ea6000200000000000000000426,
            1,
            0,
            0.3e18,
            PoolType.STABLE
        );

        controller.addRebalancingRewardHandler(
            0xb139946D2F0E71b38e2c75d03D87C5E16339d2CD, address(handler)
        );

        pools.push(address(omnipool));

        vm.startPrank(opal);

        registryAccess.addRole(ROLE_MINT_LP_TOKEN, address(omnipool));
        registryAccess.addRole(ROLE_BURN_LP_TOKEN, address(omnipool));

        // USDC
        oracle.addPriceFeed(
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
            address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6)
        );

        // STG
        oracle.addPriceFeed(
            address(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6),
            address(0x7A9f34a0Aa917D438e9b6E630067062B7F8f6f3d)
        );

        // DAI
        oracle.addPriceFeed(
            address(0x6B175474E89094C44Da98b954EedeAC495271d0F),
            address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9)
        );

        // USDT
        oracle.addPriceFeed(
            address(0xdAC17F958D2ee523a2206206994597C13D831ec7),
            address(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D)
        );

        // DOLA
        oracle.addPriceFeed(
            address(0x865377367054516e17014CcdED1e7d814EDC9ce4),
            address(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D)
        );

        // WETH
        oracle.addPriceFeed(
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419)
        );

        bptOracle.setHeartbeat(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 15 * 86_400);
        bptOracle.setHeartbeat(0xAf5191B0De278C7286d6C7CC6ab6BB8A73bA2Cd6, 15 * 86_400);
        bptOracle.setHeartbeat(0x6B175474E89094C44Da98b954EedeAC495271d0F, 15 * 86_400);
        bptOracle.setHeartbeat(0xdAC17F958D2ee523a2206206994597C13D831ec7, 15 * 86_400);
        bptOracle.setHeartbeat(0x865377367054516e17014CcdED1e7d814EDC9ce4, 15 * 86_400);
        bptOracle.setHeartbeat(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 15 * 86_400);

        vm.startPrank(address(user));

        balanceTracker = usdc.balanceOf(user);
    }

    function testDepositAndWithdraw() public {
        for (uint256 i = 0; i < pools.length; i++) {
            _testDeposit(pools[i]);
            _testWithdraw(pools[i]);
        }
    }

    function setTokenBalance(address who, address token, uint256 amt) internal {
        bytes4 sel = IERC20(token).balanceOf.selector;
        stdstore.target(token).sig(sel).with_key(who).checked_write(amt);
    }

    function _testDeposit(address poolAddress) internal {
        IOmnipool pool = IOmnipool(poolAddress);
        IERC20Metadata token = IERC20Metadata(pool.getUnderlyingToken());
        console.log("-----");
        console.log("Depositing into Pool: %s", token.symbol());
        uint256 depositAmount = 10_000 * 10 ** token.decimals();
        setTokenBalance(user, address(token), 100_000 * 10 ** token.decimals());
        vm.startPrank(user);

        token.approve(poolAddress, 10_000 * 10 ** token.decimals());
        pool.deposit(depositAmount, 1);
        depositAmounts[poolAddress] = depositAmount;
        uint256 stakedBalance = IERC20(pool.getLpToken()).balanceOf(user);
        assertApproxEqRel(stakedBalance, depositAmount, 0.1e18);
        stakedBalances[poolAddress] = stakedBalance;
        console.log("Successfully deposited into pool: %s", token.symbol());
    }

    function _testWithdraw(address poolAddress) internal {
        IOmnipool pool = IOmnipool(poolAddress);
        vm.roll(1);
        IERC20Metadata token = IERC20Metadata(pool.getUnderlyingToken());
        console.log("-----");
        console.log("Withdrawing from Pool: %s", token.symbol());
        uint256 underlyingBefore = token.balanceOf(user);
        uint256 depositAmount = depositAmounts[poolAddress];
        uint256 stakedBalance = stakedBalances[poolAddress];
        uint256 withdrawAmount = stakedBalance / 2;
        uint256 totalUnderlying = pool.totalUnderlying();
        pool.withdraw(withdrawAmount, withdrawAmount / 2);
        uint256 underlyingDiff = token.balanceOf(user) - underlyingBefore;
        assertApproxEqRel(pool.totalUnderlying(), totalUnderlying - withdrawAmount, 0.1e18);
        assertApproxEqRel(depositAmount / 2, underlyingDiff, 0.1e18);
        console.log("Successfully withdrew from pool: %s", token.symbol());

        vm.stopPrank();
    }

    function testUpdateWeight() public {
        uint256[] memory initWeight = omnipool.getAllUnderlyingPoolWeight();
        for (uint256 i = 0; i < initWeight.length; i++) {
            console.log("init weight: %s", initWeight[i]);
        }

        uint256 decimals = 6;
        vm.startPrank(user);
        address poolAddress = address(omnipool);
        console.log(poolAddress);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(
            address(omnipool), 100_000 * 10 ** decimals
        );

        vm.stopPrank();

        vm.roll(1);
        vm.prank(user);
        omnipool.deposit(10_000 * 10 ** decimals, 1);

        skip(14 days);

        IOmnipoolController.WeightUpdate[] memory newWeights =
            new IOmnipoolController.WeightUpdate[](3);
        newWeights[0] = IOmnipoolController.WeightUpdate(TRI_POOL, 0.8e18);
        newWeights[1] = IOmnipoolController.WeightUpdate(USDC_STG, 0.2e18);
        newWeights[2] = IOmnipoolController.WeightUpdate(USDC_DOLA, 0);
        vm.prank(opal);
        controller.updateWeights(poolAddress, newWeights);

        initWeight = omnipool.getAllUnderlyingPoolWeight();
        for (uint256 i = 0; i < initWeight.length; i++) {
            console.log("after weight: %s", initWeight[i]);
        }

        assertEq(omnipool.getPoolWeight(0), 0.8e18);
        assertEq(omnipool.getPoolWeight(1), 0.2e18);
        assertEq(omnipool.getPoolWeight(2), 0);
    }

    function testRebalance() public {
        deal(address(gem), 0x1234567890123456789012345678901234561234, type(uint256).max);

        vm.startPrank(0x1234567890123456789012345678901234561234);
        IERC20(gem).approve(
            registryContract.getContract(CONTRACT_GEM_MINTER_REBALANCING_REWARD), type(uint256).max
        );
        uint256[] memory initWeight = omnipool.getAllUnderlyingPoolWeight();
        for (uint256 i = 0; i < initWeight.length; i++) {
            console.log("init weight: %s", initWeight[i]);
        }

        uint256 decimals = 6;
        vm.startPrank(user);
        address poolAddress = address(omnipool);
        console.log(poolAddress);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(
            address(omnipool), 100_000 * 10 ** decimals
        );

        vm.stopPrank();

        vm.roll(1);
        vm.prank(user);
        omnipool.deposit(10_000 * 10 ** decimals, 1);

        skip(14 days);

        IOmnipoolController.WeightUpdate[] memory newWeights =
            new IOmnipoolController.WeightUpdate[](3);
        newWeights[0] = IOmnipoolController.WeightUpdate(TRI_POOL, 0.8e18);
        newWeights[1] = IOmnipoolController.WeightUpdate(USDC_STG, 0.2e18);
        newWeights[2] = IOmnipoolController.WeightUpdate(USDC_DOLA, 0);
        vm.prank(opal);
        controller.updateWeights(poolAddress, newWeights);

        initWeight = omnipool.getAllUnderlyingPoolWeight();
        for (uint256 i = 0; i < initWeight.length; i++) {
            console.log("init weight: %s", initWeight[i]);
        }

        skip(1 hours);

        assertTrue(omnipool.rebalancingRewardActive());

        uint256 deviationBefore = omnipool.computeTotalDeviation();
        uint256 gemBalanceBefore = IERC20(gem).balanceOf(user);
        vm.roll(2);
        vm.prank(user);
        omnipool.deposit(10_000 * 10 ** decimals, 1);
        uint256 deviationAfter = omnipool.computeTotalDeviation();
        assertLt(deviationAfter, deviationBefore);
        uint256 gemBalanceAfter = IERC20(gem).balanceOf(user);
        assertGt(gemBalanceAfter, gemBalanceBefore);
        console.log("reward user balance before: %s", gemBalanceBefore);
        console.log("reward user balance after: %s", gemBalanceAfter);
    }

    function testSetRewardManager() public {
        address newRewardManager = address(0x9999);

        vm.prank(opal);
        omnipool.setRewardManager(newRewardManager);

        assert(omnipool.rewardManager() == newRewardManager);
    }

    function testSetRewardManagerShouldNotBeSetTwice() public {
        address newRewardManager = address(0x9999);

        vm.prank(opal);
        omnipool.setRewardManager(newRewardManager);

        vm.expectRevert(abi.encodeWithSelector(CannotSetRewardManagerTwice.selector));

        vm.prank(opal);
        omnipool.setRewardManager(newRewardManager);
    }

    function testSetRewardManagerShouldNotBeSetToNull() public {
        vm.expectRevert(abi.encodeWithSelector(NullAddress.selector));
        vm.prank(opal);
        omnipool.setRewardManager(address(0));
    }

    function testSetRewardManagerShouldRevertIfNotCalledByOpalTeam() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        vm.prank(user);
        omnipool.setRewardManager(address(0x9999));
    }

    function testApproveForRewardManagerShouldRevertIfNotCalledByTheRewardManager() public {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        vm.prank(user);
        omnipool.approveForRewardManager(address(0x9999), 100);
    }
}
