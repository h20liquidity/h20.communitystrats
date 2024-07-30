// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;
import {console2, Test} from "forge-std/Test.sol";

import {
    IOrderBookV3,
    IO
} from "rain.orderbook.interface/interface/IOrderBookV3.sol";
import {
    IOrderBookV4,
    OrderV3,
    OrderConfigV3,
    TakeOrderConfigV3,
    TakeOrdersConfigV3,
    ActionV1
} from "rain.orderbook.interface/interface/unstable/IOrderBookV4.sol"; 
import {IParserV2} from "rain.interpreter.interface/interface/unstable/IParserV2.sol";
import {IOrderBookV4ArbOrderTaker} from "rain.orderbook.interface/interface/unstable/IOrderBookV4ArbOrderTaker.sol";
import {IExpressionDeployerV3} from "rain.interpreter.interface/interface/IExpressionDeployerV3.sol";
import {IInterpreterV3} from "rain.interpreter.interface/interface/unstable/IInterpreterV3.sol";
import {IInterpreterStoreV2} from "rain.interpreter.interface/interface/IInterpreterStoreV2.sol";
import {StrategyTests, IRouteProcessor, LibStrategyDeployment, LibComposeOrders,IInterpreterV3} from "h20.test-std/StrategyTests.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "h20.test-std/lib/LibProcessStream.sol";
uint256 constant VAULT_ID = uint256(keccak256("vault"));


/// @dev https://lineascan.build/address/0xe5d7c2a44ffddf6b295a15c148167daaaf5cf34f
IERC20 constant LINEA_WETH= IERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f); 

/// @dev https://lineascan.build/address/0x176211869cA2b568f2A7D4EE941E073a821EE1ff
IERC20 constant LINEA_USDC = IERC20(0x176211869cA2b568f2A7D4EE941E073a821EE1ff);

function lineaWethIo() pure returns (IO memory) {
    return IO(address(LINEA_WETH), 18, VAULT_ID);
}

function lineaUsdcIo() pure returns (IO memory) {
    return IO(address(LINEA_USDC), 6, VAULT_ID);
} 

contract LineaLimitOrderTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 7440168;
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_LINEA"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function setUp() public {
        selectFork();
        
        iParser = IParserV2(0xe54FB432e1bFECDaD15b901206061336EE1d60EA);
        iStore = IInterpreterStoreV2(0xE5b0006A16158AC392166A72d8A37CfD3a1ed682); 
        iInterpreter = IInterpreterV3(0x6D2148BF31482BB789B17b030bb924122f74607a); 
        iExpressionDeployer = IExpressionDeployerV3(0xe54FB432e1bFECDaD15b901206061336EE1d60EA); 
        iOrderBook = IOrderBookV4(0xF97DE1c2d864d90851aDBcbEe0A38260440B8D90);
        iArbInstance = IOrderBookV4ArbOrderTaker(0x6EAE39ea6c38207C337b3a083c33d7D5700904bc);
        iRouteProcessor = IRouteProcessor(address(0x46B3fDF7b5CDe91Ac049936bF0bDb12c5d22202e)); 

        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x5e01e44aE1969e16B9160d903B6F2aa991a37B21); 
    }

    function testLineaBuyRouteUniswapV3() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = lineaWethIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = lineaUsdcIo();

        uint256 expectedRatio = 0.00025e18;
        uint256 expectedAmount = 10e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            1e18,
            10000e6,
            expectedRatio,
            expectedAmount,
            "strategies/trireme/linea-limit-order.rain",
            "limit-orders.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        {
            vm.recordLogs();

            takeArbOrder(order, getLineaBuyWethUniV3Route(), strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }
        
    }

    function testLineaBuyRouteLynexV2() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = lineaWethIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = lineaUsdcIo();

        uint256 expectedRatio = 0.00025e18;
        uint256 expectedAmount = 10e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            1e18,
            10000e6,
            expectedRatio,
            expectedAmount,
            "strategies/trireme/linea-limit-order.rain",
            "limit-orders.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        {
            vm.recordLogs();

            takeArbOrder(order, getLineaBuyWethLynexV2Route(), strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }

    }

    function testLineaBuyRouteLynexV1() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = lineaWethIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = lineaUsdcIo();

        uint256 expectedRatio = 0.00025e18;
        uint256 expectedAmount = 10e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            "",
            0,
            0,
            1e18,
            10000e6,
            expectedRatio,
            expectedAmount,
            "strategies/trireme/linea-limit-order.rain",
            "limit-orders.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        {
            vm.recordLogs();

            takeArbOrder(order, getLineaBuyWethLynexV1Route(), strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }

    }

    function getLineaBuyWethUniV3Route() internal pure returns (bytes memory) {
        bytes memory BUY_USDC_ROUTE =
            hex"02176211869cA2b568f2A7D4EE941E073a821EE1ff01ffff01416e3B622867aa4af98FcF0E0b871a47A80A7d7E016EAE39ea6c38207C337b3a083c33d7D5700904bc";
            
        return abi.encode(BUY_USDC_ROUTE);
    }

    function getLineaBuyWethLynexV2Route() internal pure returns (bytes memory) {
        bytes memory BUY_USDC_ROUTE =
            hex"02176211869cA2b568f2A7D4EE941E073a821EE1ff01ffff013Cb104f044dB23d6513F2A6100a1997Fa5e3F587016EAE39ea6c38207C337b3a083c33d7D5700904bc";
            
        return abi.encode(BUY_USDC_ROUTE);
    }

    function getLineaBuyWethLynexV1Route() internal pure returns (bytes memory) {
        bytes memory BUY_USDC_ROUTE =
            hex"02176211869cA2b568f2A7D4EE941E073a821EE1ff01ffff006FB44889a9aA69F7290258D3716BfFcB33CdE184016EAE39ea6c38207C337b3a083c33d7D5700904bc000bb8";
            
        return abi.encode(BUY_USDC_ROUTE);
    }
 
} 

