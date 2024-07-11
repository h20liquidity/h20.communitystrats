// SPDX-License-Identifier: CAL
pragma solidity =0.8.25;

interface IOrderBookV4OrderTaker {
    /// @notice Called by `IOrderBookV4` when `takeOrders` is called with
    /// non-zero data, if it caused a non-zero input amount. I.e. if the order(s)
    /// taker received some tokens. Input and output directions are relative to
    /// the `IOrderBookV4OrderTaker` contract. If the order(s) taker had an
    /// active debt from a flash loan then that debt will be paid _before_
    /// calculating any input amounts sent.
    /// i.e. the debt is deducted from the input amount before this callback is
    /// called.
    /// @param inputToken The token that was sent to `IOrderBookV4OrderTaker`.
    /// @param outputToken The token that `IOrderBookV4` will attempt to pull
    /// from `IOrderBookV4OrderTaker` after this callback returns.
    /// @param inputAmountSent The amount of `inputToken` that was sent to
    /// `IOrderBookV4OrderTaker`.
    /// @param totalOutputAmount The total amount of `outputToken` that
    /// `IOrderBookV4` will attempt to pull from `IOrderBookV4OrderTaker` after
    /// this callback returns.
    /// @param takeOrdersData The data passed to `takeOrders` by the caller.
    function onTakeOrders(
        address inputToken,
        address outputToken,
        uint256 inputAmountSent,
        uint256 totalOutputAmount,
        bytes calldata takeOrdersData
    ) external;
}