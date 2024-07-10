// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;
import {console2, Test} from "forge-std/Test.sol";

import {
    IOrderBookV3,
    IO,
    OrderV2,
    OrderConfigV2,
    TakeOrderConfigV2,
    TakeOrdersConfigV2
} from "rain.orderbook.interface/interface/IOrderBookV3.sol";
import {IOrderBookV3ArbOrderTaker} from "rain.orderbook.interface/interface/IOrderBookV3ArbOrderTaker.sol";
import {IParserV1} from "rain.interpreter.interface/interface/IParserV1.sol";
import {IExpressionDeployerV3} from "rain.interpreter.interface/interface/IExpressionDeployerV3.sol";
import { EvaluableConfigV3, SignedContextV1} from "rain.interpreter.interface/interface/IInterpreterCallerV2.sol";
import {IInterpreterV2,SourceIndexV2} from "rain.interpreter.interface/interface/IInterpreterV2.sol";
import {IInterpreterStoreV2} from "rain.interpreter.interface/interface/IInterpreterStoreV2.sol";
import {StrategyTests, IRouteProcessor, LibStrategyDeployment, LibComposeOrders} from "h20.test-std/StrategyTests.sol";
import {LibEncodedDispatch} from "rain.interpreter.interface/lib/caller/LibEncodedDispatch.sol";
import {StateNamespace, LibNamespace, FullyQualifiedNamespace} from "rain.interpreter.interface/lib/ns/LibNamespace.sol";
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

contract WlthGridTradingTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 16819021;
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_BASE"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function getNamespace() public view returns (FullyQualifiedNamespace) {
        return LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this));
    }

    function setUp() public {
        selectFork();
        
        PARSER = IParserV1(0xF836f2746B407136a5bCB515495949B1edB75184);
        STORE = IInterpreterStoreV2(0x6E4b01603edBDa617002A077420E98C86595748E); 
        INTERPRETER = IInterpreterV2(0x379b966DC6B117dD47b5Fc5308534256a4Ab1BCC); 
        EXPRESSION_DEPLOYER = IExpressionDeployerV3(0x56394785a22b3BE25470a0e03eD9E0a939C47b9b); 
        ORDERBOOK = IOrderBookV3(0x2AeE87D75CD000583DAEC7A28db103B1c0c18b76);
        ARB_INSTANCE = IOrderBookV3ArbOrderTaker(0x199b22ce0c9fD88476cCaA2d2aB253Af38BAE3Ae);
        ROUTE_PROCESSOR = IRouteProcessor(address(0x83eC81Ae54dD8dca17C3Dd4703141599090751D1)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C); 

        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C);
    } 

    // Test the 'wlth-grid-trading' strategy
    function testWlthGridTradingBuy() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        uint256 expectedRatio = 40e18;
        uint256 expectedAmountOutputMax = 5e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            1e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/wlth/wlth-grid-trading.rain",
            "grid-trading.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function testWlthGridTradingSell() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        uint256 expectedRatio = 0.02e18;
        uint256 expectedAmountOutputMax = 250e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            10000e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/wlth/wlth-grid-trading.rain",
            "grid-trading.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );
        
        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    } 

    // Test the 'wlth-grid-recharging-linear' strategy
    function testWlthGridRechargeBuy() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        uint256 expectedRatio = 40e18;
        uint256 expectedAmountOutputMax = 5e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            1e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/wlth/wlth-grid-recharging-linear.rain",
            "grid-recharging.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function testWlthGridRechargeSell() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        uint256 expectedRatio = 0.02e18;
        uint256 expectedAmountOutputMax = 250e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            10000e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/wlth/wlth-grid-recharging-linear.rain",
            "grid-recharging.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );
        
        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    }

    // Test shy grid
    function testWlthShyGridBuy() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            0,
            1e18,
            0,
            0,
            "strategies/wlth/wlth-grid-recharging-shy.rain",
            "shy-grid-recharging.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        //Tranche 0- Full Tranche
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 + (2.5 * 0) = 40
            uint256 expectedRatio = 40e18;

            // 5 + (1 * 0) = 5
            uint256 expectedAmountOutputMax = 5e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        // Tranche 1 - Shy Tranche
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 + (2.5 * 1) = 42.5
            uint256 expectedTrancheRatio = 42.5e18; 

            // 5 + (1 * 1) = 6
            uint256 expectedTrancheAmount = 6e18;

            // 10% of the expectedTrancheAmount
            uint256 expectedShyTrancheAmount = expectedTrancheAmount / 10;

            assertEq(strategyRatio, expectedTrancheRatio);
            assertEq(strategyAmount, expectedShyTrancheAmount);
        }
    }

    function testWlthShyGridSell() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            1e6,
            10000e18,
            0,
            0,
            "strategies/wlth/wlth-grid-recharging-shy.rain",
            "shy-grid-recharging.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        
        //Tranche 0- Full Tranche
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 + (0.002 * 0) = 0.02
            uint256 expectedRatio = 0.02e18;

            // 250 * 0.02 = 5
            uint256 expectedAmountOutputMax = 250e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        // Tranche 1 - Shy Tranche
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 + (0.002 * 1) = 0.022
            uint256 expectedTrancheRatio = 0.022e18; 

            // 27.272727272727272727 * 0.022 = 0.6
            uint256 expectedShyTrancheAmount = 27.272727272727272727e18;

            assertEq(strategyRatio, expectedTrancheRatio);
            assertEq(strategyAmount, expectedShyTrancheAmount);
        } 

    }

    // Test grid exponential price
    function testWlthGridExpPriceBuy() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            0,
            1e18,
            0,
            0,
            "strategies/wlth/wlth-grid-recharging-exponential-price.rain",
            "grid-recharging-exp-price.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        //Tranche 0- Full Tranche
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 * (1 + 0.05)^0 = 40
            uint256 expectedRatio = 40e18;

            // 5 + (1 * 0) = 5
            uint256 expectedAmountOutputMax = 5e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 1
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 * (1 + 0.05)^1 = 42
            uint256 expectedRatio = 42e18;

            // 5 + (1 * 1) = 6
            uint256 expectedAmountOutputMax = 6e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 2
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 * (1 + 0.05)^2 = 44.1
            uint256 expectedRatio = 44.099999999999999000e18;

            // 5 + (1 * 2) = 7
            uint256 expectedAmountOutputMax = 7e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

    }

    function testWlthGridExpPriceSell() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            1e6,
            10000e18,
            0,
            0,
            "strategies/wlth/wlth-grid-recharging-exponential-price.rain",
            "grid-recharging-exp-price.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        
        //Tranche 0
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 * (1 + 0.002)^0 = 0.02
            uint256 expectedRatio = 0.02e18;

            // 250 * 0.02 = 5
            uint256 expectedAmountOutputMax = 250e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 1
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 * (1 + 0.002)^1 = 0.02004
            uint256 expectedRatio = 0.02004e18;

            // 300 * 0.02004 = 6
            uint256 expectedAmountOutputMax = 299.401197604790419161e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 2
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 * (1 + 0.002)^2 = 0.02008008
            uint256 expectedRatio = 0.020080079999999999e18;

            // 348 * 0.02008 = 7
            uint256 expectedAmountOutputMax = 348.604188827932973803e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }
    }

    // Test grid exponential amount
    function testWlthGridExpAmountBuy() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            0,
            1e18,
            0,
            0,
            "strategies/wlth/wlth-grid-recharging-exponential-amount.rain",
            "grid-recharging-exp-amt.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        //Tranche 0- Full Tranche
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 + (2.5 * 0) = 40
            uint256 expectedRatio = 40e18;

            // 5 * (1 + 0.05)^0 = 5
            uint256 expectedAmountOutputMax = 5e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 1
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 + (2.5 * 1) = 42.5
            uint256 expectedRatio = 42.5e18;

            // 5 * (1 + 0.05)^1 = 5.25
            uint256 expectedAmountOutputMax = 5.25e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 2
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 40 + (2.5 * 2) = 45
            uint256 expectedRatio = 45e18;

            // 5 * (1 + 0.05)^2 = 5.5125
            uint256 expectedAmountOutputMax = 5.512499999999999875e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }
    }

    function testWlthGridExpAmountSell() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            1e6,
            10000e18,
            0,
            0,
            "strategies/wlth/wlth-grid-recharging-exponential-amount.rain",
            "grid-recharging-exp-amt.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        
        //Tranche 0
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 + (0.002 * 0) = 0.02
            uint256 expectedRatio = 0.02e18;

            // 250 * 0.02 = 5
            uint256 expectedAmountOutputMax = 250e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 1
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 + (0.002 * 1) = 0.022
            uint256 expectedRatio = 0.022e18;

            // 238.636363636363636363 * 0.022 = 5.25
            uint256 expectedAmountOutputMax = 238.636363636363636363e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        //Tranche 2
        {
            vm.recordLogs();
            takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            // 0.02 + (0.002 * 2) = 0.024
            uint256 expectedRatio = 0.024e18;

            // 229.687499999999994791 * 0.024 = 5.5125
            uint256 expectedAmountOutputMax = 229.687499999999994791e18;

            assertEq(strategyRatio, expectedRatio);
            assertEq(strategyAmount, expectedAmountOutputMax);
        }

        // //Tranche 1
        // {
        //     vm.recordLogs();
        //     takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

        //     Vm.Log[] memory entries = vm.getRecordedLogs();
        //     (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

        //     // 0.02 * (1 + 0.002)^1 = 0.02004
        //     uint256 expectedRatio = 0.02004e18;

        //     // 300 * 0.02004 = 6
        //     uint256 expectedAmountOutputMax = 299.401197604790419161e18;

        //     assertEq(strategyRatio, expectedRatio);
        //     assertEq(strategyAmount, expectedAmountOutputMax);
        // }

        // //Tranche 2
        // {
        //     vm.recordLogs();
        //     takeExternalOrder(order, strategy.inputTokenIndex, strategy.outputTokenIndex);

        //     Vm.Log[] memory entries = vm.getRecordedLogs();
        //     (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

        //     // 0.02 * (1 + 0.002)^2 = 0.02008008
        //     uint256 expectedRatio = 0.020080079999999999e18;

        //     // 348 * 0.02008 = 7
        //     uint256 expectedAmountOutputMax = 348.604188827932973803e18;

        //     assertEq(strategyRatio, expectedRatio);
        //     assertEq(strategyAmount, expectedAmountOutputMax);
        // }
    }    
    

    function getEncodedBuyWlthRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02833589fCD6eDb6E08f4c7C32D4f71b54bdA0291301ffff011536EE1506e24e5A36Be99C73136cD82907A902E01";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellWlthRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"0299b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D01ffff011536EE1506e24e5A36Be99C73136cD82907A902E00";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }



}
