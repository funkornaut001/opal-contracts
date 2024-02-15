// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "src/pools/BPTOracle.sol";
import "src/pools/Omnipool.sol";
import "src/PriceFeed.sol";
import "src/utils/constants.sol";
import "src/tokens/GEM.sol";
import {RegistryAccess} from "src/utils/RegistryAccess.sol";
import {RegistryContract} from "src/utils/RegistryContract.sol";

import "forge-std/Test.sol";

contract SetupTest is Test {
    RegistryAccess public registryAccess;
    RegistryContract public registryContract;
    PriceFeed public oracle;
    BPTOracle public bptOracle;
    GEM public gem;
    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    uint256 public alicePrivKey = 0x1011;
    address public alice = vm.addr(alicePrivKey);

    address public bob = vm.addr(0x20);

    address public admin = vm.addr(0x30);

    address public opal = vm.addr(0x40);

    function setUp() public virtual {
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(admin, "admin");
        vm.label(opal, "opal");

        // RegistryAccess
        vm.prank(admin);
        registryAccess = new RegistryAccess();
        vm.prank(admin);
        registryAccess.addOpalRole(opal);
        vm.startPrank(opal);
        address accessRegistry = address(registryAccess);
        registryContract = new RegistryContract(accessRegistry);
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));
        registryContract.setContract(CONTRACT_BALANCER_VAULT, BALANCER_VAULT);
        registryContract.setContract(CONTRACT_WETH, WETH);
        registryContract.setContract(CONTRACT_OPAL_TREASURY, opal);
        registryContract.setContract(CONTRACT_INCENTIVES_MS, opal);

        oracle = new PriceFeed(address(registryContract));
        registryContract.setContract(CONTRACT_PRICE_FEED_ORACLE, address(oracle));

        console.log("priceFeedOracle: %s", address(oracle));

        bptOracle = new BPTOracle(address(registryContract));
        registryContract.setContract(CONTRACT_BPT_ORACLE, address(bptOracle));

        console.log("setup oracle: %s", registryContract.getContract(CONTRACT_PRICE_FEED_ORACLE));

        gem = new GEM();
        registryContract.setContract(CONTRACT_GEM_TOKEN, address(gem));
    }

    function testSetUp() public {
        assertEq(registryContract.getContract(CONTRACT_REGISTRY_ACCESS), address(registryAccess));
        assertEq(registryContract.getContract(CONTRACT_PRICE_FEED_ORACLE), address(oracle));
        assertEq(registryContract.getContract(CONTRACT_BPT_ORACLE), address(bptOracle));
        assertEq(registryContract.getContract(CONTRACT_GEM_TOKEN), address(gem));
    }
}
