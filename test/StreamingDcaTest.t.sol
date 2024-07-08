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
//1719907190
//9999999999

/// @dev https://polygonscan.com/address/0x6ab4E20f36ca48B61ECd66c0450fDf665Fa130be
IERC20 constant POLYGON_DOLZ = IERC20(0x6ab4E20f36ca48B61ECd66c0450fDf665Fa130be); 

/// @dev https://polygonscan.com/address/0xc2132D05D31c914a87C6611C10748AEb04B58e8F
IERC20 constant POLYGON_USDT = IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

function polygonDolzIo() pure returns (IO memory) {
    return IO(address(POLYGON_DOLZ), 18, VAULT_ID);
}

function polygonUsdtIo() pure returns (IO memory) {
    return IO(address(POLYGON_USDT), 6, VAULT_ID);
}

contract DcaOracleUniv3Test is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 58860597;
   
    
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

    function testStreamingDcaSell() public {
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdtIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonDolzIo();

        uint256 expectedIoRatio = 0.009832079999999999e18;
        uint256 expectedOutputMax = 8333333333333333400;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyDolzRoute(address(ARB_INSTANCE)),
            getEncodedSellDolzRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            100000e18,
            expectedIoRatio,
            expectedOutputMax,
            "strategies/dca-streaming.rain",
            "streaming-dca.sell-dolz.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        vm.warp(block.timestamp + 300);

        // ArbOrderTaker 'arb'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function testStreamingDcaBuy() public {
        
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonDolzIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonUsdtIo();

        uint256 expectedIoRatio = 87.611397079769799030e18;
        uint256 expectedOutputMax = 3e18;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedSellDolzRoute(address(ARB_INSTANCE)),
            getEncodedBuyDolzRoute(address(ARB_INSTANCE)),
            0,
            0,
            1000e18,
            100000e6,
            expectedIoRatio,
            expectedOutputMax,
            "strategies/dca-streaming.rain",
            "streaming-dca.buy-dolz.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        vm.warp(block.timestamp + 300);

        // ArbOrderTaker 'arb'
        checkStrategyCalculationsArbOrder(strategy);
    }

    function testStreamingDcaMinRatio() public {
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdtIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonDolzIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyDolzRoute(address(ARB_INSTANCE)),
            getEncodedSellDolzRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            100000e18,
            0,
            0,
            "strategies/dca-streaming.rain",
            "streaming-dca.sell-dolz.test",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy);

        vm.warp(block.timestamp + 300);

        vm.expectRevert("min ratio");
        takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
    }

    function testBountyAuction() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdtIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonDolzIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyDolzRoute(address(ARB_INSTANCE)),
            getEncodedSellDolzRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            100000e18,
            0,
            0,
            "strategies/dca-streaming.rain",
            "streaming-dca.sell-dolz.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        OrderV2 memory order = addOrderDepositOutputTokens(strategy); 

        // Auction starts
        vm.warp(block.timestamp + 300);
        {
            vm.recordLogs();
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 inputTokenBounty,) = getBounty(entries);
            
            // Assert greater than min bounty.
            assertGe(inputTokenBounty, 0.012e6);
        }

        // Auction ends.
        vm.warp(block.timestamp + 1800);
        {
            vm.recordLogs();
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 inputTokenBounty,) = getBounty(entries);

            // Assert greater than max bounty
            assertGe(inputTokenBounty, 0.3e6);
        }

        // Bounty amount remains same after the auction ends.
        vm.warp(block.timestamp + 1800);
        {
            vm.recordLogs();
            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 inputTokenBounty,) = getBounty(entries);

            // Assert greater than max bounty
            assertGe(inputTokenBounty, 0.3e6);
        } 
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

    function getEncodedBuyDolzRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02c2132D05D31c914a87C6611C10748AEb04B58e8F01ffff01C56DDB5C93B8E92B9409DCE43a9169aa643495b800";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedSellDolzRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"026ab4E20f36ca48B61ECd66c0450fDf665Fa130be01ffff01C56DDB5C93B8E92B9409DCE43a9169aa643495b801";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

}