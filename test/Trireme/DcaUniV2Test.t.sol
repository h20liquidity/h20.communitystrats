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
    ActionV1
} from "rain.orderbook.interface/interface/IOrderBookV4.sol"; 
import {IParserV2} from "rain.interpreter.interface/interface/IParserV2.sol";
import {IOrderBookV4ArbOrderTaker} from "rain.orderbook.interface/interface/IOrderBookV4ArbOrderTaker.sol";
import {IExpressionDeployerV3} from "rain.interpreter.interface/interface/deprecated/IExpressionDeployerV3.sol";
import {IInterpreterV3} from "rain.interpreter.interface/interface/IInterpreterV3.sol";
import {IInterpreterStoreV2} from "rain.interpreter.interface/interface/IInterpreterStoreV2.sol";
import {StrategyTests, IRouteProcessor, LibStrategyDeployment, LibComposeOrders,IInterpreterV3} from "h20.test-std/StrategyTests.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "h20.test-std/lib/LibProcessStream.sol";
uint256 constant VAULT_ID = uint256(keccak256("vault"));


/// @dev https://polygonscan.com/address/0xE1b3eb06806601828976e491914e3De18B5d6b28
IERC20 constant POLYGON_ZERC= IERC20(0xE1b3eb06806601828976e491914e3De18B5d6b28); 

/// @dev https://polygonscan.com/address/0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
IERC20 constant POLYGON_USDC = IERC20(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);

function polygonZercIo() pure returns (IO memory) {
    return IO(address(POLYGON_ZERC), 18, VAULT_ID);
}

function polygonUsdcIo() pure returns (IO memory) {
    return IO(address(POLYGON_USDC), 6, VAULT_ID);
} 

contract DcaUniV2Test is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 59867552;
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_POLYGON"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function setUp() public {
        selectFork();
        
        iParser = IParserV2(0xF14E09601A47552De6aBd3A0B165607FaFd2B5Ba);
        iStore = IInterpreterStoreV2(0xde38AD4b13D5258a5653E530EcDF0cA71B4E8a51); 
        iInterpreter = IInterpreterV3(0x6352593F4018C99dF731DE789e2a147C7FB29370); 
        iExpressionDeployer = IExpressionDeployerV3(0xF14E09601A47552De6aBd3A0B165607FaFd2B5Ba); 
        iOrderBook = IOrderBookV4(0x2f209e5b67A33B8fE96E28f24628dF6Da301c8eB);
        iArbInstance = IOrderBookV4ArbOrderTaker(0x582d9e838FE6cD9F8147C66A8f56A3FBE513a6A2);
        iRouteProcessor = IRouteProcessor(address(0x46B3fDF7b5CDe91Ac049936bF0bDb12c5d22202e)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x5e01e44aE1969e16B9160d903B6F2aa991a37B21); 
    }

    function testDcaBuyUniV2() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonZercIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        uint256 expectedRatio = 7.546679062155744054e18;
        uint256 expectedAmount = 1.448940071037488020e18;

        LibStrategyDeployment.StrategyDeploymentV3 memory strategy = LibStrategyDeployment.StrategyDeploymentV3(
            getEncodedSellZercRoute(),
            getEncodedBuyZercRoute(),
            0,
            0,
            1e18,
            10000e6,
            expectedRatio,
            expectedAmount,
            "strategies/trireme/dca-oracle-univ2.rain",
            "polygon-h20liquidity-oracle-dca.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new ActionV1[](0)
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        {
            vm.recordLogs();

            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }

    }

    function testDcaSellUniV2() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonZercIo();

        uint256 expectedRatio = 0.107731681330498142e18;
        uint256 expectedAmount = 11.591520568299904160e18;

        LibStrategyDeployment.StrategyDeploymentV3 memory strategy = LibStrategyDeployment.StrategyDeploymentV3(
            getEncodedBuyZercRoute(),
            getEncodedSellZercRoute(),
            0,
            0,
            1e6,
            100000e18,
            expectedRatio,
            expectedAmount,
            "strategies/trireme/dca-oracle-univ2.rain",
            "polygon-h20liquidity-oracle-dca.sell.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new ActionV1[](0)
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        {
            vm.recordLogs();

            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }
    }

    function testDcaUniV2CardanoCheck() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonZercIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        LibStrategyDeployment.StrategyDeploymentV3 memory strategy = LibStrategyDeployment.StrategyDeploymentV3(
            getEncodedSellZercRoute(),
            getEncodedBuyZercRoute(),
            0,
            0,
            1e18,
            10000e6,
            0,
            0,
            "strategies/trireme/dca-oracle-univ2.rain",
            "polygon-h20liquidity-oracle-dca.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new ActionV1[](0)
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);


        // Cardano check fails
        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
            vm.expectRevert("Price change.");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // Cardano check succeeds
        {   
            vm.warp(block.timestamp + 1);
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);   
        }

    }

    function testDcaUniV2Cooldown() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonZercIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdcIo();

        LibStrategyDeployment.StrategyDeploymentV3 memory strategy = LibStrategyDeployment.StrategyDeploymentV3(
            getEncodedSellZercRoute(),
            getEncodedBuyZercRoute(),
            0,
            0,
            1e18,
            10000e6,
            0,
            0,
            "strategies/trireme/dca-oracle-univ2.rain",
            "polygon-h20liquidity-oracle-dca.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults,
            new ActionV1[](0)
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        // Bot takes order
        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        
        // Cooldown fails
        {   
           vm.expectRevert("cooldown");
           takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // Cooldown fails
        {   
           vm.warp(block.timestamp + 59);
           vm.expectRevert("cooldown");
           takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // Cooldown succeeds
        {   
           vm.warp(block.timestamp + 1);
           takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

    }

    function getEncodedBuyZercRoute() internal pure returns (bytes memory) {
        bytes memory BUY_ZERC_ROUTE =
            hex"023c499c542cEF5E3811e1192ce70d8cC03d5c335901ffff00514480cF3eD104B5c34A17A15859a190E38E97AF01582d9e838FE6cD9F8147C66A8f56A3FBE513a6A2000bb8";
            
        return abi.encode(BUY_ZERC_ROUTE);
    }

    function getEncodedSellZercRoute() internal pure returns (bytes memory) {
        bytes memory SELL_ZERC_ROUTE =
            hex"02E1b3eb06806601828976e491914e3De18B5d6b2801ffff00514480cF3eD104B5c34A17A15859a190E38E97AF00582d9e838FE6cD9F8147C66A8f56A3FBE513a6A2000bb8";
            
        return abi.encode(SELL_ZERC_ROUTE);
    } 


} 

