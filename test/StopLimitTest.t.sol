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

contract StopLimitTest is StrategyTests { 

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 17307588;
    
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

    function testEnsureStopLimitSell() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            10000e6,
            10000e18,
            0,
            0,
            "strategies/wlth/wlth-stop-limit.rain",
            "stop-limit-order.sell.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // Current Price is not below the market price.
        {
            vm.expectRevert("Stop price.");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // When current price goes below the market price the order suceeds.
        {
            moveExternalPrice(
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.inputVaults[strategy.inputTokenIndex].token,
                200000e18,
                strategy.takerRoute
            );
            
            vm.recordLogs();
            // `arb()` called
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, 0.02e18);
            assertEq(strategyAmount, 50e18);
        
            vm.expectRevert("Max order count");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
             
        }
    }

    function testEnsureStopLimitBuy() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            200000e18,
            10000e6,
            0,
            0,
            "strategies/wlth/wlth-stop-limit.rain",
            "stop-limit-order.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // Current Price is not above the market price.
        {
            vm.expectRevert("Stop price.");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
        }

        {
            vm.recordLogs();
            // `arb()` called
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, 46e18);
            assertEq(strategyAmount, 1e18);
    
            vm.expectRevert("Max order count");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        } 
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


