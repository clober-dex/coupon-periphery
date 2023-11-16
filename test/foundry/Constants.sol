// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Constants {
    uint256 internal constant FORK_BLOCK_NUMBER = 150920883;
    address internal constant TREASURY = address(0xc0f1);
    address internal constant USER1 = address(0x1);
    address internal constant USER2 = address(0x2);
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address internal constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address internal constant USDC_MINTER = 0xE7Ed1fa7f45D05C508232aa32649D89b73b8bA48;
    address internal constant USDC_WHALE = 0xB38e8c17e38363aF6EbdCb3dAE12e0243582891D;
    address internal constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant WRAPPED1155_FACTORY = 0xfcBE16BfD991E4949244E59d9b524e6964b8BB75;
    address internal constant CLOBER_FACTORY = 0x24aC0938C010Fb520F1068e96d78E0458855111D;
    address internal constant ODOS_V2_SWAP_ROUTER = 0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13;
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    // https://docs.chain.link/data-feeds/price-feeds/addresses?network=arbitrum
    address internal constant ETH_CHAINLINK_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address internal constant USDC_CHAINLINK_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address internal constant COUPON_ASSET_POOL = 0xBA4B7f0Dd297C68Ca472da58CfE1338B9E7A0D9e;
    address internal constant COUPON_BOND_POSITION_MANAGER = 0x0Cf91Bc7a67B063142C029a69fF9C8ccd93476E2;
    address internal constant COUPON_LOAN_POSITION_MANAGER = 0x03d65411684ae7B5440E11a6063881a774C733dF;
    address internal constant COUPON_COUPON_MANAGER = 0x8bbcA766D175aDbffB073832262990df1c5ef748;
    address internal constant COUPON_ORACLE = 0xF8e9ab02b057978c29Ca57c7E086D46983764A13;
    address internal constant COUPON_WETH_SUBSTITUTE = 0xAb6c37355D6C06fcF73Ab0E049d9Cf922f297573;
    address internal constant COUPON_USDC_SUBSTITUTE = 0x7Ed1145045c8B754506d375Cdf90734550d1077e;
}
