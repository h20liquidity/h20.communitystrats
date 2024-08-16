// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;
import {console2, Test} from "forge-std/Test.sol";

import {
    IOrderBookV3,
    IO
} from "rain.orderbook.interface/interface/deprecated/v3/IOrderBookV3.sol";
import {
    IOrderBookV4,
    OrderV3,
    OrderConfigV3,
    TakeOrderConfigV3,
    TakeOrdersConfigV3,
    ActionV1,
    EvaluableV3,
    SignedContextV1
} from "rain.orderbook.interface/interface/IOrderBookV4.sol";
import {IParserV2} from "rain.interpreter.interface/interface/IParserV2.sol";
import {IOrderBookV4ArbOrderTaker} from "rain.orderbook.interface/interface/IOrderBookV4ArbOrderTaker.sol";
import {IExpressionDeployerV3} from "rain.interpreter.interface/interface/deprecated/IExpressionDeployerV3.sol";
import {IInterpreterV3} from "rain.interpreter.interface/interface/IInterpreterV3.sol";
import {IInterpreterStoreV2} from "rain.interpreter.interface/interface/IInterpreterStoreV2.sol";
import {StrategyTests, IRouteProcessor, LibStrategyDeployment, LibComposeOrders,IInterpreterV3,FullyQualifiedNamespace,LibNamespace,StateNamespace} from "h20.test-std/StrategyTests.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "h20.test-std/lib/LibProcessStream.sol";

uint256 constant VAULT_ID = uint256(keccak256("vault"));


/// @dev https://basescan.org/address/0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D
IERC20 constant BASE_WLTH= IERC20(0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D); 

/// @dev https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
IERC20 constant BASE_USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

function baseWlthIo() pure returns (IO memory) {
    return IO(address(BASE_WLTH), 18, VAULT_ID);
}

function baseUsdcIo() pure returns (IO memory) {
    return IO(address(BASE_USDC), 6, VAULT_ID);
} 

contract StopLimitTest is StrategyTests { 

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 18463466;
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_BASE"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function setUp() public {
        selectFork();
        
        iParser = IParserV2(0x56394785a22b3BE25470a0e03eD9E0a939C47b9b);
        iStore = IInterpreterStoreV2(0x6E4b01603edBDa617002A077420E98C86595748E); 
        iInterpreter = IInterpreterV3(0x379b966DC6B117dD47b5Fc5308534256a4Ab1BCC); 
        iExpressionDeployer = IExpressionDeployerV3(0x56394785a22b3BE25470a0e03eD9E0a939C47b9b); 
        iOrderBook = IOrderBookV4(0x7A44459893F99b9d9a92d488eb5d16E4090f0545);
        iArbInstance = IOrderBookV4ArbOrderTaker(0x03B6A05D487e760edb383754dA58C801D860D1d0);
        iRouteProcessor = IRouteProcessor(address(0x0389879e0156033202C44BF784ac18fC02edeE4f)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x5e01e44aE1969e16B9160d903B6F2aa991a37B21); 
    }

    function testWlthTrancheInitBuy() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        uint256 expectedRatio = 20e18;
        uint256 expectedOrderAmount = 6000000000000000000;

        
        LibStrategyDeployment.StrategyDeploymentV4 memory strategy = LibStrategyDeployment.StrategyDeploymentV4(
            getEncodedSellWlthRoute(),
            getEncodedBuyWlthRoute(),
            0,
            0,
            1e18,
            10000e6,
            expectedRatio,
            expectedOrderAmount,
            "strategies/wlth-tranche-init.rain",
            "wlth-tranches.buy.initialized.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new SignedContextV1[](0)
        );

        checkStrategyCalculationsArbOrder(strategy);

    }

    function testWlthTrancheInitSell() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        uint256 expectedRatio = 42000000000000000;
        uint256 expectedOrderAmount = 123809523809523809523;

        
        LibStrategyDeployment.StrategyDeploymentV4 memory strategy = LibStrategyDeployment.StrategyDeploymentV4(
            getEncodedBuyWlthRoute(),
            getEncodedSellWlthRoute(),
            0,
            0,
            1e6,
            1000000e18,
            expectedRatio,
            expectedOrderAmount,
            "strategies/wlth-tranche-init.rain",
            "wlth-tranches.sell.initialized.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new SignedContextV1[](0)
        );

        checkStrategyCalculationsArbOrder(strategy);

    }

     function testSuccessiveTranches() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();
        
        LibStrategyDeployment.StrategyDeploymentV4 memory strategy = LibStrategyDeployment.StrategyDeploymentV4(
            getEncodedSellWlthRoute(),
            getEncodedBuyWlthRoute(),
            0,
            0,
            100000e18,
            10000e6,
            0,
            0,
            "strategies/wlth-tranche-init.rain",
            "wlth-tranches.buy.initialized.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new SignedContextV1[](0)    
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);


        // Tranche 0
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            uint256 expectedTrancheAmount = 6000000000000000000;
            uint256 expectedTrancheRatio = 20e18;

            assertEq(strategyAmount, expectedTrancheAmount);
            assertEq(strategyRatio, expectedTrancheRatio);
        }

        // Tranche 1
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            uint256 expectedTrancheAmount = 6100000000000000000;
            uint256 expectedTrancheRatio = 20500000000000000000;

            assertEq(strategyAmount, expectedTrancheAmount);
            assertEq(strategyRatio, expectedTrancheRatio);
        }

        // Tranche 2
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            uint256 expectedTrancheAmount = 6200000000000000000;
            uint256 expectedTrancheRatio = 21000000000000000000;

            assertEq(strategyAmount, expectedTrancheAmount);
            assertEq(strategyRatio, expectedTrancheRatio);
        }

    }

    function getEncodedBuyWlthRoute() internal pure returns (bytes memory) {
        bytes memory BUY_WLTH_ROUTE =
            hex"02833589fCD6eDb6E08f4c7C32D4f71b54bdA0291301ffff011536EE1506e24e5A36Be99C73136cD82907A902E0103B6A05D487e760edb383754dA58C801D860D1d0";
            
        return abi.encode(BUY_WLTH_ROUTE);
    }

    function getEncodedSellWlthRoute() internal pure returns (bytes memory) {
        bytes memory SELL_WLTH_ROUTE =
            hex"0299b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D01ffff011536EE1506e24e5A36Be99C73136cD82907A902E0003B6A05D487e760edb383754dA58C801D860D1d0";
            
        return abi.encode(SELL_WLTH_ROUTE);
    }

}