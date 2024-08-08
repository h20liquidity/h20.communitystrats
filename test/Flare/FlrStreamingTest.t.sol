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
import {StrategyTests, IRouteProcessor, LibStrategyDeployment, LibComposeOrders,IInterpreterV3,LibNamespace,FullyQualifiedNamespace,StateNamespace} from "h20.test-std/StrategyTests.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "h20.test-std/lib/LibProcessStream.sol";
uint256 constant VAULT_ID = uint256(keccak256("vault"));


/// @dev https://flarescan.com/token/0x1D80c49BbBCd1C0911346656B529DF9E5c2F783d
IERC20 constant FLARE_WFLR= IERC20(0x1D80c49BbBCd1C0911346656B529DF9E5c2F783d); 

/// @dev https://flarescan.com/address/0xFbDa5F676cB37624f28265A144A48B0d6e87d3b6
IERC20 constant FLARE_USDC = IERC20(0xFbDa5F676cB37624f28265A144A48B0d6e87d3b6);

function flareWflrIo() pure returns (IO memory) {
    return IO(address(FLARE_WFLR), 18, VAULT_ID);
}

function flareUsdcIo() pure returns (IO memory) {
    return IO(address(FLARE_USDC), 6, VAULT_ID);
} 

contract FlrStreamingTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 28047494;
    
    function selectFork() internal {
        uint256 fork = vm.createFork(vm.envString("RPC_URL_FLARE"));
        vm.selectFork(fork);
        vm.rollFork(FORK_BLOCK_NUMBER);
    }

    function setUp() public {
        selectFork();
        
        iParser = IParserV2(0xEBe394cff4980992B826Ec70ef0a9ec8b5D4C640);
        iStore = IInterpreterStoreV2(0xd8Bb6094fCB839bca8c12Ec53Bb2Cd7C012C8E87); 
        iInterpreter = IInterpreterV3(0x199E7891715B48b4fb093885de7Ba724Bfc39183); 
        iExpressionDeployer = IExpressionDeployerV3(0xEBe394cff4980992B826Ec70ef0a9ec8b5D4C640);

        iOrderBook = IOrderBookV4(0x582d9e838FE6cD9F8147C66A8f56A3FBE513a6A2);
        iArbInstance = IOrderBookV4ArbOrderTaker(0xC1A14cE2fd58A3A2f99deCb8eDd866204eE07f8D);
        iRouteProcessor = IRouteProcessor(address(0x4Aa9AEf59C7B63CD5C4B2eDE81F65A4225a99d9d));
         
        EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        ORDER_OWNER = address(0x5e01e44aE1969e16B9160d903B6F2aa991a37B21); 
    }

    function testBuyFlrStream() public {

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = flareWflrIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = flareUsdcIo();

        uint256 expectedRatio = 61.628395061728395059e18;
        uint256 expectedAmount = 4999999999999999920;

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            "",
            getEncodedBuyWflrRoute(),
            0,
            0,
            0,
            100000e18,
            expectedRatio,
            expectedAmount,
            "strategies/flare/wflr-streaming-dca.rain",
            "streaming-dca.buy-wflr.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );
        
        OrderV3 memory order = addOrderDepositOutputTokens(strategy);

        vm.warp(block.timestamp + 3600);
        
        {
            vm.recordLogs();

            takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);

            Vm.Log[] memory entries = vm.getRecordedLogs();
            (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);

            assertEq(strategyRatio, strategy.expectedRatio);
            assertEq(strategyAmount, strategy.expectedAmount);
        }
    }

    function getEncodedBuyWflrRoute() internal pure returns (bytes memory) {
        bytes memory BUY_WFLR_ROUTE =
            hex"02FbDa5F676cB37624f28265A144A48B0d6e87d3b601ffff00B1eC7ef55fa2E84eb6fF9FF0fa1e33387f892f6800C1A14cE2fd58A3A2f99deCb8eDd866204eE07f8D000bb8";
            
        return abi.encode(BUY_WFLR_ROUTE);
    }
}