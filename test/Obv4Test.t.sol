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
import {IOrderBookV4ArbOrderTaker} from "test/interface/IOrderBookV4ArbOrderTaker.sol";
import "test/interface/IOrderBookV4.sol";
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

contract WlthGridTradingTest is StrategyTests {

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 16952956;
    
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
        ORDER_OWNER = address(0x5e01e44aE1969e16B9160d903B6F2aa991a37B21); 

        // EXTERNAL_EOA = address(0x654FEf5Fb8A1C91ad47Ba192F7AA81dd3C821427);
        // APPROVED_EOA = address(0x669845c29D9B1A64FFF66a55aA13EB4adB889a88);
        // ORDER_OWNER = address(0x19f95a84aa1C48A2c6a7B2d5de164331c86D030C);
    } 

    function testObv4() public { 

        console2.log("ob4");
        IOrderBookV4 obv4 = IOrderBookV4(0xA2f56F8F74B7d04d61f281BE6576b6155581dcBA);
        IInterpreterV3 iv3 = IInterpreterV3(0x379b966DC6B117dD47b5Fc5308534256a4Ab1BCC);
        IOrderBookV4ArbOrderTaker arb2Contract = IOrderBookV4ArbOrderTaker(0xF97A86C2Cb3e42f89AC5f5AA020E5c3505015a88); 

        IO[] memory inputVaults = new IO[](1);
        inputVaults[0] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](1);
        outputVaults[0] = baseWlthIo();

        LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
            getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
            getEncodedSellWlthRoute(address(ARB_INSTANCE)),
            0,
            0,
            1e6,
            10000e18,
            0,
            0,
            "strategies/wlth/wlth-limit-order-single.rain",
            "limit-orders.sell.prod",
            "./lib/h20.test-std/lib/rain.orderbook",
            "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
            inputVaults,
            outputVaults
        );

        (bytes memory bytecode, uint256[] memory constants) = PARSER.parse(
            LibComposeOrders.getComposedOrder(
                vm, strategy.strategyFile, strategy.strategyScenario, strategy.buildPath, strategy.manifestPath
            )
        );

        EvaluableV3 memory evaluableV3Config = EvaluableV3(iv3, STORE, bytecode);

        OrderConfigV3 memory orderV3Config = OrderConfigV3(evaluableV3Config, inputVaults, outputVaults, "", "", "");

        OrderV3 memory orderV3;
        {   
            vm.startPrank(ORDER_OWNER);
            vm.recordLogs();
            (bool stateChanged) = obv4.addOrder2(orderV3Config,new ActionV1[](0)); 
            vm.stopPrank();
            Vm.Log[] memory entries = vm.getRecordedLogs();
            (,, orderV3) = abi.decode(entries[0].data, (address, bytes32, OrderV3));
            console2.log(orderV3.owner);
        }
        
        {
            vm.startPrank(APPROVED_EOA); 

            EvaluableV3 memory arbEvaluableV3Config = EvaluableV3(address(0x0000000000000000000000000000000000000000), address(0x0000000000000000000000000000000000000000), "");
            TakeOrderConfigV3[] memory innerConfigs = new TakeOrderConfigV3[](1); 
            innerConfigs[0] = TakeOrderConfigV3(orderV3, 0, 0, new SignedContextV1[](0)); 

            TakeOrdersConfigV3 memory takeOrdersConfig =
                TakeOrdersConfigV3(0, type(uint256).max, type(uint256).max, innerConfigs, getEncodedRpv4WlthUsdc());
            arb2Contract.arb2(takeOrdersConfig, 0, arbEvaluableV3Config);
            vm.stopPrank();
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

    function getEncodedRpv4WlthUsdc() internal pure returns (bytes memory){
        bytes memory WLTH_TO_USDC = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000420299b2b1a2adb02b38222adcd057783d7e5d1fcc7d01ffff011536ee1506e24e5a36be99c73136cd82907a902e00f97a86c2cb3e42f89ac5f5aa020e5c3505015a88000000000000000000000000000000000000000000000000000000000000";
    }


}