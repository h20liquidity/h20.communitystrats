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

/// @dev https://polygonscan.com/address/0xAC0F66379A6d7801D7726d5a943356A172549Adb
IERC20 constant POLYGON_GEOD = IERC20(0xAC0F66379A6d7801D7726d5a943356A172549Adb); 

/// @dev https://polygonscan.com/address/0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
IERC20 constant POLYGON_USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);


function polygonGeodIo() pure returns (IO memory) {
    return IO(address(POLYGON_GEOD), 18, VAULT_ID);
}

function polygonUsdcIo() pure returns (IO memory) {
    return IO(address(POLYGON_USDC), 6, VAULT_ID);
}
contract DcaOracleUniv3Test is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 58689136;

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

    function testPolygonMeanReversal() public {
        IO[] memory inputVaults = new IO[](2);
        inputVaults[0] = polygonUsdcIo();
        inputVaults[1] = polygonGeodIo();

        IO[] memory outputVaults = new IO[](2);
        outputVaults[0] = polygonUsdcIo();
        outputVaults[1] = polygonGeodIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellGeodRoute(address(ARB_INSTANCE)),
            getEncodedBuyGeodRoute(address(ARB_INSTANCE)),
            1,
            0,
            1000e18,
            1000e6,
            0,
            0,
            "strategies/polygon-mean-reversal.rain",
            "polygon-mean.geod.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        {
            vm.recordLogs();
            takeArbOrder(order, strategy.takerRoute, 1, 0);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyAmount, 50e18);
            assertEq(strategyRatio, 5.633354682081213875e18);
        }
        
    }

    function testPartialTrade() public {

        IO[] memory inputVaults = new IO[](2);
        inputVaults[0] = polygonUsdcIo();
        inputVaults[1] = polygonGeodIo();

        IO[] memory outputVaults = new IO[](2);
        outputVaults[0] = polygonUsdcIo();
        outputVaults[1] = polygonGeodIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellGeodRoute(address(ARB_INSTANCE)),
            getEncodedBuyGeodRoute(address(ARB_INSTANCE)),
            1,
            0,
            1000e18,
            1000e6,
            0,
            0,
            "strategies/polygon-mean-reversal.rain",
            "polygon-mean.geod.prod",
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
            context[3][0] = uint256(uint160(address(POLYGON_GEOD)));
            context[4][0] = uint256(uint160(address(POLYGON_USDC)));

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

        // Division to scale from 18 decimal fp to 6 decimal fp
        orderOuputMax = orderOuputMax / 1e12; 

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
            TakeOrdersConfigV2(0, orderOuputMax - 1, type(uint256).max, innerConfigs, "");
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

    function getEncodedBuyGeodRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"022791Bca1f2de4661ED88A30C99A7a9449Aa8417401ffff01B372b5AbDb7c2ab8aD9E614BE9835A42d000915301";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellGeodRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02AC0F66379A6d7801D7726d5a943356A172549Adb01ffff01B372b5AbDb7c2ab8aD9E614BE9835A42d000915300";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

}