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

contract WlthLimitOrderMultipleTest is StrategyTests { 

    using SafeERC20 for IERC20;
    using Strings for address;

    uint256 constant FORK_BLOCK_NUMBER = 16913278;
    
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

    function testConsolidateMA() public {
        IO[] memory inputVaults = new IO[](2);
        inputVaults[0] = baseWlthIo();
        inputVaults[1] = baseUsdcIo();

        IO[] memory outputVaults = new IO[](2);
        outputVaults[0] = baseWlthIo();
        outputVaults[1] = baseUsdcIo();


        uint256 expectedRatio = 0.501038265021202985e18;
        uint256 expectedAmount = 50e18;

        {
            LibStrategyDeployment.StrategyDeployment memory strategy = LibStrategyDeployment.StrategyDeployment(
                getEncodedSellWlthRoute(address(ARB_INSTANCE)),
                getEncodedBuyWlthRoute(address(ARB_INSTANCE)),
                0,
                0,
                2000e6,
                100000e18,
                expectedRatio,
                expectedAmount,
                "strategies/wlth/wlth-bid-ask-ma-spread.rain",
                "bid-ask-ma-spread.wlth.prod",
                "./lib/h20.test-std/lib/rain.orderbook",
                "./lib/h20.test-std/lib/rain.orderbook/Cargo.toml",
                inputVaults,
                outputVaults
            );

            OrderV2 memory order = addOrderDepositOutputTokens(strategy); 
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