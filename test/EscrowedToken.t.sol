// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EscrowedToken} from "src/tokenomics/EscrowedToken.sol";
import {VoteLocker} from "src/tokenomics/VoteLocker.sol";
import {MockedERC20} from "src/mocks/MockedERC20.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";
import {
    CONTRACT_REGISTRY_ACCESS,
    ROLE_MINT_ESCROW_TOKEN,
    WEEK,
    SCALED_ONE
} from "src/utils/constants.sol";

contract EscrowedTokenTest is Test {
    EscrowedToken escrowedToken;
    MockedERC20 token;
    RegistryAccess registryAccess;

    address public minterRole = vm.addr(0x98);
    address public opalTeam = vm.addr(0x99);

    address public alice = vm.addr(0x10);
    address public bob = vm.addr(0x20);
    address public charlie = vm.addr(0x30);

    function setUp() external {
        token = new MockedERC20("Opal", "GEM");

        registryAccess = new RegistryAccess();
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryAccess.addOpalRole(opalTeam);
        vm.prank(opalTeam);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));

        escrowedToken = new EscrowedToken(address(token),
             "Escrowed Gem Token", "esGEM", address(registryContract));
    }

    function claimMinterRole(address minter) internal {
        vm.prank(opalTeam);
        registryAccess.addRole(ROLE_MINT_ESCROW_TOKEN, minter);
    }

    function createAVesting(uint256 amount, address receiver, uint256 startTimestamp) internal {
        vm.prank(minterRole);
        token.mint(minterRole, amount);
        vm.prank(minterRole);
        token.approve(address(escrowedToken), amount);

        vm.warp(startTimestamp);

        claimMinterRole(minterRole);

        vm.prank(minterRole);
        escrowedToken.mint(amount, receiver, startTimestamp);
    }
}

contract EscrowedTokenInitializeTest is EscrowedTokenTest {
    /**
     * @notice Should set the locker allowance to max uint256 in the constructor
     */
    function test_initialize() external view {
        assert(escrowedToken.vestingDuration() == WEEK * 8);
        assert(escrowedToken.ratePerToken() == SCALED_ONE);
    }
}

contract EscrowedTokenERC20Test is EscrowedTokenTest {
    error CannotTransfer();
    /**
     * @notice Should not be able to transfer tokens
     */

    function test_transferShouldRevert() external {
        vm.expectRevert(abi.encodeWithSelector(CannotTransfer.selector));
        escrowedToken.transfer(alice, 1 ether);
    }
    /**
     * @notice Should not be able to transfer from tokens
     */

    function test_transferFromShouldRevert() external {
        vm.expectRevert(abi.encodeWithSelector(CannotTransfer.selector));
        escrowedToken.transferFrom(alice, bob, 1 ether);
    }
}

contract EscrowedTokenMintTest is EscrowedTokenTest {
    error NotAuthorized();
    error ZeroValue();
    error ZeroAddress();
    error InvalidTimestamp();

    /**
     * @notice Should not be able to mint if the sender is not a minter
     */
    function test_mintShouldRevertIfNotMinter() external {
        vm.expectRevert(abi.encodeWithSelector(NotAuthorized.selector));
        escrowedToken.mint(1 ether, alice, 1);
    }

    /**
     * @notice Should not be able to mint 0 tokens
     */
    function test_mintZeroAmountShouldRevert() external {
        claimMinterRole(minterRole);
        vm.expectRevert(abi.encodeWithSelector(ZeroValue.selector));
        vm.prank(minterRole);
        escrowedToken.mint(0, alice, 1);
    }

    /**
     * @notice Should not be able to mint if the receiver is the zero address
     */
    function test_mintZeroAddressShouldRevert() external {
        claimMinterRole(minterRole);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(minterRole);
        escrowedToken.mint(1 ether, address(0), 1);
    }

    /**
     * @notice Should not be able to mint if the start timestamp is in the past
     */
    function test_mintPastTimestampShouldRevert() external {
        uint256 startTimestamp = 10;
        claimMinterRole(minterRole);
        vm.expectRevert(abi.encodeWithSelector(InvalidTimestamp.selector));
        vm.warp(startTimestamp);
        vm.prank(minterRole);
        escrowedToken.mint(1 ether, alice, startTimestamp - 1);
    }

    /**
     * @notice Should transfer the tokens to the escrowed token contract
     */
    function test_mintShouldTransferTokens() external {
        uint256 amount = 1 ether;
        uint256 startTimestamp = 1;
        token.mint(alice, amount);
        vm.prank(alice);
        token.approve(address(escrowedToken), amount);

        vm.warp(startTimestamp);

        vm.expectCall(
            address(token),
            abi.encodeCall(token.transferFrom, (alice, address(escrowedToken), amount)),
            1
        );

        claimMinterRole(alice);
        vm.prank(alice);
        escrowedToken.mint(amount, alice, startTimestamp);

        (uint256 vindex, uint256 vamount,, uint48 vend, bool vclaimed) =
            escrowedToken.vestings(alice, 0);

        assertEq(vindex, 0);
        assertEq(vamount, amount);
        assertEq(vend, startTimestamp + escrowedToken.vestingDuration());
        assertEq(vclaimed, false);
        assertEq(escrowedToken.totalVesting(), amount);
        assertEq(escrowedToken.userVestingCount(alice), 1);
        uint256 balanceOfReceiver = escrowedToken.balanceOf(alice);
        assertEq(balanceOfReceiver, amount);
    }
}

contract EscrowedTokenClaimTest is EscrowedTokenTest {
    error InvalidIndex();
    error VestingAlreadyClaimed();
    error EmptyArray();

    function test_claimShouldRevertIfNoVesting() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidIndex.selector));
        escrowedToken.claim(0);
    }

    /**
     * @notice The claim should revert because it was already claimed
     */
    function test_claimShouldRevertIfItWasAlreadyClaimed() external {
        createAVesting(1 ether, alice, 1);

        vm.startPrank(alice);
        escrowedToken.claim(0);

        vm.expectRevert(abi.encodeWithSelector(VestingAlreadyClaimed.selector));
        escrowedToken.claim(0);
        vm.stopPrank();
    }

    /**
     * @notice Alice creates a vesting of 1 ether at week 0 and claims it after 4 weeks
     *      Bob creates a vesting of 1 ether at week 0 and claims it after 8 weeks
     *      Charlie creates a vesting of 1 ether at week 4 and claims it after 8 weeks
     *      - Alice should receive the half of the tokens because she claimed after half of the vesting duration
     *      - Bob should receive the full amount of tokens plus the Alice unclaimed tokens
     *      - Charlie should receive the full amount of tokens
     */
    function test_claimAmountShouldBeProportionateToTimePassedAndTokensShouldBeRedistributed()
        external
    {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
        uint256 amount = 1 ether;
        uint256 startTimestamp = block.timestamp;
        createAVesting(amount, alice, startTimestamp);
        createAVesting(amount, bob, startTimestamp);

        vm.warp(startTimestamp + WEEK * 4);

        vm.prank(alice);
        escrowedToken.claim(0);
        createAVesting(amount, charlie, startTimestamp + WEEK * 4);

        vm.warp(startTimestamp + WEEK * 8);

        vm.prank(bob);
        escrowedToken.claim(0);

        vm.warp(startTimestamp + WEEK * 12);

        vm.prank(charlie);
        escrowedToken.claim(0);

        uint256 balanceOfAlice = token.balanceOf(alice);
        uint256 balanceOfBob = token.balanceOf(bob);
        uint256 balanceOfCharlie = token.balanceOf(charlie);

        assertEq(balanceOfAlice, amount / 2);
        assertEq(balanceOfBob, amount + amount / 2);
        assertEq(balanceOfCharlie, amount);
    }

    /**
     * @notice Test claimMultiple
     */
    function test_claimMultiple() external {
        uint256 amount = 1 ether;
        uint256 startTimestamp = block.timestamp;
        createAVesting(amount, alice, startTimestamp);
        createAVesting(amount * 2, alice, startTimestamp);
        createAVesting(amount * 3, alice, startTimestamp);

        vm.warp(startTimestamp + WEEK * 8);

        uint256[] memory vestingIndex = new uint256[](2);
        vestingIndex[0] = 0;
        vestingIndex[1] = 1;
        vm.prank(alice);
        escrowedToken.claimMultiple(vestingIndex);

        (,,,, bool vclaimed) = escrowedToken.vestings(alice, 0);
        (,,,, bool vclaimed2) = escrowedToken.vestings(alice, 1);
        (,,,, bool vclaimed3) = escrowedToken.vestings(alice, 2);

        assertEq(vclaimed, true);
        assertEq(vclaimed2, true);
        assertEq(vclaimed3, false);
        uint256 balanceOfAlice = token.balanceOf(alice);
        assertEq(balanceOfAlice, amount * 3);
    }

    /**
     * @notice Test claimMultiple should revert if we pass an empty array
     */
    function test_claimMultipleShouldRevertIfEmptyArray() external {
        vm.expectRevert(abi.encodeWithSelector(EmptyArray.selector));
        uint256[] memory vestingIndex = new uint256[](0);
        escrowedToken.claimMultiple(vestingIndex);
    }

    /**
     * @notice Test claimAll
     */
    function test_claimAll() external {
        uint256 amount = 1 ether;
        uint256 startTimestamp = block.timestamp;
        createAVesting(amount, alice, startTimestamp);
        createAVesting(amount * 2, alice, startTimestamp);
        createAVesting(amount * 3, alice, startTimestamp);

        vm.warp(startTimestamp + WEEK * 8);

        vm.prank(alice);
        escrowedToken.claimAll();

        (,,,, bool vclaimed) = escrowedToken.vestings(alice, 0);
        (,,,, bool vclaimed2) = escrowedToken.vestings(alice, 1);
        (,,,, bool vclaimed3) = escrowedToken.vestings(alice, 2);

        assertEq(vclaimed, true);
        assertEq(vclaimed2, true);
        assertEq(vclaimed3, true);

        uint256 balanceOfAlice = token.balanceOf(alice);
        assertEq(balanceOfAlice, amount * 6);
    }
}

contract EscrowedTokenGettersTest is EscrowedTokenTest {
    error InvalidIndex();

    /**
     * @notice Test getUserVestings
     */
    function test_getUserVestings() external {
        uint256 amount = 1 ether;
        uint256 startTimestamp = block.timestamp;
        createAVesting(amount, alice, startTimestamp);
        createAVesting(amount * 2, alice, startTimestamp + 4 weeks);

        EscrowedToken.UserVesting[] memory vestings = escrowedToken.getUserVestings(alice);

        assertEq(vestings.length, 2);
        assertEq(vestings[0].index, 0);
        assertEq(vestings[0].amount, amount);
        assertEq(vestings[0].ratePerToken, SCALED_ONE);
        assertEq(vestings[0].end, uint48(startTimestamp + escrowedToken.vestingDuration()));
        assertEq(vestings[0].claimed, false);

        assertEq(vestings[1].index, 1);
        assertEq(vestings[1].amount, amount * 2);
        assertEq(vestings[1].ratePerToken, SCALED_ONE);
        assertEq(
            vestings[1].end, uint48(startTimestamp + escrowedToken.vestingDuration() + 4 weeks)
        );
        assertEq(vestings[1].claimed, false);
    }

    /**
     * @notice Test getUserActiveVestings
     */
    function test_getUserActiveVestings() external {
        uint256 amount = 1 ether;
        uint256 startTimestamp = block.timestamp;
        createAVesting(amount, alice, startTimestamp);
        createAVesting(amount * 2, alice, startTimestamp + 4 weeks);

        vm.prank(alice);
        escrowedToken.claim(0);
        EscrowedToken.UserVesting[] memory vestings = escrowedToken.getUserActiveVestings(alice);

        assertEq(vestings.length, 1);
        assertEq(vestings[0].index, 1);
        assertEq(vestings[0].amount, amount * 2);
        assertEq(vestings[0].ratePerToken, SCALED_ONE);
        assertEq(
            vestings[0].end, uint48(startTimestamp + escrowedToken.vestingDuration() + 4 weeks)
        );
        assertEq(vestings[0].claimed, false);
    }

    /**
     * @notice Test getVestingClaimValue
     */
    function test_getVestingClaimValue() external {
        uint256 amount = 1 ether;
        uint256 startTimestamp = block.timestamp;
        createAVesting(amount, alice, startTimestamp);

        vm.warp(startTimestamp + WEEK * 4);

        (uint256 currentValue, uint256 maxValue) = escrowedToken.getVestingClaimValue(alice, 0);

        assertEq(currentValue, amount / 2);
        assertEq(maxValue, amount);
    }

    /**
     * @notice Test getVestingClaimValue should revert if the index is invalid
     */
    function test_getVestingClaimValueShouldRevertIfInvalidIndex() external {
        vm.expectRevert(abi.encodeWithSelector(InvalidIndex.selector));
        escrowedToken.getVestingClaimValue(alice, 0);
    }
}
