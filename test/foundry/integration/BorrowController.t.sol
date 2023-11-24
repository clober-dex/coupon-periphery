// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {Constants} from "../Constants.sol";
import {ForkUtils, ERC20Utils, Utils, PermitSignLibrary} from "../Utils.sol";
import {IAssetPool} from "../../../contracts/interfaces/IAssetPool.sol";
import {IAaveTokenSubstitute} from "../../../contracts/interfaces/IAaveTokenSubstitute.sol";
import {ICouponOracle} from "../../../contracts/interfaces/ICouponOracle.sol";
import {ICouponManager} from "../../../contracts/interfaces/ICouponManager.sol";
import {ILoanPositionManager, ILoanPositionManagerTypes} from "../../../contracts/interfaces/ILoanPositionManager.sol";
import {Coupon, CouponLibrary} from "../../../contracts/libraries/Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "../../../contracts/libraries/CouponKey.sol";
import {Epoch, EpochLibrary} from "../../../contracts/libraries/Epoch.sol";
import {LoanPosition} from "../../../contracts/libraries/LoanPosition.sol";
import {Wrapped1155MetadataBuilder} from "../../../contracts/libraries/Wrapped1155MetadataBuilder.sol";
import {ERC20PermitParams, PermitSignature} from "../../../contracts/libraries/PermitParams.sol";
import {IWrapped1155Factory} from "../../../contracts/external/wrapped1155/IWrapped1155Factory.sol";
import {CloberMarketFactory} from "../../../contracts/external/clober/CloberMarketFactory.sol";
import {CloberMarketSwapCallbackReceiver} from "../../../contracts/external/clober/CloberMarketSwapCallbackReceiver.sol";
import {CloberOrderBook} from "../../../contracts/external/clober/CloberOrderBook.sol";
import {BorrowController} from "../../../contracts/BorrowController.sol";
import {IBorrowController} from "../../../contracts/interfaces/IBorrowController.sol";
import {IController} from "../../../contracts/interfaces/IController.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";

contract BorrowControllerIntegrationTest is Test, CloberMarketSwapCallbackReceiver, ERC1155Holder {
    using Strings for *;
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;
    using PermitSignLibrary for Vm;

    address public constant MARKET_MAKER = address(999123);

    IAssetPool public assetPool;
    BorrowController public borrowController;
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
    ERC20PermitParams public emptyERC20PermitParams;
    PermitSignature public emptyERC721PermitParams;

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
        oracle = ICouponOracle(Constants.COUPON_COUPON_MANAGER);
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
            address(loanPositionManager),
            Constants.ODOS_V2_SWAP_ROUTER
        );

        IERC20(wausdc).transfer(address(assetPool), usdc.amount(1_000));
        IERC20(waweth).transfer(address(assetPool), 1_000 ether);

        // create wrapped1155
        for (uint8 i = 0; i < 5; i++) {
            couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current().add(i)}));
        }
        for (uint8 i = 5; i < 10; i++) {
            couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current().add(i - 5)}));
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
        uint16 loanEpochs
    ) internal returns (uint256 positionId) {
        positionId = loanPositionManager.nextId();
        ERC20PermitParams memory permitParams = vm.signPermit(
            1,
            IERC20Permit(IAaveTokenSubstitute(collateralToken).underlyingToken()),
            address(borrowController),
            collateralAmount
        );
        IBorrowController.SwapData memory swapData;
        vm.prank(borrower);
        borrowController.borrow(
            collateralToken,
            borrowToken,
            collateralAmount,
            borrowAmount,
            type(uint256).max,
            EpochLibrary.current().add(loanEpochs - 1),
            swapData,
            permitParams
        );
    }

    function testBorrow() public {
        uint256 collateralAmount = usdc.amount(10000);
        uint256 borrowAmount = 1 ether;

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        uint256 positionId = _initialBorrow(user, wausdc, waweth, collateralAmount, borrowAmount, 2);
        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.08 ether;

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertEq(usdc.balanceOf(user), beforeUSDCBalance - collateralAmount, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + borrowAmount - couponAmount, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + borrowAmount - couponAmount + 0.001 ether, "NATIVE_BALANCE_LE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, borrowAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, wausdc, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, waweth, "POSITION_DEBT_TOKEN");
    }

    function testBorrowMore() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount + 0.5 ether,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        uint256 borrowMoreAmount = 0.5 ether;
        uint256 couponAmount = 0.04 ether;

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + borrowMoreAmount - couponAmount, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + borrowMoreAmount - couponAmount + 0.001 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount + borrowMoreAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testAddCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        ERC20PermitParams memory permit20Params = vm.signPermit(
            1, IERC20Permit(IAaveTokenSubstitute(wausdc).underlyingToken()), address(borrowController), collateralAmount
        );
        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount + collateralAmount,
            beforeLoanPosition.debtAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            permit20Params,
            emptyERC20PermitParams
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance - collateralAmount, "USDC_BALANCE");
        assertEq(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount + collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRemoveCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            beforeLoanPosition.debtAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance + collateralAmount, "USDC_BALANCE");
        assertEq(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testExtendLoanDuration() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint16 epochs = 3;
        uint256 maxPayInterest = 0.04 ether * uint256(epochs);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        vm.startPrank(user);
        weth.approve(address(borrowController), maxPayInterest);
        borrowController.adjustPosition{value: maxPayInterest}(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount,
            maxPayInterest,
            0,
            beforeLoanPosition.expiredWith.add(epochs),
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
        vm.stopPrank();
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance - maxPayInterest, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + 0.01 ether - maxPayInterest, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith.add(epochs), afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testShortenLoanDuration() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 5);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint16 epochs = 3;
        uint256 minEarnInterest = 0.02 ether * epochs - 0.01 ether;
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith.sub(epochs),
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + minEarnInterest, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + minEarnInterest + 0.01 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith.add(epochs), "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepay() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 repayAmount = 0.3 ether;
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        ERC20PermitParams memory permit20Params = vm.signPermit(
            1, IERC20Permit(IAaveTokenSubstitute(waweth).underlyingToken()), address(borrowController), repayAmount
        );

        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        borrowController.adjustPosition{value: repayAmount}(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount - repayAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            permit20Params
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.012 ether;

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertLe(user.balance, beforeETHBalance - repayAmount + couponAmount, "NATIVE_BALANCE_GE");
        assertGe(user.balance, beforeETHBalance - repayAmount + couponAmount - 0.0001 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount + repayAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepayOverCloberMarket() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(200_000), 70 ether, 2);

        uint256 repayAmount = 60 ether;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        ERC20PermitParams memory permit20Params = vm.signPermit(
            1, IERC20Permit(IAaveTokenSubstitute(waweth).underlyingToken()), address(borrowController), repayAmount
        );

        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        borrowController.adjustPosition{value: repayAmount}(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount - repayAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            permit20Params
        );

        assertGt(couponManager.balanceOf(user, couponKeys[5].toId()), 9.9 ether, "COUPON0_BALANCE");
        assertLt(couponManager.balanceOf(user, couponKeys[6].toId()), 10 ether, "COUPON0_BALANCE");
    }

    function testLeverage() public {
        uint256 collateralAmount = 0.4 ether;
        uint256 borrowAmount = usdc.amount(550);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeWETHBalance = weth.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        uint256 positionId = loanPositionManager.nextId();
        ERC20PermitParams memory permitParams = vm.signPermit(
            1,
            IERC20Permit(AaveTokenSubstitute(payable(wausdc)).underlyingToken()),
            address(borrowController),
            collateralAmount
        );

        IBorrowController.SwapData memory swapData;
        swapData.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
            )
        );
        swapData.amount = usdc.amount(500);
        swapData.inToken = address(wausdc);

        vm.prank(user);
        borrowController.borrow{value: 0.16 ether}(
            waweth,
            wausdc,
            collateralAmount,
            borrowAmount,
            type(uint256).max,
            EpochLibrary.current().add(1),
            swapData,
            permitParams
        );

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user) - beforeUSDCBalance, 0, "USDC_BALANCE");
        assertLt(beforeETHBalance - user.balance, 0.16 ether, "NATIVE_BALANCE");
        assertEq(beforeWETHBalance, weth.balanceOf(user), "WETH_BALANCE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, borrowAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, waweth, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, wausdc, "POSITION_DEBT_TOKEN");
    }

    function testLeverageMore() public {
        uint256 positionId = _initialBorrow(user, waweth, wausdc, 1 ether, usdc.amount(500), 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeWETHBalance = weth.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 beforePositionCollateralAmount = loanPosition.collateralAmount;
        uint256 beforePositionDebtAmount = loanPosition.debtAmount;

        uint256 collateralAmount = 0.4 ether;
        uint256 borrowAmount = usdc.amount(550);

        ERC20PermitParams memory permitParams = vm.signPermit(
            1,
            IERC20Permit(AaveTokenSubstitute(payable(wausdc)).underlyingToken()),
            address(borrowController),
            collateralAmount
        );

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        swapData.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000803608bda99eed8c0028f5c00017F137D1D8d20BA54004Ba358E9C229DA26FA3Fa900000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010501020601a0a52cd80b010001020000270100030200020b0001040500ff000000fae2ae0a9f87fd35b5b0e24b47bac796a7eefea1af88d065e77c8cc2239327c5edb3a432268e5831d87899d10eaa10f3ade05038a38251f758e5c0ebc6f780497a95e246eb9449f5e4770916dcd6396a912ce59144191c1204e64559fe8253a0e49e654800000000000000000000000000000000000000000000000000000000"
            )
        );
        swapData.amount = usdc.amount(500);
        swapData.inToken = address(wausdc);

        vm.prank(user);
        borrowController.adjustPosition{value: 0.16 ether}(
            positionId,
            loanPosition.collateralAmount + collateralAmount,
            loanPosition.debtAmount + borrowAmount,
            type(uint256).max,
            0,
            loanPosition.expiredWith,
            swapData,
            permit721Params,
            permitParams,
            emptyERC20PermitParams
        );

        loanPosition = loanPositionManager.getPosition(positionId);

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user) - beforeUSDCBalance, 0, "USDC_BALANCE");
        assertLt(beforeETHBalance - user.balance, 0.16 ether, "NATIVE_BALANCE");
        assertEq(beforeWETHBalance, weth.balanceOf(user), "WETH_BALANCE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current().add(1), "POSITION_EXPIRE_EPOCH");
        assertEq(
            loanPosition.collateralAmount,
            collateralAmount + beforePositionCollateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(loanPosition.debtAmount, borrowAmount + beforePositionDebtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, waweth, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, wausdc, "POSITION_DEBT_TOKEN");
    }

    function testExpiredBorrowMore() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        // loan duration is 2 epochs
        vm.warp(EpochLibrary.current().add(2).startTime());
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILoanPositionManagerTypes.FullRepaymentRequired.selector));
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount + 0.5 ether,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
    }

    function testExpiredReduceCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        // loan duration is 2 epochs
        vm.warp(EpochLibrary.current().add(2).startTime());
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILoanPositionManagerTypes.FullRepaymentRequired.selector));
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            beforeLoanPosition.debtAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
    }

    function testOthersPosition() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        // loan duration is 2 epochs
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowController.SwapData memory swapData;
        vm.expectRevert(abi.encodeWithSelector(IController.InvalidAccess.selector));
        borrowController.adjustPosition(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            beforeLoanPosition.debtAmount,
            type(uint256).max,
            0,
            beforeLoanPosition.expiredWith,
            swapData,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
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
        bytes memory r = new bytes(ss.length / 2);
        for (uint256 i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(fromHexChar(uint8(ss[2 * i])) * 16 + fromHexChar(uint8(ss[2 * i + 1])));
        }
        return r;
    }

    function remove0x(string calldata s) external pure returns (string memory) {
        return s[2:];
    }

    function assertEq(Epoch e1, Epoch e2, string memory err) internal {
        assertEq(Epoch.unwrap(e1), Epoch.unwrap(e2), err);
    }
}
