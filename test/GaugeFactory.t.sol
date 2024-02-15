// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VoteLocker} from "src/tokenomics/VoteLocker.sol";
import {MockedERC20} from "src/mocks/MockedERC20.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";
import {GaugeFactory} from "src/tokenomics/GaugeFactory.sol";
import {MockedLiquidityGauge} from "src/mocks/MockedLiquidityGauge.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    ROLE_MINT_ESCROW_TOKEN,
    WEEK,
    SCALED_ONE
} from "src/utils/constants.sol";

contract GaugeFactoryTest is Test {
    GaugeFactory gaugeFactory;
    RegistryAccess registryAccess;

    address public opalTeam = vm.addr(0x99);

    address public alice = vm.addr(0x10);

    error NotAuthorized();
    error AddressZero();

    function setUp() external {
        registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(opalTeam);
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        MockedLiquidityGauge liquidityGauge = new MockedLiquidityGauge();

        gaugeFactory = new GaugeFactory(address(liquidityGauge), address(registryContract));
    }

    /**
     * @notice  Should revert if the caller has not the Opal Team role
     */
    function test_setImplementationShouldRevertIfCallerHasNotOpalTeamRole() external {
        vm.expectRevert(NotAuthorized.selector);
        vm.prank(alice);
        gaugeFactory.setImplementation(address(0x123));
    }

    /**
     * @notice  Should update implementation
     */
    function test_shouldSetImplementation() external {
        vm.prank(opalTeam);
        gaugeFactory.setImplementation(address(0x123));

        assertEq(gaugeFactory.implementation(), address(0x123));
    }

    /**
     * @notice  Should deploy a new liquidity gauge
     */
    function test_shouldDeployGauge() external {
        vm.prank(alice);
        address gauge = gaugeFactory.deployGauge(address(0x124));

        assertEq(gaugeFactory.gaugeToLpToken(gauge), address(0x124));
        assertEq(gaugeFactory.lpTokenToGauge(address(0x124)), gauge);
        assertEq(gaugeFactory.isFactoryGauge(gauge), true);
        assertEq(gauge == address(0), false);
    }

    /**
     * @notice  Should revert if the lpToken is the zero address
     */
    function test_shouldRevertIfLpTokenIsZeroAddress() external {
        vm.expectRevert(AddressZero.selector);
        vm.prank(alice);
        gaugeFactory.deployGauge(address(0));
    }
}
