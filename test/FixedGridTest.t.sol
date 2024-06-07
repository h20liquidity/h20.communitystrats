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

string constant WLTH_FIXED_GRID = "strategies/wlth-006-100-dca.rain";
string constant WLTH_BUY_FIXED_GRID_PROD = "base-wlth-fixed-grid.buy.prod";
string constant WLTH_BUY_FIXED_GRID_TEST_TWAP = "base-wlth-fixed-grid.buy.test-twap";
string constant WLTH_SELL_FIXED_GRID_PROD = "base-wlth-fixed-grid.sell.prod";
string constant WLTH_SELL_FIXED_GRID_TEST_TWAP = "base-wlth-fixed-grid.sell.test-twap";

/// @dev https://basescan.org/address/0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D
IERC20 constant WLTH_TOKEN = IERC20(0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D); 

/// @dev https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
IERC20 constant USDC_TOKEN = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

/// @dev https://basescan.org/address/0x4200000000000000000000000000000000000006
IERC20 constant WETH_TOKEN = IERC20(0x4200000000000000000000000000000000000006);

/// @dev https://basescan.org/address/0x71DDE9436305D2085331AF4737ec6f1fe876Cf9f
IERC20 constant PAID_TOKEN = IERC20(0x71DDE9436305D2085331AF4737ec6f1fe876Cf9f);

function baseWlthIo() pure returns (IO memory) {
    return IO(address(WLTH_TOKEN), 18, VAULT_ID);
}

function basePaidIo() pure returns (IO memory) {
    return IO(address(PAID_TOKEN), 18, VAULT_ID);
}

function baseWethIo() pure returns (IO memory) {
    return IO(address(WETH_TOKEN), 18, VAULT_ID);
}

function baseUsdcIo() pure returns (IO memory) {
    return IO(address(USDC_TOKEN), 6, VAULT_ID);
}

contract FixedGridTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 15485600;
    
    address public BASE_USDC_POOL;

    
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
        
        PARSER = IParserV1(0x8853D126bC23A45B9f807739B6EA0B38eF569005);
        INTERPRETER = IInterpreterV2(0xF9bDedb1e8c32185E879E056eBA9F5aeC1839d60); 
        STORE = IInterpreterStoreV2(0xd19581a021f4704ad4eBfF68258e7A0a9DB1CD77); 
        ORDERBOOK = IOrderBookV3(0x2AeE87D75CD000583DAEC7A28db103B1c0c18b76);
        ARB_INSTANCE = IOrderBookV3ArbOrderTaker(0x199b22ce0c9fD88476cCaA2d2aB253Af38BAE3Ae);
        EXPRESSION_DEPLOYER = IExpressionDeployerV3(0xfca89cD12Ba1346b1ac570ed988AB43b812733fe); 
        ROUTE_PROCESSOR = IRouteProcessor(address(0x83eC81Ae54dD8dca17C3Dd4703141599090751D1)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C);

        BASE_USDC_POOL = address(0x1536EE1506e24e5A36Be99C73136cD82907A902E);

    }

    function testBuyPaidFixedGrid() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = basePaidIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        uint256 expectedRatio = 0;
        uint256 expectedAmountOutputMax = 1e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            getEncodedBuyPaidRoute(address(ARB_INSTANCE)),
            0,
            0,
            0,
            10000e6,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/paid-fixed-grid-buy.rain",
            "base-paid-fixed-grid.buy.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);    
    } 

    function testSellPaidFixedGrid() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = basePaidIo();

        uint256 expectedRatio = 0;
        uint256 expectedAmountOutputMax = 1e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            getEncodedSellPaidRoute(address(ARB_INSTANCE)),
            0,
            0,
            0,
            10000000e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/paid-fixed-grid-buy.rain",
            "base-paid-fixed-grid.sell.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex); 
    }

    function testCwGridArbSellHappyPath() public {
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        uint256 expectedRatio = 0;
        uint256 expectedAmountOutputMax = 1e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            getEncodedSellRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            0,
            0,
            10000e6,
            80000e18,
            expectedRatio,
            expectedAmountOutputMax,
            WLTH_FIXED_GRID,
            WLTH_SELL_FIXED_GRID_PROD,
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );
        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // `takeOrders()` called
        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
    }

    function testCwGridArbBuyHappyPath() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        uint256 expectedRatio = 0;
        uint256 expectedAmountOutputMax = 1e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            getEncodedBuyRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            0,
            0,
            8e18,
            10000e6,
            expectedRatio,
            expectedAmountOutputMax,
            WLTH_FIXED_GRID,
            WLTH_BUY_FIXED_GRID_PROD,
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // `takeOrders()` called
        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
    }

    function testCwGridCooldown() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            getEncodedBuyRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            0,
            0,
            80e18,
            10000e6,
            0,
            0,
            WLTH_FIXED_GRID,
            WLTH_BUY_FIXED_GRID_PROD,
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

    function testGridBand() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            getEncodedBuyRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            0,
            0,
            8000000000e18,
            1000000000e6,
            0,
            0,
            WLTH_FIXED_GRID,
            WLTH_BUY_FIXED_GRID_PROD,
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // Move the market outside the grid band
        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
            vm.expectRevert("grid band");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

        // Move the market outside the grid band
        {
            moveExternalPrice(
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.takerAmount,
                strategy.takerRoute
            );
            vm.expectRevert("grid band");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }

    } 

    function testGridUniV3BuyTwapCheck() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseWlthIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseUsdcIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            getEncodedBuyRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            0,
            0,
            100000e18,
            1000000e6,
            0,
            0,
            WLTH_FIXED_GRID,
            WLTH_BUY_FIXED_GRID_TEST_TWAP,
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // Price within twap threshold.
        {
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
            vm.warp(block.timestamp + 14400);
        }
        
        // Change the 30min twap price
        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
            vm.warp(block.timestamp + 1200);

            // Assert twap-check
            vm.expectRevert("twap check");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
    }

    function testGridUniV3SellTwapCheck() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            getEncodedSellRoute(BASE_USDC_POOL,address(ARB_INSTANCE)),
            0,
            0,
            10000e6,
            5000e18,
            0,
            0,
            WLTH_FIXED_GRID,
            WLTH_SELL_FIXED_GRID_TEST_TWAP,
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        // Price within twap threshold.
        {
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
            vm.warp(block.timestamp + 14400);
        }
        
        // Change the 30min twap price
        {
            moveExternalPrice(
                strategy.inputVaults[strategy.inputTokenIndex].token,
                strategy.outputVaults[strategy.outputTokenIndex].token,
                strategy.makerAmount,
                strategy.makerRoute
            );
            vm.warp(block.timestamp + 1200);
            // Assert twap-check
            vm.expectRevert("twap check");
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
        }
    }

    function getEncodedBuyRoute(address poolAddress, address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02"
            hex"833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" 
            hex"01"
            hex"ffff"
            hex"01";

        return abi.encode(
            bytes.concat(
                ROUTE_PRELUDE,
                abi.encodePacked(address(poolAddress)),
                hex"01",
                abi.encodePacked(address(toAddress))
            )
        );
    }

    function getEncodedSellRoute(address poolAddress, address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02"
            hex"99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D"
            hex"01"
            hex"ffff"
            hex"01";

        return abi.encode(
            bytes.concat(
                ROUTE_PRELUDE,
                abi.encodePacked(address(poolAddress)),
                hex"00",
                abi.encodePacked(address(toAddress))
            )
        );
    }

    function getEncodedBuyPaidRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02833589fCD6eDb6E08f4c7C32D4f71b54bdA0291301ffff00ab067c01C7F5734da168C699Ae9d23a4512c9FdB0083eC81Ae54dD8dca17C3Dd4703141599090751D101420000000000000000000000000000000000000601ffff013e170f4509A9CB5edC4FD98Ed0b461B78d7F31ea01";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellPaidRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"0271DDE9436305D2085331AF4737ec6f1fe876Cf9f01ffff013e170f4509A9CB5edC4FD98Ed0b461B78d7F31ea0088A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C0442000000000000000000000000000000000000060088A43bbDF9D098eEC7bCEda4e2494615dfD9bB9C01";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }
}