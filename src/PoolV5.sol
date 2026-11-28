// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ReqoV3.sol";

contract PoolV5 is PoolV3 {
    using SafeERC20 for IERC20;

    address public immutable creator;

    event LiquidityToppedUp(
        address indexed creator,
        uint256 tokenAmount,
        uint256 wqorAmount
    );

    constructor(
        address token_,
        address wqor_,
        address creator_
    ) PoolV3(token_, wqor_) {
        require(creator_ != address(0), "zero creator");
        creator = creator_;
    }

    function topUp(
        uint256 tokenAmount,
        uint256 wqorAmount
    ) external nonReentrant {
        require(msg.sender == creator, "creator only");
        require(seeded, "not seeded");
        require(tokenAmount > 0 && wqorAmount > 0, "zero amount");

        // Exact proportional contributions preserve the recorded price.
        require(
            tokenAmount * wqorReserve ==
            wqorAmount * tokenReserve,
            "incorrect ratio"
        );

        IERC20(token).safeTransferFrom(
            msg.sender, address(this), tokenAmount
        );
        IERC20(wqor).safeTransferFrom(
            msg.sender, address(this), wqorAmount
        );

        tokenReserve += tokenAmount;
        wqorReserve += wqorAmount;

        emit LiquidityToppedUp(
            msg.sender, tokenAmount, wqorAmount
        );
    }
}
