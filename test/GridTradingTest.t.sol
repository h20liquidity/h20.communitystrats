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


IERC20 constant RED_TOKEN = IERC20(0xE38D92733203E6f93C634304b777490e67Dc4Bdf);
IERC20 constant BLUE_TOKEN = IERC20(0x40D44abeC30288BFcd400200BA65FBD05daA5321);

function flareRedIo() pure returns (IO memory) {
    return IO(address(RED_TOKEN), 18, VAULT_ID);
}

function flareBlueIo() pure returns (IO memory) {
    return IO(address(BLUE_TOKEN), 18, VAULT_ID);
}

contract GridTradingTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 26478013;
   
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_FLARE"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function getNamespace() public view returns (FullyQualifiedNamespace) {
        return LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this));
    }

    function setUp() public {
        selectFork();
        
        PARSER = IParserV1(0xA073E75E39C402d2AFFb48E5e8EC18169daeC31D);
        ORDERBOOK = IOrderBookV3(0x07701e3BcE4248EFDFc7D31392a43c8b82a7A260);
        ARB_INSTANCE = IOrderBookV3ArbOrderTaker(0xF9323B7d23c655122Fb0272D989b83E105cBcf9d);
        EXPRESSION_DEPLOYER = IExpressionDeployerV3(0xEBe394cff4980992B826Ec70ef0a9ec8b5D4C640);
        ROUTE_PROCESSOR = IRouteProcessor(address(0x0bB72B4C7c0d47b2CaED07c804D9243C1B8a0728)); 
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C);

    }

    function testGridTradingBuy() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = flareRedIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = flareBlueIo();

        uint256 expectedRatio = 1e18;
        uint256 expectedAmountOutputMax = 1e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedRedToBlueRoute(address(ARB_INSTANCE)),
            getEncodedBlueToRedRoute(address(ARB_INSTANCE)),
            0,
            0,
            10e18,
            1e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/grid-trading.rain",
            "flare-red-blue.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function testGridTradingSell() public {
        // Input vaults
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = flareBlueIo();

        // Output vaults
        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = flareRedIo();

        uint256 expectedRatio = 1e18;
        uint256 expectedAmountOutputMax = 1e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBlueToRedRoute(address(ARB_INSTANCE)),
            getEncodedRedToBlueRoute(address(ARB_INSTANCE)),
            0,
            0,
            10000e18,
            10000e18,
            expectedRatio,
            expectedAmountOutputMax,
            "strategies/grid-trading.rain",
            "flare-red-blue.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );
        
        // OrderBook 'takeOrder'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function getEncodedRedToBlueRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory RED_TO_BLUE_ROUTE_PRELUDE =
            hex"02"
            hex"E38D92733203E6f93C634304b777490e67Dc4Bdf"
            hex"01"
            hex"ffff"
            hex"00"
            hex"03585a45Af10963838e435601487516F97B18aF7"
            hex"00";

        return abi.encode(bytes.concat(RED_TO_BLUE_ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    // Inheriting contract defines the route for the strategy.
    function getEncodedBlueToRedRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory BLUE_TO_RED_ROUTE_PRELUDE =
            hex"02"
            hex"40D44abeC30288BFcd400200BA65FBD05daA5321"
            hex"01"
            hex"ffff"
            hex"00"
            hex"03585a45Af10963838e435601487516F97B18aF7"
            hex"01";

        return abi.encode(bytes.concat(BLUE_TO_RED_ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    } 



}
