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
    CONTRACT_GAUGE_CONTROLLER,
    SCALED_ONE,
    INFLATION_DELAY,
    INITIAL_MINTER_RATE,
    RATE_REDUCTION_TIME,
    MINTER_ESCROW_RATE
} from "src/utils/constants.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {LiquidityGauge} from "src/tokenomics/LiquidityGauge.sol";
import {MockedMinter} from "src/mocks/MockedMinter.sol";
import {MockedMinterEscrow} from "src/mocks/MockedMinterEscrow.sol";
import {MockedVoteLocker} from "src/mocks/MockedVoteLocker.sol";
import {IMinter} from "src/interfaces/Minter/IMinter.sol";
import {IMinterEscrow} from "src/interfaces/Minter/IMinterEscrow.sol";
import {IGaugeController} from "src/interfaces/Gauge/IGaugeController.sol";

contract LiquidityGaugeTest is Test {
    MockedERC20 public token;
    address public minter;
    address public minterEscrow;
    MockedVoteLocker public voteLocker;
    address public gaugeController;

    address admin = address(0x99);
    address alice = address(0x10);
    address bob = address(0x11);
    address charlie = address(0x12);

    LiquidityGauge public liquidityGaugeImplementation;
    LiquidityGauge public liquidityGauge;

    function setUp() external virtual {
        RegistryAccess registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(admin);

        minter = address(new MockedMinter());
        minterEscrow = address(new MockedMinterEscrow());
        voteLocker = new MockedVoteLocker();
        gaugeController = address(new MockedGaugeController());

        vm.prank(admin);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));
        vm.prank(admin);
        registryContract.setContract(CONTRACT_GAUGE_CONTROLLER, address(gaugeController));

        liquidityGaugeImplementation =
            new LiquidityGauge(minter, minterEscrow, address(voteLocker), address(registryContract));

        liquidityGauge = LiquidityGauge(Clones.clone(address(liquidityGaugeImplementation)));

        voteLocker.mint(alice, 10 ether);
        voteLocker.mint(bob, 10 ether);
        voteLocker.mint(charlie, 5 ether);
    }
}

contract LiquidityGaugeInitializeTest is LiquidityGaugeTest {
    error CannotInitialize();

    MockedERC20 public lpToken;

    function initMocks() internal {
        vm.mockCall(
            minter, abi.encodeWithSelector(IMinter(minter).rate.selector), abi.encode(SCALED_ONE)
        );
        vm.mockCall(
            minterEscrow,
            abi.encodeWithSelector(IMinterEscrow(minterEscrow).rate.selector),
            abi.encode(SCALED_ONE)
        );
        vm.mockCall(
            minter,
            abi.encodeWithSelector(IMinter(minter).futureEpochTimeWrite.selector),
            abi.encode(INFLATION_DELAY)
        );
    }

    /**
     * @notice Should revert if already initialized
     */
    function test_shouldRevertIfAlreadyInitialized() external {
        lpToken = new MockedERC20("Test", "TST");
        initMocks();

        liquidityGauge.initialize(address(lpToken));
        vm.expectRevert(CannotInitialize.selector);
        liquidityGauge.initialize(address(0x99));
    }

    function test_initialize() external {
        string memory lpSymbol = "TST";
        lpToken = new MockedERC20("Test", lpSymbol);
        initMocks();

        liquidityGauge.initialize(address(lpToken));
        address lpTokenAddress = liquidityGauge.lpToken();
        address factory = liquidityGauge.factory();
        string memory name = liquidityGauge.name();
        string memory symbol = liquidityGauge.symbol();
        uint256 inflationRate = liquidityGauge.inflationRate();
        uint256 inflationRateBoosted = liquidityGauge.inflationRateBoosted();
        uint256 futureEpochTime = liquidityGauge.futureEpochTime();

        assertEq(lpTokenAddress, address(lpToken));
        assertEq(factory, address(this));
        assertEq(name, string(abi.encodePacked("Opal ", lpSymbol, " Gauge Deposit")));
        assertEq(symbol, string(abi.encodePacked(lpSymbol, "-Gauge")));
        assertEq(inflationRate, SCALED_ONE);
        assertEq(inflationRateBoosted, SCALED_ONE);
        assertEq(futureEpochTime, INFLATION_DELAY);
    }
}

contract LiquidityGaugeGettersTest is LiquidityGaugeTest {
    MockedERC20 public lpToken;

    function test_decimals() external {
        assertEq(liquidityGauge.decimals(), 18);
    }
}

contract LiquidityGaugeUserCheckpointTest is LiquidityGaugeTest {
    MockedERC20 public lpToken;

    uint256 CURRENT_TS = 9999;

    error CallerNotAllowed();

    function initMocks() internal {
        vm.warp(4999);
        // The new epoch just started
        vm.mockCall(
            minter,
            abi.encodeWithSelector(IMinter(minter).futureEpochTimeWrite.selector),
            abi.encode(RATE_REDUCTION_TIME + block.timestamp)
        );
        vm.mockCall(
            minter,
            abi.encodeWithSelector(IMinter(minter).rate.selector),
            abi.encode(INITIAL_MINTER_RATE)
        );
        vm.mockCall(
            minterEscrow,
            abi.encodeWithSelector(IMinterEscrow(minterEscrow).rate.selector),
            abi.encode(MINTER_ESCROW_RATE)
        );
        vm.mockCall(
            minterEscrow,
            abi.encodeWithSelector(IMinterEscrow(minterEscrow).distributionEnd.selector),
            abi.encode(SCALED_ONE) // ??
        );
        vm.mockCall(
            gaugeController,
            abi.encodeWithSelector(IGaugeController(gaugeController).checkpointGauge.selector),
            abi.encode(SCALED_ONE) // ??
        );
        vm.mockCall(
            gaugeController,
            abi.encodeWithSelector(IGaugeController(gaugeController).gaugeRelativeWeight.selector),
            abi.encode(SCALED_ONE) // ?? ~ ok
        );

        string memory lpSymbol = "TST";
        lpToken = new MockedERC20("Test", lpSymbol);

        lpToken.mint(alice, 10 ether);
        lpToken.mint(bob, 10 ether);
        lpToken.mint(charlie, 5 ether);

        liquidityGauge.initialize(address(lpToken));
        vm.warp(CURRENT_TS);
    }

    /**
     * @notice Should checkpoint the user
     * - Initial Period is 0
     * - Initial integrateInvSupply is 0 (same for boosted one)
     * - Initial inflation rate is SCALDED_ONE
     */
    function test_userCheckpoint() external {
        initMocks();
        vm.prank(alice);
        liquidityGauge.userCheckpoint(alice);

        assertEq(liquidityGauge.period(), 1);
        assertEq(liquidityGauge.integrateInvSupply(1), 0);
        assertEq(liquidityGauge.integrateInvSupplyBoosted(), 0);
        assertEq(liquidityGauge.inflationRate(), INITIAL_MINTER_RATE);
        assertEq(liquidityGauge.inflationRateBoosted(), MINTER_ESCROW_RATE);
        assertEq(liquidityGauge.periodTimestamp(1), CURRENT_TS);
    }

    /**
     * @notice Should revert if user is not msg.sender and not MINTER_ESCROW and not MINTER
     */
    function test_shouldRevertIfNotSender() external {
        vm.expectRevert(abi.encodeWithSelector(CallerNotAllowed.selector));
        vm.prank(alice);
        liquidityGauge.userCheckpoint(address(this));
    }
}

contract LiquidityGaugeSetKilledTest is LiquidityGaugeTest {
    function test_setKilled() external {
        vm.prank(admin);
        liquidityGauge.setKilled(true);
        assertEq(liquidityGauge.isKilled(), true);
    }

    function test_setKilled_shouldRevertIfNotAdmin() external {
        vm.expectRevert();
        vm.prank(alice);
        liquidityGauge.setKilled(true);
    }
}

/**
 * @notice This inherits from LiquidityGaugeUserCheckpointTest because we need to checkpoint
 */
contract LiquidityGaugeUserDepositTest is LiquidityGaugeUserCheckpointTest {
    /**
     * @notice Should deposit
     */
    function test_userDeposit() external {
        initMocks();

        vm.prank(alice);
        lpToken.approve(address(liquidityGauge), 1 ether);
        vm.prank(alice);
        liquidityGauge.deposit(1 ether);

        assertEq(lpToken.balanceOf(address(liquidityGauge)), 1 ether);
        assertEq(lpToken.balanceOf(alice), 9 ether);
        assertEq(liquidityGauge.balanceOf(alice), 1 ether);
        assertEq(liquidityGauge.totalSupply(), 1 ether);
        assertEq(liquidityGauge.workingBalances(alice), 640_000_000_000_000_000);
        assertEq(liquidityGauge.workingSupply(), 640_000_000_000_000_000);
    }

    /**
     * @notice Should deposit for another user
     */
    function test_userDepositForAnotherUser() external {
        initMocks();

        vm.prank(alice);
        lpToken.approve(address(liquidityGauge), 1 ether);
        vm.prank(alice);
        liquidityGauge.deposit(1 ether, bob);

        assertEq(lpToken.balanceOf(address(liquidityGauge)), 1 ether);
        assertEq(lpToken.balanceOf(alice), 9 ether);
        assertEq(liquidityGauge.balanceOf(bob), 1 ether);
    }

    /**
     * @notice Should create multiple deposits
     */
    function test_userMultipleDeposits() external {
        initMocks();

        vm.prank(alice);
        lpToken.approve(address(liquidityGauge), 2 ether);
        vm.prank(bob);
        lpToken.approve(address(liquidityGauge), 1 ether);
        vm.prank(charlie);
        lpToken.approve(address(liquidityGauge), 1 ether);

        vm.prank(alice);
        liquidityGauge.deposit(1 ether);
        vm.prank(bob);
        liquidityGauge.deposit(1 ether);
        vm.prank(charlie);
        liquidityGauge.deposit(1 ether);
        vm.prank(alice);
        liquidityGauge.deposit(1 ether);

        assertEq(liquidityGauge.period(), 4);
        assertEq(liquidityGauge.workingSupply(), 3_400_000_000_000_000_000);
        assertEq(liquidityGauge.totalSupply(), 4 ether);
    }
}

/**
 * @notice This inherits from LiquidityGaugeUserCheckpointTest because we need to checkpoint
 */
contract LiquidityGaugeUserWithdrawTest is LiquidityGaugeUserCheckpointTest {
    /**
     * @notice Should withdraw
     */
    function test_userWithdraw() external {
        initMocks();

        vm.prank(alice);
        lpToken.approve(address(liquidityGauge), 1 ether);
        vm.prank(alice);
        liquidityGauge.deposit(1 ether);
        vm.prank(alice);
        liquidityGauge.withdraw(1 ether);

        assertEq(lpToken.balanceOf(address(liquidityGauge)), 0 ether);
        assertEq(lpToken.balanceOf(alice), 10 ether);
        assertEq(liquidityGauge.balanceOf(alice), 0 ether);
        assertEq(liquidityGauge.totalSupply(), 0 ether);
        assertEq(liquidityGauge.workingBalances(alice), 0);
        assertEq(liquidityGauge.workingSupply(), 0);
    }

    /**
     * @notice Should create multiple withdraws
     */
    function test_userMultipleWithdraws() external {
        initMocks();

        vm.prank(alice);
        lpToken.approve(address(liquidityGauge), 2 ether);
        vm.prank(bob);
        lpToken.approve(address(liquidityGauge), 1 ether);
        vm.prank(charlie);
        lpToken.approve(address(liquidityGauge), 1 ether);

        vm.prank(alice);
        liquidityGauge.deposit(1 ether);
        vm.prank(bob);
        liquidityGauge.deposit(1 ether);
        vm.prank(charlie);
        liquidityGauge.deposit(1 ether);
        vm.prank(alice);
        liquidityGauge.deposit(1 ether);

        vm.prank(alice);
        liquidityGauge.withdraw(1 ether);
        vm.prank(bob);
        liquidityGauge.withdraw(1 ether);
        vm.prank(charlie);
        liquidityGauge.withdraw(1 ether);

        assertEq(liquidityGauge.period(), 7);
        assertEq(liquidityGauge.workingSupply(), 1_000_000_000_000_000_000);
        assertEq(liquidityGauge.totalSupply(), 1 ether);
    }
}
