import { arbitrum, arbitrumSepolia } from 'viem/chains'
import { Address } from 'viem'

export const TESTNET_ID = 7777

export const SINGLETON_FACTORY = '0xce0042B868300000d44A59004Da54A005ffdcf9f'

export const OWNER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x1689FD73FfC888d47D201b72B0ae7A83c20fA274',
  [arbitrumSepolia.id]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
  [TESTNET_ID]: '0xa0E3174f4D222C5CBf705A138C6a9369935EeD81',
}

export const TREASURY: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x2f1707aed1fb24d07b9b42e4b0bc885f546b4f43',
  [arbitrumSepolia.id]: '0x000000000000000000000000000000000000dEaD',
  [TESTNET_ID]: '0x000000000000000000000000000000000000dEaD',
}

export const AAVE_V3_POOL: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
  [TESTNET_ID]: '0x794a61358D6845594F94dc1DB02A252b5b4814aD',
}

export const ASSET_POOL: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xBA4B7f0Dd297C68Ca472da58CfE1338B9E7A0D9e',
}

export const BOND_POSITION_MANAGER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x0Cf91Bc7a67B063142C029a69fF9C8ccd93476E2',
}

export const COUPON_MANAGER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x8bbcA766D175aDbffB073832262990df1c5ef748',
}

export const COUPON_ORACLE: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xF8e9ab02b057978c29Ca57c7E086D46983764A13',
}

export const LOAN_POSITION_MANAGER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x03d65411684ae7B5440E11a6063881a774C733dF',
}

export const CLOBER_FACTORY: { [chainId: number]: Address } = {
  [arbitrum.id]: '0x24aC0938C010Fb520F1068e96d78E0458855111D',
}

export const WRAPPED1155_FACTORY: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xfcBE16BfD991E4949244E59d9b524e6964b8BB75',
}

export const ODOS_ROUTER: { [chainId: number]: Address } = {
  [arbitrum.id]: '0xa669e7A0d4b3e4Fa48af2dE86BD4CD7126Be4e13',
  [arbitrumSepolia.id]: '0xfd71fBe411E839220b625826858578454f58F4b2',
}

export const TOKEN_KEYS = {
  WETH: 'WETH',
  wstETH: 'wstETH',
  USDC: 'USDC',
  USDCe: 'USDC.e',
  DAI: 'DAI',
  USDT: 'USDT',
  WBTC: 'WBTC',
  ARB: 'ARB',
}

export type TokenKeys = (typeof TOKEN_KEYS)[keyof typeof TOKEN_KEYS]

export const TOKENS: { [chainId: number]: { [name: TokenKeys]: Address } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1',
    [TOKEN_KEYS.wstETH]: '0x5979D7b546E38E414F7E9822514be443A4800529',
    [TOKEN_KEYS.USDC]: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    [TOKEN_KEYS.USDCe]: '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8',
    [TOKEN_KEYS.DAI]: '0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1',
    [TOKEN_KEYS.USDT]: '0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9',
    [TOKEN_KEYS.WBTC]: '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f',
    [TOKEN_KEYS.ARB]: '0x912CE59144191C1204E64559FE8253a0e49E6548',
  },
  [arbitrumSepolia.id]: {
    [TOKEN_KEYS.WBTC]: '0x929075bdc8cf2e43cA7FB4BF1a189130b6014Cc1',
    [TOKEN_KEYS.USDC]: '0x92bb5C37868C5B34B163FeFAb4e20b1179853eB9',
    [TOKEN_KEYS.DAI]: '0x00644a534bDea310ee2FCCF1c2821Df769A0b12F',
    [TOKEN_KEYS.USDT]: '0xf989cF31a0C30c766C7f81Eb71b1Df518e7E9EBA',
    [TOKEN_KEYS.WETH]: '0xE0dBCB42CCAc63C949cE3EF879A647DDb662916d',
  },
}

export const SUBSTITUTES: { [chainId: number]: { [name: TokenKeys]: Address } } = {
  [arbitrum.id]: {
    [TOKEN_KEYS.WETH]: '0xAb6c37355D6C06fcF73Ab0E049d9Cf922f297573',
    [TOKEN_KEYS.USDC]: '0x7Ed1145045c8B754506d375Cdf90734550d1077e',
    [TOKEN_KEYS.wstETH]: '0x4e0e151940ad5790ac087DA335F1104A5C4f6f71',
    [TOKEN_KEYS.DAI]: '0x43FE2BE829a00ba065FAF5B1170c3b0f1328eb37',
    [TOKEN_KEYS.USDCe]: '0x322d24b60795e3D4f0DD85F54FAbcd63A85dFF82',
    [TOKEN_KEYS.USDT]: '0x26185cC53695240f9298e1e81Fd95612aA19D68b',
    [TOKEN_KEYS.WBTC]: '0xCf94152a31BBC050603Ae3186b394269E4f0A8Fe',
    [TOKEN_KEYS.ARB]: '0x3D3d18B22b6EB47ffC21ca226E506Bd1C5C7cc00',
  },
  [arbitrumSepolia.id]: {
    [TOKEN_KEYS.WBTC]: '0xbd6Bc9B2ED76bF27B42586C8d81cDbe8250A9b98',
    [TOKEN_KEYS.USDC]: '0x447AD4A108B5540c220f9F7E83723ac87c0f8FD8',
    [TOKEN_KEYS.DAI]: '0x643477e3f1A4BCA02e74904E79F8A89492b241fF',
    [TOKEN_KEYS.USDT]: '0xD74b405f598EEbE7Eac0d4E39f4CC31309a87246',
    [TOKEN_KEYS.WETH]: '0xA4fCfCE915DFBBDD6F41d4e307517160D73661f9',
  },
}
