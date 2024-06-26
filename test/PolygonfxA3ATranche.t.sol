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

/// @dev https://polygonscan.com/address/0x58c7B2828e7F2B2CaA0cC7fEef242fA3196d03df
IERC20 constant POLYGON_fxA3A = IERC20(0x58c7B2828e7F2B2CaA0cC7fEef242fA3196d03df); 

/// @dev https://polygonscan.com/address/0xc2132D05D31c914a87C6611C10748AEb04B58e8F
IERC20 constant POLYGON_USDT = IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

/// @dev https://polygonscan.com/address/0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
IERC20 constant POLYGON_USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

/// @dev https://polygonscan.com/address/0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
IERC20 constant POLYGON_WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);


function polygonfxA3AIo() pure returns (IO memory) {
    return IO(address(POLYGON_fxA3A), 18, VAULT_ID);
}

function polygonUsdtIo() pure returns (IO memory) {
    return IO(address(POLYGON_USDT), 6, VAULT_ID);
}

function polygonUsdcIo() pure returns (IO memory) {
    return IO(address(POLYGON_USDC), 6, VAULT_ID);
}

function polygonWmaticIo() pure returns (IO memory) {
    return IO(address(POLYGON_WMATIC), 18, VAULT_ID);
}


contract PolygonFixedGridDecimal is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 58626736;
    string constant fxA3A_TRANCHE_PATH = "strategies/fxA3A/3a-0003-tranche-recharge.rain";
    string constant fxA3A_POLYGON_ORACLE_DCA = "strategies/fxA3A/3a-polygon-oracle-dca-usdc.rain";

   
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_POLYGON"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function getNamespace() public view returns (FullyQualifiedNamespace) {
        return LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this));
    }

    function setUp() public {
        selectFork();
        
        PARSER = IParserV1(0x7A44459893F99b9d9a92d488eb5d16E4090f0545);
        INTERPRETER = IInterpreterV2(0x762adD85a30A83722feF2e029087C9D110B6a7b3); 
        STORE = IInterpreterStoreV2(0x59401C9302E79Eb8AC6aea659B8B3ae475715e86); 
        EXPRESSION_DEPLOYER = IExpressionDeployerV3(0xB3aC858bEAf7814892d3946A8C109A7D701DF8E7); 
        ORDERBOOK = IOrderBookV3(0xc95A5f8eFe14d7a20BD2E5BAFEC4E71f8Ce0B9A6); 
        ARB_INSTANCE = IOrderBookV3ArbOrderTaker(0x9a8545FA798A7be7F8E1B8DaDD79c9206357C015);
        ROUTE_PROCESSOR = IRouteProcessor(address(0xE7eb31f23A5BefEEFf76dbD2ED6AdC822568a5d2)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C);
    } 

    function testPolygonfxA3ATranche() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonfxA3AIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        uint256 expectedRatio = 333333333333333333333;
        uint256 expectedAmountOutputMax = 10e18; 

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellfxA3ARoute(address(ARB_INSTANCE)),
            getEncodedBuyfxA3ARoute(address(ARB_INSTANCE)),
            0,
            0,
            100000e18,
            100000e6,
            expectedRatio,
            expectedAmountOutputMax,
            fxA3A_TRANCHE_PATH,
            "polygon-a3a-tranches.buy.initialized.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );
        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function testPolygonUniV2OracleDcaHappyPath() public {
        
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonfxA3AIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        uint256 expectedRatio = 277.719904911824664183e18;
        uint256 expectedAmountOutputMax = 10853037074011243840; 

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellfxA3ARoute(address(ARB_INSTANCE)),
            getEncodedBuyfxA3ARoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            100000e6,
            expectedRatio,
            expectedAmountOutputMax,
            fxA3A_POLYGON_ORACLE_DCA,
            "polygon-h20liquidity-oracle-dca.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        {
            vm.recordLogs();

            // `arb()` called
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }
    }

    function testPolygonUniV2OracleDcaCooldown() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonfxA3AIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellfxA3ARoute(address(ARB_INSTANCE)),
            getEncodedBuyfxA3ARoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            100000e6,
            0,
            0,
            fxA3A_POLYGON_ORACLE_DCA,
            "polygon-h20liquidity-oracle-dca.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

        // Cooldown errors
        {
            vm.expectRevert("cooldown");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
        {   
            vm.warp(block.timestamp + 3599);
            vm.expectRevert("cooldown");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
        // Cooldown success
        {   
            vm.warp(block.timestamp + 1);
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

    }
    
    function testPolygonUniV2OracleDcaCardanoCheck() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonfxA3AIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellfxA3ARoute(address(ARB_INSTANCE)),
            getEncodedBuyfxA3ARoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            100000e6,
            0,
            0,
            fxA3A_POLYGON_ORACLE_DCA,
            "polygon-h20liquidity-oracle-dca.buy.test",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
        } 
        // Price changes within the same block, cardano check fails.
        {   
            vm.expectRevert("Buy price change.");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // Block time increases as new block are mined, cardano check succeeds
        {   
            vm.warp(block.timestamp + 1);
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

    }

    function testPartialTrade() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonfxA3AIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellfxA3ARoute(address(ARB_INSTANCE)),
            getEncodedBuyfxA3ARoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            100000e6,
            0,
            0,
            fxA3A_POLYGON_ORACLE_DCA,
            "polygon-h20liquidity-oracle-dca.buy.test",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
        }
        // warping to next block so the cardano check passes.
        vm.warp(block.timestamp + 1);  

        // Get the order output max for the order
        uint256 orderOuputMax;
        {
            (bytes memory bytecode, uint256[] memory constants) = PARSER.parse(
                LibComposeOrders.getComposedOrder(
                    vm, strategy.strategyFile, strategy.strategyScenario, strategy.buildPath, strategy.manifestPath
                )
            );
            (,,address expression,) = EXPRESSION_DEPLOYER.deployExpression2(bytecode, constants); 
            uint256[][] memory context = getOrderContext(uint256(keccak256("order-hash")));

            // Eval Order
            (uint256[] memory stack,) = INTERPRETER.eval2(
                STORE,
                getNamespace(),
                LibEncodedDispatch.encode2(expression, SourceIndexV2.wrap(0), type(uint16).max),
                context,
                new uint256[](0)
            );
            orderOuputMax = stack[1];
        }

        // Adjust order output max to appropriate decimal value, usdc has 6 decimals.
        orderOuputMax = orderOuputMax/1e12;
        
        vm.startPrank(APPROVED_EOA);
        address inputTokenAddress = order.validInputs[strategy.inputTokenIndex].token;
        IERC20(inputTokenAddress).safeApprove(address(ORDERBOOK), type(uint256).max);
        TakeOrderConfigV2[] memory innerConfigs = new TakeOrderConfigV2[](1);
        innerConfigs[0] = TakeOrderConfigV2(order, strategy.inputTokenIndex, strategy.outputTokenIndex, new SignedContextV1[](0));

        // If taker order amount is less than order output max, the trade fails
        {   
            TakeOrdersConfigV2 memory takeOrdersConfig =
            TakeOrdersConfigV2(0, 1, type(uint256).max, innerConfigs, "");
            vm.expectRevert("Partial trade");
            ORDERBOOK.takeOrders(takeOrdersConfig);
        }
        {   
            TakeOrdersConfigV2 memory takeOrdersConfig =
            TakeOrdersConfigV2(0, orderOuputMax - 1 , type(uint256).max, innerConfigs, "");
            vm.expectRevert("Partial trade");
            ORDERBOOK.takeOrders(takeOrdersConfig);
        }
        // Else trade succeeds
        {   
            TakeOrdersConfigV2 memory takeOrdersConfig =
            TakeOrdersConfigV2(0, orderOuputMax, type(uint256).max, innerConfigs, "");
            ORDERBOOK.takeOrders(takeOrdersConfig);
        }
        vm.stopPrank();
        
    }
    
    function getBounty(Vm.Log[] memory entries)
        public
        view
        returns (uint256 bounty)
    {
        for (uint256 j = 0; j < entries.length; j++) { 
            if (
                entries[j].topics[0] == keccak256("Transfer(address,address,uint256)") && 
                address(ARB_INSTANCE) == abi.decode(abi.encodePacked(entries[j].topics[1]), (address)) &&
                address(APPROVED_EOA) == abi.decode(abi.encodePacked(entries[j].topics[2]), (address))
                ) {

                bounty = abi.decode(entries[j].data, (uint256));
            }   
        }
    }

    function getEncodedBuyfxA3ARoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"022791Bca1f2de4661ED88A30C99A7a9449Aa8417401ffff0089470e8D8bB8655a94678d801e0089c4646f5E8401";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellfxA3ARoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"0258c7B2828e7F2B2CaA0cC7fEef242fA3196d03df01ffff0089470e8D8bB8655a94678d801e0089c4646f5E8400";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

}