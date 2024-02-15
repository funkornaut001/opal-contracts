// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Minter} from "src/tokenomics/Minter.sol";
import {GaugeController} from "src/tokenomics/GaugeController.sol";
import {MockedERC20} from "src/mocks/MockedERC20.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";
import {MockedGaugeController} from "src/mocks/MockedGaugeController.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    ROLE_MINT_ESCROW_TOKEN,
    WEEK,
    SCALED_ONE,
    INFLATION_DELAY,
    INITIAL_MINTER_RATE,
    RATE_END_TIMESTAMP,
    RATE_REDUCTION_COEFFICIENT,
    RATE_REDUCTION_TIME
} from "src/utils/constants.sol";
import {MockedLiquidityGauge} from "src/mocks/MockedLiquidityGauge.sol";
import {ILiquidityGauge} from "src/interfaces/Gauge/ILiquidityGauge.sol";
import {IGaugeController} from "src/interfaces/Gauge/IGaugeController.sol";

contract MinterTest is Test {
    MockedERC20 public token;
    Minter public minter;
    address public gaugeController;

    address alice = address(0x10);
    address bob = address(0x20);
    address admin = address(0x99);

    function setUp() external {
        vm.warp(1000 days);
        RegistryAccess registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(admin);
        vm.prank(admin);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        token = new MockedERC20("TOKEN", "TKN");

        gaugeController = address(new MockedGaugeController());

        minter = new Minter(
            address(token),
            address(gaugeController)
        );
        vm.prank(admin);
        registryAccess.addRole(ROLE_MINT_ESCROW_TOKEN, address(minter));

        token.mint(address(minter), 100 ether);
    }
}

contract MinterGettersSettersTest is MinterTest {
    error InvalidParameters();
    error TimestampTooFarInFuture();

    function test_availableSupply() external {
        vm.warp(INFLATION_DELAY + block.timestamp + 6 weeks);
        minter.updateMiningParameters();
        uint256 supply = minter.availableSupply();
        assertEq(supply, 259_615_384_615_384_615_238_400);
    }

    function test_startEpochTimeWrite() external {
        vm.warp(INFLATION_DELAY + block.timestamp + 6 weeks);
        uint256 startEpochTime = minter.startEpochTimeWrite();
        assertEq(startEpochTime, 54_950_400);
    }

    function test_futureEpochTimeWrite() external {
        vm.warp(INFLATION_DELAY + block.timestamp + 6 weeks);
        uint256 futureEpochTime = minter.futureEpochTimeWrite();
        assertEq(futureEpochTime, 118_022_400);
    }

    function test_toggleApprovedMint() external {
        assertEq(minter.allowedMinterProxy(bob, alice), false);
        vm.prank(alice);
        minter.toggleApprovedMint(bob);
        assertEq(minter.allowedMinterProxy(bob, alice), true);
    }

    function test_mintableInTimeframe() external {
        vm.warp(INFLATION_DELAY + block.timestamp + 6 weeks);
        minter.updateMiningParameters();
        uint256 mintable = minter.mintableInTimeframe(block.timestamp, block.timestamp + 10 weeks);
        uint256 mintableFarAway = minter.mintableInTimeframe(
            block.timestamp, block.timestamp + RATE_REDUCTION_TIME + 10 weeks
        );
        assertEq(mintable, 432_692_307_692_307_692_064_000);
        assertEq(mintableFarAway, 1_642_299_107_142_857_112_000_000);
    }

    function test_mintableInTimeframe_shouldRevertIfStartIsAfterEnd() external {
        vm.expectRevert(InvalidParameters.selector);
        minter.mintableInTimeframe(block.timestamp + 1 weeks, block.timestamp);
    }

    function test_mintableInTimeframe_shouldRevertIfEndIsTooFarInFuture() external {
        vm.expectRevert(TimestampTooFarInFuture.selector);
        minter.mintableInTimeframe(block.timestamp, block.timestamp + 1 + RATE_REDUCTION_TIME * 2);
    }
}

contract MinterUpdateMiningParametersTest is MinterTest {
    error CannotUpdate();

    /**
     * @notice  Should revert if block.timestamp < startEpochTime + RATE_REDUCTION_TIME
     */
    function test_shouldRevertIfBlockTimestampIsLessThanStartEpochTimePlusRateReductionTime()
        external
    {
        vm.warp(block.timestamp + INFLATION_DELAY + 1);
        minter.updateMiningParameters();
        vm.expectRevert(CannotUpdate.selector);
        minter.updateMiningParameters();
    }

    /**
     * @notice  Should update mining parameters and initialize the rate to INITIAL_MINTER_RATE
     */
    function test_shouldUpdateMiningParameters() external {
        vm.warp(block.timestamp + INFLATION_DELAY + 1);
        uint256 _startEpochTime = minter.startEpochTime();

        minter.updateMiningParameters();

        assertEq(minter.rate(), INITIAL_MINTER_RATE);
        assertEq(minter.startEpochTime(), _startEpochTime + RATE_REDUCTION_TIME);
        assertEq(minter.miningEpoch(), 0);
    }

    /**
     * @notice  Should update mining parameters and update the rate
     */
    function test_shouldUpdateMiningParametersAndRate() external {
        uint256 endOfFirstEpoch = block.timestamp + INFLATION_DELAY;
        vm.warp(endOfFirstEpoch);
        uint256 _startEpochTime = minter.startEpochTime();

        minter.updateMiningParameters();
        vm.warp(endOfFirstEpoch + RATE_REDUCTION_TIME);
        minter.updateMiningParameters();

        assertEq(minter.startEpochSupply(), INITIAL_MINTER_RATE * RATE_REDUCTION_TIME);
        assertEq(minter.rate(), INITIAL_MINTER_RATE * RATE_REDUCTION_COEFFICIENT / SCALED_ONE);
        assertEq(minter.startEpochTime(), _startEpochTime + RATE_REDUCTION_TIME * 2);
        assertEq(minter.miningEpoch(), 1);
    }
}

contract MinterMintTest is MinterTest {
    error GaugeNotAdded();
    error ExceedsAllowedSupply();

    uint256 INTEGRATED_FRACTION = SCALED_ONE;

    address liquidityGauge;

    function initMocks() internal {
        liquidityGauge = address(new MockedLiquidityGauge());

        vm.mockCall(
            liquidityGauge,
            abi.encodeWithSelector(ILiquidityGauge(liquidityGauge).integrateFraction.selector),
            abi.encode(INTEGRATED_FRACTION)
        );
        vm.mockCall(
            gaugeController,
            abi.encodeWithSelector(IGaugeController(gaugeController).getGaugeType.selector),
            abi.encode(1)
        );
    }

    /**
     * @notice  Mint should revert if gauge is not added
     */
    function test_mintShouldRevertIfGaugeIsNotAdded() external {
        vm.mockCall(
            gaugeController,
            abi.encodeWithSelector(IGaugeController(gaugeController).getGaugeType.selector),
            abi.encode(0)
        );
        vm.expectRevert(abi.encodeWithSelector(GaugeNotAdded.selector));
        minter.mint(address(0x1));
    }

    /**
     * @notice Mint should revert because the available supply is 0
     */
    function test_mintShouldRevertIfTheMintedAmountExceedTheEpochAvailableSupply() external {
        initMocks();

        vm.expectRevert(ExceedsAllowedSupply.selector);
        minter.mint(liquidityGauge);
    }

    /**
     * @notice Mint should succeed
     */
    function test_mint() external {
        initMocks();

        vm.warp(block.timestamp + RATE_REDUCTION_TIME / 2);

        vm.expectCall(
            address(token), abi.encodeCall(token.transfer, (alice, INTEGRATED_FRACTION)), 1
        );

        vm.prank(alice);
        minter.mint(liquidityGauge);

        assertEq(minter.mintedSupply(), INTEGRATED_FRACTION);
        assertEq(minter.minted(alice, liquidityGauge), INTEGRATED_FRACTION);
        assertEq(token.balanceOf(alice), INTEGRATED_FRACTION);
    }

    /**
     * @notice Mint for someone else
     */
    function test_mintFor() external {
        initMocks();
        vm.warp(block.timestamp + RATE_REDUCTION_TIME / 2);

        vm.expectCall(
            address(token), abi.encodeCall(token.transfer, (alice, INTEGRATED_FRACTION)), 1
        );

        vm.prank(alice);
        minter.toggleApprovedMint(bob);

        vm.prank(bob);
        minter.mintFor(liquidityGauge, alice);
    }

    /**
     * @notice Should not be a able to mint for someone else if not allowed
     */
    function test_mintForShouldNotMintIfCallerIsNotAllowed() external {
        initMocks();
        vm.warp(block.timestamp + RATE_REDUCTION_TIME / 2);

        vm.expectCall(
            address(token), abi.encodeCall(token.transfer, (alice, INTEGRATED_FRACTION)), 0
        );

        vm.prank(bob);
        minter.mintFor(liquidityGauge, alice);
    }

    /**
     * @notice Mint multiple
     */
    function test_mintMultiple() external {
        initMocks();
        vm.warp(block.timestamp + RATE_REDUCTION_TIME / 2);
        address liquidityGauge2 = address(new MockedLiquidityGauge());
        address[] memory gauges = new address[](2);
        gauges[0] = liquidityGauge;
        gauges[1] = liquidityGauge2;

        vm.mockCall(
            liquidityGauge2,
            abi.encodeWithSelector(ILiquidityGauge(liquidityGauge2).integrateFraction.selector),
            abi.encode(INTEGRATED_FRACTION)
        );

        vm.expectCall(
            address(token), abi.encodeCall(token.transfer, (alice, INTEGRATED_FRACTION)), 2
        );

        vm.prank(alice);
        minter.mintMultiple(gauges);
    }
}
