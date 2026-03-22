// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/BotTheHouseEscrow.sol";

contract Deploy is Script {
    function run() external {
        address houseWallet = vm.envAddress("HOUSE_WALLET_ADDRESS");
        address settler     = vm.envAddress("SETTLER_ADDRESS");
        uint256 rakeRateBps = 500;

        vm.startBroadcast();
        BotTheHouseEscrow escrow = new BotTheHouseEscrow(houseWallet, settler, rakeRateBps);
        vm.stopBroadcast();

        console.log("BotTheHouseEscrow deployed to:", address(escrow));
    }
}
