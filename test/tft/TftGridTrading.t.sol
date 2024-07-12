// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;
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

/// @dev https://bscscan.com/address/0x8f0FB159380176D324542b3a7933F0C2Fd0c2bbf
IERC20 constant TFT_TOKEN = IERC20(0x8f0FB159380176D324542b3a7933F0C2Fd0c2bbf);

/// @dev https://bscscan.com/address/0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
IERC20 constant BUSD_TOKEN = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);

function bscTftIo() pure returns (IO memory) {
    return IO(address(TFT_TOKEN), 7, VAULT_ID);
}

function bscBusdIo() pure returns (IO memory) {
    return IO(address(BUSD_TOKEN), 18, VAULT_ID);
}

contract ThreefoldStabiliseTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 40406023;

    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_BSC"));
        console2.log("RPC_URL_BSC : ", vm.envString("RPC_URL_BSC"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function getNamespace() public view returns (FullyQualifiedNamespace) {
        return LibNamespace.qualifyNamespace(StateNamespace.wrap(0), address(this));
    }

    function setUp() public {
        selectFork();
        INTERPRETER = IInterpreterV2(0x6E4b01603edBDa617002A077420E98C86595748E); 
        STORE = IInterpreterStoreV2(0xF836f2746B407136a5bCB515495949B1edB75184);  
        PARSER = IParserV1(0xb06202aA3Fe7d85171fB7aA5f17011d17E63f382);
        EXPRESSION_DEPLOYER = IExpressionDeployerV3(0x379b966DC6B117dD47b5Fc5308534256a4Ab1BCC);
        
        ORDERBOOK = IOrderBookV3(0xb1d6D10561D4e1792A7c6B336b0529e4bFb5Ea8F); 
        ARB_INSTANCE = IOrderBookV3ArbOrderTaker(0xaCD99A1BE78926b05De19237E2C35B2eDa0292B8);
        ROUTE_PROCESSOR = IRouteProcessor(address(0xd36990D74b947eC4Ad9f52Fe3D49d14AdDB51E44));
        
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C);
    }

    function testTftGridTradingBuy() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = bscTftIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = bscBusdIo();

        uint256 expectedRatio = 75e18;
        uint256 expectedMaxOutput = 5e18;


        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellTftRoute(address(ARB_INSTANCE)),
            getEncodedBuyTftRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e7,
            100000e18,
            expectedRatio,
            expectedMaxOutput,
            "strategies/tft/grid-trading.rain",
            "grid-trading.buy.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        ); 

        // OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        checkStrategyCalculationsArbOrder(strategy);

    }

    function testTftGridTradingSell() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = bscBusdIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = bscTftIo();

        uint256 expectedRatio = 0.01e18;
        uint256 expectedMaxOutput = 500e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyTftRoute(address(ARB_INSTANCE)),
            getEncodedSellTftRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e18,
            10000000e7,
            expectedRatio,
            expectedMaxOutput,
            "strategies/tft/grid-trading.rain",
            "grid-trading.sell.grid.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        ); 

        // OrderV2 memory order = addOrderDepositOutputTokens(strategy);
        checkStrategyCalculationsArbOrder(strategy);

    }

    function getEncodedBuyTftRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02"
            hex"e9e7CEA3DedcA5984780Bafc599bD69ADd087D56"
            hex"01"
            hex"ffff"
            hex"00"
            hex"4A2Dbaa979A3F4Cfb8004eA5743fAF159DD2665A"
            hex"00";
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellTftRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02"
            hex"8f0FB159380176D324542b3a7933F0C2Fd0c2bbf"
            hex"01"
            hex"ffff"
            hex"00"
            hex"4A2Dbaa979A3F4Cfb8004eA5743fAF159DD2665A"
            hex"01";
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }  


}