// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils, Utils} from "../Utils.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {IAaveTokenSubstitute} from "../../../contracts/interfaces/IAaveTokenSubstitute.sol";
import {ICouponOracle} from "../../../contracts/interfaces/ICouponOracle.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {IController} from "../../../contracts/interfaces/IController.sol";
import {IERC721Permit} from "../../../contracts/interfaces/IERC721Permit.sol";
import {ILoanPositionManager, ILoanPositionManagerTypes} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {LoanPosition} from "../../../contracts/libraries/LoanPosition.sol";
import {Wrapped1155MetadataBuilder} from "../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {IWrapped1155Factory} from "../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {CloberMarketFactory} from "../../../contracts/external/clober/CloberMarketFactory.sol";
import {CloberMarketSwapCallbackReceiver} from "../../../contracts/external/clober/CloberMarketSwapCallbackReceiver.sol";
import {CloberOrderBook} from "../../../contracts/external/clober/CloberOrderBook.sol";
import {BorrowController} from "../../../contracts/BorrowController.sol";
import {IBorrowController} from "../../../contracts/interfaces/IBorrowController.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";
import {CouponLiquidator} from "../../../contracts/CouponLiquidator.sol";

contract CouponLiquidatorIntegrationTest is Test, CloberMarketSwapCallbackReceiver, ERC1155Holder {
    using Strings for *;
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;

    address public constant MARKET_MAKER = address(999123);
    bytes32 private constant _ERC20_PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    IAssetPool public assetPool;
    BorrowController public borrowController;
    CouponLiquidator public couponLiquidator;
    ILoanPositionManager public loanPositionManager;
    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;
    ICouponOracle public oracle;
    CloberMarketFactory public cloberMarketFactory;
    IERC20 public usdc;
    IERC20 public weth;
    address public wausdc;
    address public waweth;
    address public user;
    IController.ERC20PermitParams public emptyERC20PermitParams;
    IController.PermitSignature public emptyERC721PermitParams;

    CouponKey[] public couponKeys;
    address[] public wrappedCoupons;

    function setUp() public {
        ForkUtils.fork(vm, Constants.FORK_BLOCK_NUMBER);
        user = vm.addr(1);

        usdc = IERC20(Constants.USDC);
        weth = IERC20(Constants.WETH);
        vm.startPrank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(1_000_000));
        usdc.transfer(address(this), usdc.amount(1_000_000));
        vm.stopPrank();
        vm.deal(user, 1_000_000 ether);

        bool success;
        vm.startPrank(user);
        (success,) = payable(address(weth)).call{value: 500_000 ether}("");
        require(success, "transfer failed");
        vm.stopPrank();

        vm.deal(address(this), 1_000_000 ether);
        (success,) = payable(address(weth)).call{value: 500_000 ether}("");
        require(success, "transfer failed");

        wrapped1155Factory = IWrapped1155Factory(Constants.WRAPPED1155_FACTORY);
        cloberMarketFactory = CloberMarketFactory(Constants.CLOBER_FACTORY);
        wausdc = Constants.COUPON_USDC_SUBSTITUTE;
        waweth = Constants.COUPON_WETH_SUBSTITUTE;
        oracle = ICouponOracle(Constants.COUPON_ORACLE);
        assetPool = IAssetPool(Constants.COUPON_ASSET_POOL);
        couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
        loanPositionManager = ILoanPositionManager(Constants.COUPON_LOAN_POSITION_MANAGER);

        usdc.approve(wausdc, usdc.amount(3_000));
        IAaveTokenSubstitute(wausdc).mint(usdc.amount(3_000), address(this));
        IERC20(Constants.WETH).approve(waweth, 3_000 ether);
        IAaveTokenSubstitute(waweth).mint(3_000 ether, address(this));

        borrowController = new BorrowController(
            Constants.WRAPPED1155_FACTORY,
            Constants.CLOBER_FACTORY,
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager)
        );

        couponLiquidator =
            new CouponLiquidator( address (loanPositionManager), Constants.ODOS_V2_SWAP_ROUTER, Constants.WETH);

        IERC20(wausdc).transfer(address(assetPool), usdc.amount(1_500));
        IERC20(waweth).transfer(address(assetPool), 1_500 ether);

        // create wrapped1155
        for (uint8 i = 0; i < 5; i++) {
            couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current().add(i)}));
        }
        if (!cloberMarketFactory.registeredQuoteTokens(wausdc)) {
            vm.prank(cloberMarketFactory.owner());
            cloberMarketFactory.registerQuoteToken(wausdc);
        }
        for (uint8 i = 5; i < 10; i++) {
            couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current().add(i - 5)}));
        }
        if (!cloberMarketFactory.registeredQuoteTokens(waweth)) {
            vm.prank(cloberMarketFactory.owner());
            cloberMarketFactory.registerQuoteToken(waweth);
        }
        for (uint256 i = 0; i < 10; i++) {
            address wrappedToken = wrapped1155Factory.requireWrapped1155(
                address(couponManager),
                couponKeys[i].toId(),
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            wrappedCoupons.push(wrappedToken);
            address market = cloberMarketFactory.createVolatileMarket(
                address(Constants.TREASURY),
                couponKeys[i].asset,
                wrappedToken,
                i < 5 ? 1 : 1e9,
                0,
                400,
                1e10,
                1001 * 1e15
            );
            borrowController.setCouponMarket(couponKeys[i], market);
        }
        _marketMake();

        vm.prank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(10_000));
        vm.deal(address(user), 100 ether);
    }

    function _marketMake() internal {
        for (uint256 i = 0; i < wrappedCoupons.length; ++i) {
            CouponKey memory key = couponKeys[i];
            CloberOrderBook market = CloberOrderBook(borrowController.getCouponMarket(key));
            (uint16 bidIndex,) = market.priceToIndex(1e18 / 100 * 2, false); // 2%
            (uint16 askIndex,) = market.priceToIndex(1e18 / 100 * 4, false); // 4%
            CloberOrderBook(market).limitOrder(
                MARKET_MAKER, bidIndex, market.quoteToRaw(IERC20(key.asset).amount(1), false), 0, 3, ""
            );
            uint256 amount = IERC20(wrappedCoupons[i]).amount(5000);
            Coupon[] memory coupons = Utils.toArr(Coupon(key, amount));
            vm.prank(Constants.COUPON_LOAN_POSITION_MANAGER);
            couponManager.mintBatch(address(this), coupons, "");
            couponManager.safeBatchTransferFrom(
                address(this),
                address(wrapped1155Factory),
                coupons,
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            CloberOrderBook(market).limitOrder(MARKET_MAKER, askIndex, 0, amount, 2, "");
        }
    }

    function cloberMarketSwapCallback(address inputToken, address, uint256 inputAmount, uint256, bytes calldata)
        external
        payable
    {
        if (inputAmount > 0) {
            IERC20(inputToken).transfer(msg.sender, inputAmount);
        }
    }

    function _initialBorrow(
        address borrower,
        address collateralToken,
        address borrowToken,
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint8 loanEpochs
    ) internal returns (uint256 positionId) {
        positionId = loanPositionManager.nextId();
        IController.ERC20PermitParams memory permitParams = _buildERC20PermitParams(
            1, AaveTokenSubstitute(payable(collateralToken)), address(borrowController), collateralAmount
        );
        vm.prank(borrower);
        borrowController.borrow(
            collateralToken, borrowToken, collateralAmount, borrowAmount, type(uint256).max, loanEpochs, permitParams
        );
    }

    function testLiquidator() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(700), 0.24 ether, 2);

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        address feeRecipient = address(this);
        uint256 beforeUSDCBalance = usdc.balanceOf(feeRecipient);
        uint256 beforeWETHBalance = weth.balanceOf(feeRecipient);

        address[] memory assets = new address[](3);
        assets[0] = Constants.COUPON_USDC_SUBSTITUTE;
        assets[1] = Constants.COUPON_WETH_SUBSTITUTE;
        assets[2] = address(0);

        uint256[] memory prices = new uint256[](3);
        prices[0] = 99997900;
        prices[1] = 205485580000;
        prices[2] = 205485580000;

        vm.warp(loanPosition.expiredWith.endTime() + 1);

        vm.mockCall(address(oracle), abi.encodeWithSignature("getAssetsPrices(address[])", assets), abi.encode(prices));
        assertEq(oracle.getAssetsPrices(assets)[1], 205485580000, "MANIPULATE_ORACLE");

        bytes memory data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
                this.remove0x(Strings.toHexString(address(couponLiquidator))),
                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
            )
        );

        couponLiquidator.liquidate(positionId, usdc.amount(500), data, feeRecipient);

        assertEq(usdc.balanceOf(feeRecipient) - beforeUSDCBalance, 3344321, "USDC_BALANCE");
        assertEq(weth.balanceOf(feeRecipient) - beforeWETHBalance, 3348150879705280, "WETH_BALANCE");
    }

    // Convert an hexadecimal character to their value
    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        revert("fail");
    }

    // Convert an hexadecimal string to raw bytes
    function fromHex(string memory s) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length/2);
        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }

    function remove0x(string calldata s) external pure returns (string memory) {
        return s[2:];
    }

    function _buildERC20PermitParams(
        uint256 privateKey,
        IAaveTokenSubstitute substitute,
        address spender,
        uint256 amount
    ) internal view returns (IController.ERC20PermitParams memory) {
        IERC20Permit token = IERC20Permit(substitute.underlyingToken());
        address owner = vm.addr(privateKey);
        bytes32 structHash = keccak256(
            abi.encode(_ERC20_PERMIT_TYPEHASH, owner, spender, amount, token.nonces(owner), block.timestamp + 1)
        );
        bytes32 hash = MessageHashUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return IController.ERC20PermitParams(amount, IController.PermitSignature(block.timestamp + 1, v, r, s));
    }

    function _buildERC721PermitParams(uint256 privateKey, IERC721Permit token, address spender, uint256 tokenId)
        internal
        view
        returns (IController.PermitSignature memory)
    {
        bytes32 structHash =
            keccak256(abi.encode(token.PERMIT_TYPEHASH(), spender, tokenId, token.nonces(tokenId), block.timestamp + 1));
        bytes32 hash = MessageHashUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return IController.PermitSignature(block.timestamp + 1, v, r, s);
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
