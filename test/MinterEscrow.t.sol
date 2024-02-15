// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EscrowedToken} from "src/tokenomics/EscrowedToken.sol";
import {MinterEscrow} from "src/tokenomics/MinterEscrow.sol";
import {GaugeController} from "src/tokenomics/GaugeController.sol";
import {VoteLocker} from "src/tokenomics/VoteLocker.sol";
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
    RATE_END_TIMESTAMP,
    MINTER_ESCROW_RATE
} from "src/utils/constants.sol";
import {MockedLiquidityGauge} from "src/mocks/MockedLiquidityGauge.sol";
import {ILiquidityGauge} from "src/interfaces/Gauge/ILiquidityGauge.sol";
import {IGaugeController} from "src/interfaces/Gauge/IGaugeController.sol";

contract MinterEscrowTest is Test {
    MockedERC20 public token;
    EscrowedToken public escrowedToken;
    MinterEscrow public minterEscrow;
    address public gaugeController;

    address alice = address(0x10);
    address bob = address(0x20);
    address admin = address(0x99);

    function setUp() external {
        RegistryAccess registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(admin);
        vm.prank(admin);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        token = new MockedERC20("80GEM-20ETH BPT", "gemBPT");
        escrowedToken =
            new EscrowedToken(address(token), "Escrowed Gem", "esGEM",address(registryContract));

        gaugeController = address(new MockedGaugeController());

        minterEscrow = new MinterEscrow(
            address(token),
            address(escrowedToken),
            address(gaugeController),
            address(registryAccess)
        );
        vm.prank(admin);
        registryAccess.addRole(ROLE_MINT_ESCROW_TOKEN, address(minterEscrow));

        token.mint(address(minterEscrow), 100 ether);
    }
}

contract MinterEscrowGettersSettersTest is MinterEscrowTest {
    error InvalidParameters();
    error NotAuthorized();

    function test_availableSupply() external {
        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);
        uint256 supply = minterEscrow.availableSupply();
        assertEq(supply, 90_384_615_384_615_384_336_000);
    }

    function test_availableSupply_zeroDay() external {
        vm.warp(INFLATION_DELAY + block.timestamp);
        uint256 supply = minterEscrow.availableSupply();
        assertEq(supply, 0);
    }

    function test_setMinterProxy() external {
        assertEq(minterEscrow.allowedMinterProxy(bob, alice), false);
        vm.prank(alice);
        minterEscrow.setMinterProxy(bob, true);
        assertEq(minterEscrow.allowedMinterProxy(bob, alice), true);
    }

    function test_distributionEnd() external {
        assertEq(
            minterEscrow.distributionEnd(), block.timestamp + INFLATION_DELAY + RATE_END_TIMESTAMP
        );
    }

    function test_rate() external {
        assertEq(minterEscrow.rate(), MINTER_ESCROW_RATE);
        vm.warp(INFLATION_DELAY + block.timestamp + RATE_END_TIMESTAMP + 1);
        assertEq(minterEscrow.rate(), 0);
    }

    function test_mintableInTimeframe() external {
        uint256 mintable = minterEscrow.mintableInTimeframe(
            block.timestamp, block.timestamp + 1 weeks + INFLATION_DELAY
        );
        assertEq(mintable, 90_384_615_384_615_384_336_000);
    }

    function test_mintableInTimeframe_shouldRevertIfStartIsAfterEnd() external {
        vm.expectRevert(InvalidParameters.selector);
        minterEscrow.mintableInTimeframe(block.timestamp + 1 weeks, block.timestamp);
    }

    function test_updateApprove() external {
        vm.prank(admin);
        minterEscrow.updateApprove(100 ether);
        assertEq(token.allowance(address(minterEscrow), address(escrowedToken)), 100 ether);
    }

    function test_updateApprove_shouldRevertIfNotAuthorized() external {
        vm.expectRevert(NotAuthorized.selector);
        minterEscrow.updateApprove(100 ether);
    }
}

contract MinterEscrowMintTest is MinterEscrowTest {
    error GaugeNotAdded();
    error ExceedsAllowedSupply();

    uint256 INTEGRATED_FRACTION = SCALED_ONE;

    address liquidityGauge;

    function initMocks() internal {
        liquidityGauge = address(new MockedLiquidityGauge());

        vm.mockCall(
            liquidityGauge,
            abi.encodeWithSelector(
                ILiquidityGauge(liquidityGauge).integrateFractionBoosted.selector
            ),
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
        minterEscrow.mint(address(0x1));
    }

    /**
     * @notice Mint should revert due to underflow error is the first INFLATION DELAY is not passed
     */
    function test_mintShouldRevertIfInflationDelayIsNotPassed() external {
        initMocks();
        vm.expectRevert();
        minterEscrow.mint(liquidityGauge);
    }

    /**
     * @notice Mint should revert because the available supply is 0
     */
    function test_mintShouldRevertIfTheMintedAmountExceedAvailableSupply() external {
        initMocks();
        vm.warp(INFLATION_DELAY + block.timestamp);

        vm.expectRevert(ExceedsAllowedSupply.selector);
        minterEscrow.mint(liquidityGauge);
    }

    /**
     * @notice Mint should succeed
     */
    function test_mint() external {
        initMocks();
        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);

        vm.expectCall(
            address(escrowedToken),
            abi.encodeCall(escrowedToken.mint, (INTEGRATED_FRACTION, alice, block.timestamp)),
            1
        );

        vm.prank(alice);
        minterEscrow.mint(liquidityGauge);
    }

    /**
     * @notice Mint multiple
     */
    function test_mintMultiple() external {
        initMocks();
        address liquidityGauge2 = address(new MockedLiquidityGauge());
        address[] memory gauges = new address[](2);
        gauges[0] = liquidityGauge;
        gauges[1] = liquidityGauge2;

        vm.mockCall(
            liquidityGauge2,
            abi.encodeWithSelector(
                ILiquidityGauge(liquidityGauge2).integrateFractionBoosted.selector
            ),
            abi.encode(INTEGRATED_FRACTION)
        );

        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);

        vm.expectCall(
            address(escrowedToken),
            abi.encodeCall(escrowedToken.mint, (INTEGRATED_FRACTION * 2, alice, block.timestamp)),
            1
        );

        vm.prank(alice);
        minterEscrow.mintMultiple(gauges);
    }

    /**
     * @notice Mint for someone else
     */
    function test_mintFor() external {
        initMocks();
        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);

        vm.expectCall(
            address(escrowedToken),
            abi.encodeCall(escrowedToken.mint, (INTEGRATED_FRACTION, alice, block.timestamp)),
            1
        );

        vm.prank(alice);
        minterEscrow.setMinterProxy(bob, true);

        vm.prank(bob);
        minterEscrow.mintFor(liquidityGauge, alice);
    }

    /**
     * @notice Should not be a able to mint for someone else if not allowed
     */
    function test_mintForShouldNotMintIfCallerIsNotAllowed() external {
        initMocks();
        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);

        vm.expectCall(
            address(escrowedToken),
            abi.encodeCall(escrowedToken.mint, (INTEGRATED_FRACTION, alice, block.timestamp)),
            0
        );

        vm.prank(bob);
        minterEscrow.mintFor(liquidityGauge, alice);
    }

    /**
     * @notice Mint multiple for someone else
     */
    function test_mintMultipleFor() external {
        initMocks();
        address liquidityGauge2 = address(new MockedLiquidityGauge());
        address[] memory gauges = new address[](2);
        gauges[0] = liquidityGauge;
        gauges[1] = liquidityGauge2;

        vm.mockCall(
            liquidityGauge2,
            abi.encodeWithSelector(
                ILiquidityGauge(liquidityGauge2).integrateFractionBoosted.selector
            ),
            abi.encode(INTEGRATED_FRACTION)
        );

        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);

        vm.expectCall(
            address(escrowedToken),
            abi.encodeCall(escrowedToken.mint, (INTEGRATED_FRACTION * 2, alice, block.timestamp)),
            1
        );

        vm.prank(alice);
        minterEscrow.setMinterProxy(bob, true);

        vm.prank(bob);
        minterEscrow.mintMultipleFor(gauges, alice);
    }

    /**
     * @notice Should not be a able to mint multiple for someone else if not allowed
     */
    function test_mintMultipleForShouldNotMintIfCallerIsNotAllowed() external {
        initMocks();
        address liquidityGauge2 = address(new MockedLiquidityGauge());
        address[] memory gauges = new address[](2);
        gauges[0] = liquidityGauge;
        gauges[1] = liquidityGauge2;

        vm.mockCall(
            liquidityGauge2,
            abi.encodeWithSelector(
                ILiquidityGauge(liquidityGauge2).integrateFractionBoosted.selector
            ),
            abi.encode(INTEGRATED_FRACTION)
        );

        vm.warp(INFLATION_DELAY + block.timestamp + 1 weeks);

        vm.expectCall(
            address(escrowedToken),
            abi.encodeCall(escrowedToken.mint, (INTEGRATED_FRACTION * 2, alice, block.timestamp)),
            0
        );

        vm.prank(bob);
        minterEscrow.mintMultipleFor(gauges, alice);
    }
}
