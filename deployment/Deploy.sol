pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {GEM} from "../src/tokens/GEM.sol";
import {Omnipool} from "../src/pools/Omnipool.sol";
import {BPTOracle, PoolType} from "../src/pools/BPTOracle.sol";
import {RewardManager} from "../src/RewardManager.sol";
import {PriceFeed} from "../src/PriceFeed.sol";
import {VoteLocker} from "../src/tokenomics/VoteLocker.sol";
import {GaugeController} from "../src/tokenomics/GaugeController.sol";
import {EscrowedToken} from "../src/tokenomics/EscrowedToken.sol";
import {MinterEscrow} from "../src/tokenomics/MinterEscrow.sol";
import {Minter} from "../src/tokenomics/Minter.sol";
import {LiquidityGauge} from "../src/tokenomics/LiquidityGauge.sol";
import {GaugeFactory} from "../src/tokenomics/GaugeFactory.sol";
import {
    IWeightedPoolFactory,
    IRateProvider
} from "../src/interfaces/WeightedPool/IWeightedPoolFactory.sol";
import {IBalancerVault} from "../src/interfaces/Balancer/IBalancerVault.sol";
import {IWeightedPool} from "../src/interfaces/WeightedPool/IWeightedPool.sol";
import {IWETH} from "../src/interfaces/Token/IWETH.sol";
import {RegistryAccess} from "../src/utils/RegistryAccess.sol";
import {RegistryContract} from "../src/utils/RegistryContract.sol";
import {IRegistryContract} from "../src/interfaces/Registry/IRegistryContract.sol";
import {IRegistryAccess} from "../src/interfaces/Registry/IRegistryAccess.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAsset} from "balancer-v2-monorepo/pkg/interfaces/contracts/vault/IAsset.sol";
import {
    ROLE_OPAL_TEAM,
    CONTRACT_REGISTRY_ACCESS,
    CONTRACT_BPT_ORACLE,
    CONTRACT_GEM_TOKEN,
    CONTRACT_GAUGE_CONTROLLER,
    WEEK,
    CONTRACT_BAL_TOKEN,
    CONTRACT_AURA_TOKEN,
    CONTRACT_BALANCER_VAULT,
    CONTRACT_AURA_DEPOSIT_WRAPPER
} from "../src/utils/constants.sol";

contract DeployScript is Script {
    function setUp() external {}

    function run() external {
        vm.startBroadcast();
        console.log("----------------------- Deploying Opal Protocol -----------------------");

        address owner = msg.sender;

        string memory network = vm.envString("NETWORK");
        address weth = vm.envAddress(string.concat(network, "_WETH"));
        address usdc = vm.envAddress(string.concat(network, "_USDC"));
        address bal = vm.envAddress(string.concat(network, "_BAL"));
        address aura = vm.envAddress(string.concat(network, "_AURA"));
        address stg = vm.envAddress(string.concat(network, "_STG"));
        address dai = vm.envAddress(string.concat(network, "_DAI"));
        address usdt = vm.envAddress(string.concat(network, "_USDT"));
        address dola = vm.envAddress(string.concat(network, "_DOLA"));
        address balancerVault = vm.envAddress(string.concat(network, "_BALANCER_VAULT"));
        address auraDepositWrapper = vm.envAddress(string.concat(network, "_AURA_DEPOSIT_WRAPPER"));
        address auraPoolDaiUsdtUsdc =
            vm.envAddress(string.concat(network, "_AURA_POOL_DAI_USDT_USDC"));
        bytes32 auraPoolIdDaiUsdtUsdc =
            vm.envBytes32(string.concat(network, "_AURA_POOL_ID_DAI_USDT_USDC"));
        address auraPoolDolaUsdc = vm.envAddress(string.concat(network, "_AURA_POOL_DOLA_USDC"));
        bytes32 auraPoolIdDolaUsdc =
            vm.envBytes32(string.concat(network, "_AURA_POOL_ID_DOLA_USDC"));
        address auraPoolStgUsdc = vm.envAddress(string.concat(network, "_AURA_POOL_STG_USDC"));
        bytes32 auraPoolIdStgUsdc = vm.envBytes32(string.concat(network, "_AURA_POOL_ID_STG_USDC"));
        address usdcPriceFeed = vm.envAddress(string.concat(network, "_USDC_PRICE_FEED"));
        address stgPriceFeed = vm.envAddress(string.concat(network, "_STG_PRICE_FEED"));
        address daiPriceFeed = vm.envAddress(string.concat(network, "_DAI_PRICE_FEED"));
        address usdtPriceFeed = vm.envAddress(string.concat(network, "_USDT_PRICE_FEED"));
        address dolaPriceFeed = vm.envAddress(string.concat(network, "_DOLA_PRICE_FEED"));
        address wethPriceFeed = vm.envAddress(string.concat(network, "_WETH_PRICE_FEED"));
        address balancerWeightedPoolFactory =
            vm.envAddress(string.concat(network, "_BALANCER_WEIGHTED_POOL_FACTORY"));

        console.log("\n--------- Configurations ---------");
        console.log("-> Network: %s", network);
        console.log("-> Owner: %s", owner);
        console.log("--- Addresses ---");
        console.log("-> Balancer Vault: %s", balancerVault);
        console.log("-> Aura Deposit Wrapper: %s", auraDepositWrapper);
        console.log("-> WETH: %s", weth);
        console.log("-> USDC: %s", usdc);
        console.log("-> BAL: %s", bal);
        console.log("-> AURA: %s", aura);
        console.log("-> STG: %s", stg);
        console.log("-> DAI: %s", dai);
        console.log("-> USDT: %s", usdt);
        console.log("-> DOLA: %s", dola);
        console.log("- Pools -");
        console.log("-> Aura Pool DAI/USDT/USDC: %s", auraPoolDaiUsdtUsdc);
        console.log("-> Aura Pool DOLA/USDC: %s", auraPoolDolaUsdc);
        console.log("-> Aura Pool STG/USDC: %s", auraPoolStgUsdc);
        console.log("- Price Feeds -");
        console.log("-> USDC: %s", usdcPriceFeed);
        console.log("-> STG: %s", stgPriceFeed);
        console.log("-> DAI: %s", daiPriceFeed);
        console.log("-> USDT: %s", usdtPriceFeed);
        console.log("-> DOLA: %s", dolaPriceFeed);
        console.log("-> WETH: %s", wethPriceFeed);

        IBalancerVault balancerVaultContract = IBalancerVault(balancerVault);
        IWETH wethContract = IWETH(weth);

        console.log("\n--------- Deployment ---------");
        RegistryAccess registryAccess = new RegistryAccess();
        registryAccess.addOpalRole(owner);
        console.log("[1/20] - REGISTRY_ACCESS_ADDR deployed at: %s", address(registryAccess));
        RegistryContract registryContract = new RegistryContract(address(registryAccess));
        registryContract.setContract(CONTRACT_REGISTRY_ACCESS, address(registryAccess));
        registryContract.setContract(CONTRACT_BAL_TOKEN, bal);
        registryContract.setContract(CONTRACT_AURA_TOKEN, aura);
        registryContract.setContract(CONTRACT_BALANCER_VAULT, balancerVault);
        registryContract.setContract(CONTRACT_AURA_DEPOSIT_WRAPPER, auraDepositWrapper);

        console.log("[2/20] - REGISTRY_CONTRACT_ADDR deployed at: %s", address(registryContract));

        address gem = address(new GEM());
        IERC20 gemContract = IERC20(gem);
        registryContract.setContract(CONTRACT_GEM_TOKEN, gem);
        console.log("[3/20] - GEM_ADDR deployed at: %s", gem);

        PriceFeed priceFeed = new PriceFeed(address(registryContract));
        console.log("[4/20] - PRICE_FEED_ADDR deployed at: %s", address(priceFeed));

        address bptOracle = address(new BPTOracle(address(priceFeed)));
        registryContract.setContract(CONTRACT_BPT_ORACLE, bptOracle);

        console.log("[5/20] - BPT_ORACLE_ADDR deployed at: %s", bptOracle);

        Omnipool omnipool = new Omnipool(
            usdc,
            balancerVault,
            address(registryContract),
            auraDepositWrapper,
            "Opal USDC Pool",
            "opalUSDC"
        );
        console.log("[6/20] - OMNIPOOL_ADDR deployed at: %s", address(omnipool));

        RewardManager rewardManager = new RewardManager(
            address(omnipool),
            address(registryAccess),
            address(registryContract)
        );
        console.log("[7/20] - REWARD_MANAGER_ADDR deployed at: %s", address(rewardManager));

        IERC20[] memory tokens = new IERC20[](2);
        // Balancer sort tokens by address and GEM address is non deterministic
        tokens[0] = gem < weth ? IERC20(gem) : IERC20(weth);
        tokens[1] = gem < weth ? IERC20(weth) : IERC20(gem);
        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = IRateProvider(address(0));
        rateProviders[1] = IRateProvider(address(0));
        uint256[] memory normalizedWeights = new uint256[](2);
        normalizedWeights[0] = gem < weth ? 80 * 10 ** 16 : 20 * 10 ** 16;
        normalizedWeights[1] = gem < weth ? 20 * 10 ** 16 : 80 * 10 ** 16;

        address gemWethBalancerPoolAddr = IWeightedPoolFactory(balancerWeightedPoolFactory).create(
            "Opal 80 GEM 20 WETH",
            "O-80GEM-20WETH",
            tokens,
            normalizedWeights,
            rateProviders,
            uint256(3 * 10 ** 16),
            owner,
            0
        );
        IWeightedPool gemWethBalancerPool = IWeightedPool(gemWethBalancerPoolAddr);
        bytes32 gemWethBalancerPoolId = gemWethBalancerPool.getPoolId();

        console.log("[8/20] - GEM_WETH_BALANCER_POOL_ADDR deployed at: %s", gemWethBalancerPoolAddr);

        VoteLocker voteLocker = new VoteLocker(
            "Opal Vote Locker Token",
            "vlGEM",
            gemWethBalancerPoolAddr,
            address(registryContract)
        );

        console.log("[9/20] - VOTE_LOCKER_ADDR deployed at: %s", address(voteLocker));

        GaugeController gaugeController = new GaugeController(
            gemWethBalancerPoolAddr, // Might change
            address(voteLocker),
            address(registryContract)
        );
        registryContract.setContract(CONTRACT_GAUGE_CONTROLLER, address(gaugeController));

        console.log("[10/20] - GAUGE_CONTROLLER_ADDR deployed at: %s", address(gaugeController));

        EscrowedToken escrowedToken = new EscrowedToken(
            gem,
            "Opal Escrowed Token",
            "eGEM",
            address(registryContract)
        );

        console.log("[11/20] - ESCROWED_TOKEN_ADDR deployed at: %s", address(escrowedToken));

        MinterEscrow minterEscrow = new MinterEscrow(
            gem,
            address(escrowedToken),
            address(gaugeController),
            address(registryContract)
        );

        console.log("[12/20] - MINTER_ESCROW_ADDR deployed at: %s", address(minterEscrow));

        Minter minter = new Minter(
            gem,
            address(gaugeController)
        );

        console.log("[13/20] - MINTER_ADDR deployed at: %s", address(minter));

        LiquidityGauge liquidityGauge = new LiquidityGauge(
            address(minter),
            address(minterEscrow),
            address(voteLocker),
            address(registryContract)
        );

        console.log("[14/20] - LIQUIDITY_GAUGE_ADDR deployed at: %s", address(liquidityGauge));

        GaugeFactory gaugeFactory = new GaugeFactory(
            address(liquidityGauge),
            address(registryContract)
        );

        console.log("[15/20] - GAUGE_FACTORY_ADDR deployed at: %s", address(gaugeFactory));

        console.log("\n--------- Setup ---------");
        omnipool.changeUnderlyingPool(
            0, auraPoolStgUsdc, auraPoolIdStgUsdc, 0, 0, 40, PoolType.WEIGHTED
        );
        omnipool.changeUnderlyingPool(
            1, auraPoolDaiUsdtUsdc, auraPoolIdDaiUsdtUsdc, 2, 2, 30, PoolType.WEIGHTED
        );
        omnipool.changeUnderlyingPool(
            2, auraPoolDolaUsdc, auraPoolIdDolaUsdc, 1, 0, 30, PoolType.WEIGHTED
        );
        console.log("[12/15] - Omnipool underlying pools configured");
        omnipool.changeUnderlyingPool(
            0, auraPoolStgUsdc, auraPoolIdStgUsdc, 0, 0, 40, PoolType.WEIGHTED
        );
        omnipool.changeUnderlyingPool(
            1, auraPoolDaiUsdtUsdc, auraPoolIdDaiUsdtUsdc, 2, 2, 30, PoolType.WEIGHTED
        );
        omnipool.changeUnderlyingPool(
            2, auraPoolDolaUsdc, auraPoolIdDolaUsdc, 1, 0, 30, PoolType.WEIGHTED
        );
        console.log("[16/20] - Omnipool underlying pools configured");

        priceFeed.addPriceFeed(usdc, usdcPriceFeed);
        priceFeed.addPriceFeed(weth, wethPriceFeed);
        priceFeed.addPriceFeed(stg, stgPriceFeed);
        priceFeed.addPriceFeed(dai, daiPriceFeed);
        priceFeed.addPriceFeed(usdt, usdtPriceFeed);
        priceFeed.addPriceFeed(dola, dolaPriceFeed);

        console.log("[17/20] - BPTOracle price feeds configured");

        rewardManager.setExtraRewardTokens();

        console.log("[18/20] - RewardManager extra reward tokens configured");

        omnipool.setRewardManager(address(rewardManager));

        // ---------------------------------- Tokenomics ----------------------------------

        console.log("[19/20] - Omnipool reward manager configured");

        // Get WETH
        uint256 wethAmount = 10 ether;
        uint256 gemAmount = 100 ether;
        wethContract.deposit{value: wethAmount}();
        wethContract.approve(balancerVault, wethAmount);
        gemContract.approve(balancerVault, gemAmount);

        uint256 gemBalanceOf = gemContract.balanceOf(owner);
        IAsset[] memory assets = new IAsset[](2);
        assets[0] = gem < weth ? IAsset(gem) : IAsset(weth);
        assets[1] = gem < weth ? IAsset(weth) : IAsset(gem);
        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = gem < weth ? gemAmount : wethAmount;
        maxAmountsIn[1] = gem < weth ? wethAmount : gemAmount;
        bytes memory userData = abi.encode(IBalancerVault.JoinKind.INIT, maxAmountsIn);

        IBalancerVault.JoinPoolRequest memory jpr =
            IBalancerVault.JoinPoolRequest(assets, maxAmountsIn, userData, false);

        // Provide liquidity
        balancerVaultContract.joinPool(gemWethBalancerPoolId, owner, owner, jpr);

        console.log("[20/20] - Provided liquidity to GEM/WETH pool");

        console.log("\n--------- Finished ---------");

        vm.stopBroadcast();
    }
}
