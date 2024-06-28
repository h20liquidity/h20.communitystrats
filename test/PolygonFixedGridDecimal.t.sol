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


/// @dev https://polygonscan.com/address/0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39
IERC20 constant POLYGON_LINK = IERC20(0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39); 

/// @dev https://polygonscan.com/address/0xc2132D05D31c914a87C6611C10748AEb04B58e8F
IERC20 constant POLYGON_USDT = IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

/// @dev https://polygonscan.com/address/0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
IERC20 constant POLYGON_USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

/// @dev https://polygonscan.com/address/0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
IERC20 constant POLYGON_WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);


function polygonLinkIo() pure returns (IO memory) {
    return IO(address(POLYGON_LINK), 18, VAULT_ID);
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

    uint256 constant FORK_BLOCK_NUMBER = 58715054;
   
    
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

    function testLinkBuyLinkHappyPath() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonLinkIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        uint256 expectedRatio = 69323311538160288;
        uint256 expectedAmountOutputMax = 16279555611016865760;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellLinkRoute(address(ARB_INSTANCE)),
            getEncodedBuyLinkRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            10000e6,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/dca-oracle-polygon-univ3.rain",
            "polygon-link-dca-univ3.buy.deviation.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );


        // ArbOrderTaker 'arb'
        checkStrategyCalculationsArbOrder(strategy);

    }

    function testLinkSellLinkHappyPath() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonLinkIo();

        uint256 expectedRatio = 13936173715114621738; 
        uint256 expectedAmountOutputMax = 1085303707401124384;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyLinkRoute(address(ARB_INSTANCE)),
            getEncodedSellLinkRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            10000e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/dca-oracle-polygon-univ3.rain",
            "polygon-link-dca-univ3.sell.deviation.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        // ArbOrderTaker 'arb'
        checkStrategyCalculationsArbOrder(strategy);

    }

    function testGridCooldown() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonLinkIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            getEncodedBuyLinkRoute(address(ARB_INSTANCE)),
            0,
            0,
            0,
            10000e6,
            0,
            0,
            "strategies/dca-oracle-polygon-univ3.rain",
            "polygon-link-dca-univ3.buy.deviation.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

        // Check cooldown
        {
            vm.expectRevert("cooldown");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
        {
            vm.warp(block.timestamp + 14399);
            vm.expectRevert("cooldown");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
        // Cooldown succeeds
        {
            vm.warp(block.timestamp + 1);
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }


    }
    
    function testPartialTrade() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonLinkIo();

        uint256 expectedRatio = 14018452504312447172;
        uint256 expectedAmountOutputMax = 1085303707401124384;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyLinkRoute(address(ARB_INSTANCE)),
            getEncodedSellLinkRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            10000e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/dca-oracle-polygon-univ3.rain",
            "polygon-link-dca-univ3.sell.deviation.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

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
        returns (uint256 inputTokenBounty, uint256 outputTokenBounty)
    {   
        // Array of length 2 to store the input and ouput token bounties.
        uint256[] memory bounties = new uint256[](2);

        // Count the number of bounties found.
        uint256 bountyCount = 0;
        for (uint256 j = 0; j < entries.length; j++) { 
            if (
                entries[j].topics[0] == keccak256("Transfer(address,address,uint256)") && 
                address(ARB_INSTANCE) == abi.decode(abi.encodePacked(entries[j].topics[1]), (address)) &&
                address(APPROVED_EOA) == abi.decode(abi.encodePacked(entries[j].topics[2]), (address))
            ) {
                bounties[bountyCount] = abi.decode(entries[j].data, (uint256));
                bountyCount++;
            }   
        }
        return (bounties[0], bounties[1]);
    } 


    function getEncodedBuyLinkRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"022791Bca1f2de4661ED88A30C99A7a9449Aa8417401ffff0122177148e681A6ca5242c9888Ace170EE7eC47BD01";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellLinkRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"0253E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad3901ffff013c92bd9596E6aca8cfa29ec733ebe0c189bec1F301E7eb31f23A5BefEEFf76dbD2ED6AdC822568a5d201c2132D05D31c914a87C6611C10748AEb04B58e8F01ffff018CFaab34f5159abf9C35587AC40d09a05dC9476500";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

}