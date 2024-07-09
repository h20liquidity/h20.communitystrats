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

/// @dev https://polygonscan.com/address/0xc2132D05D31c914a87C6611C10748AEb04B58e8F
IERC20 constant POLYGON_USDT = IERC20(0xc2132D05D31c914a87C6611C10748AEb04B58e8F);

/// @dev https://polygonscan.com/address/0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
IERC20 constant POLYGON_WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);

function polygonUsdtIo() pure returns (IO memory) {
    return IO(address(POLYGON_USDT), 6, VAULT_ID);
}

function polygonWmaticIo() pure returns (IO memory) {
    return IO(address(POLYGON_WMATIC), 18, VAULT_ID);
}

contract PolygonFixedGridDecimal is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 59148516;
    string constant fxA3A_TRANCHE_PATH = "strategies/fxA3A/3a-0003-tranche-recharge.rain";
    string constant fxA3A_POLYGON_ORACLE_DCA = "strategies/fxA3A/3a-polygon-oracle-dca-usdc.rain";
    
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

    function testConsolidateMA() public {
        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = polygonUsdtIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = polygonWmaticIo();

        uint256 expectedRatio = 0.501038265021202985e18;
        uint256 expectedAmount = 50e18;

        {
            LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
                getEncodedUsdtWmaticRoute(address(ARB_INSTANCE)),
                getEncodedWmaticUsdtRoute(address(ARB_INSTANCE)),
                0,
                0,
                2000e6,
                100000e18,
                expectedRatio,
                expectedAmount,
                "strategies/BidAskSpreadMA/consolidating-MA-buyside-wmaticuusdt.rain",
                "consolidated-ma.wmatic.prod",
                "./lib/h20.test-std/lib/rain.orderbook",
                "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
                inputVaults,
                outputVaults
            );

            OrderV2 memory order = addOrderDepositOutputTokens(strategy);
            moveExternalPrice(
                    strategy.inputVaults[strategy.inputTokenIndex].token,
                    strategy.outputVaults[strategy.outputTokenIndex].token,
                    strategy.makerAmount,
                    strategy.makerRoute
            );
            {
                vm.recordLogs();
                takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
                Vm.Log[] memory entries = vm.getRecordedLogs();
                (uint256 strategyAmount, uint256 strategyRatio) = getCalculationContext(entries);
                assertEq(strategyRatio, strategy.expectedRatio);
                assertEq(strategyAmount, strategy.expectedAmount);
            }
        }
        {
            LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
                getEncodedWmaticUsdtRoute(address(ARB_INSTANCE)),
                getEncodedUsdtWmaticRoute(address(ARB_INSTANCE)),
                0,
                0,
                4000e18,
                1000e6,
                expectedRatio,
                expectedAmount,
                "strategies/BidAskSpreadMA/consolidating-MA-buyside-sellback-wmaticuusdt.rain",
                "consolidated-ma.wmatic.prod",
                "./lib/h20.test-std/lib/rain.orderbook",
                "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
                outputVaults,
                inputVaults
            );

            OrderV2 memory order = addOrderDepositOutputTokens(strategy);

            moveExternalPrice(
                    strategy.inputVaults[strategy.inputTokenIndex].token,
                    strategy.outputVaults[strategy.outputTokenIndex].token,
                    strategy.makerAmount,
                    strategy.makerRoute
            );

            {
                takeArbOrder(order, strategy.takerRoute, strategy.inputTokenIndex, strategy.outputTokenIndex);
                assertEq(strategyAmount, expectedRatio*expectedAmount);
            }

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

    function getEncodedWmaticUsdtRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"020d500B1d8E8eF31E21C99d1Db9A6444d3ADf127001ffff019B08288C3Be4F62bbf8d1C20Ac9C5e6f9467d8B701";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }

    function getEncodedUsdtWmaticRoute(address toAddress) internal pure returns (bytes memory) {
        bytes memory ROUTE_PRELUDE =
            hex"02c2132D05D31c914a87C6611C10748AEb04B58e8F01ffff019B08288C3Be4F62bbf8d1C20Ac9C5e6f9467d8B700";
            
        return abi.encode(bytes.concat(ROUTE_PRELUDE, abi.encodePacked(address(toAddress))));
    }
 

}