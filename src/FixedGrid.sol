// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;
import {Vm} from "forge-std/Vm.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    IOrderBookV3,
    IO,
    OrderV2,
    OrderConfigV2,
    TakeOrderConfigV2,
    TakeOrdersConfigV2
} from "rain.orderbook.interface/interface/IOrderBookV3.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

uint256 constant VAULT_ID = uint256(keccak256("vault"));

/// @dev https://basescan.org/address/0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D
IERC20 constant WLTH_TOKEN = IERC20(0x99b2B1A2aDB02B38222ADcD057783D7e5D1FCC7D); 

/// @dev https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
IERC20 constant USDC_TOKEN = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

function baseWlthIo() pure returns (IO memory) {
    return IO(address(WLTH_TOKEN), 18, VAULT_ID);
}

function baseUsdcIo() pure returns (IO memory) {
    return IO(address(USDC_TOKEN), 6, VAULT_ID);
}

string constant WLTH_FILE_PATH = "strategies/Common-Wealth/cw-base-launch-tranch1.rain";
string constant WLTH_BUY_SCENARIO = "base-wlth-tranches.buy.initialized.prod";
string constant WLTH_SELL_SCENARIO = "base-wlth-tranches.sell.initialized.prod"; 

string constant WLTH_FIXED_GRID = "strategies/Common-Wealth/cw-fixed-grid.rain";
string constant WLTH_BUY_FIXED_GRID_PROD = "base-wlth-fixed-grid.buy.prod";
string constant WLTH_BUY_FIXED_GRID_TEST_TWAP = "base-wlth-fixed-grid.buy.test-twap";

string constant WLTH_SELL_FIXED_GRID_PROD = "base-wlth-fixed-grid.sell.prod";
string constant WLTH_SELL_FIXED_GRID_TEST_TWAP = "base-wlth-fixed-grid.sell.test-twap";
