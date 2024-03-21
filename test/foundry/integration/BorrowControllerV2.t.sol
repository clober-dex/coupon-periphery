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
import {CloberOrderBook} from "../../../contracts/external/clober/CloberOrderBook.sol";
import {BorrowControllerV2} from "../../../contracts/BorrowControllerV2.sol";
import {Tick} from "../../../contracts/external/clober-v2/Tick.sol";
import {BookIdLibrary} from "../../../contracts/external/clober-v2/BookId.sol";
import {IBorrowControllerV2} from "../../../contracts/interfaces/IBorrowControllerV2.sol";
import {IControllerV2} from "../../../contracts/interfaces/IControllerV2.sol";
import {IController} from "../../../contracts/external/clober-v2/IController.sol";
import {IBookManager} from "../../../contracts/external/clober-v2/IBookManager.sol";
import {IHooks} from "../../../contracts/external/clober-v2/IHooks.sol";
import {Currency, CurrencyLibrary} from "../../../contracts/external/clober-v2/Currency.sol";
import {FeePolicy, FeePolicyLibrary} from "../../../contracts/external/clober-v2/FeePolicy.sol";
import {DepositControllerV2} from "../../../contracts/DepositControllerV2.sol";
import {MockBookManager} from "../mocks/MockBookManager.sol";
import {MockController} from "../mocks/MockController.sol";
import {AaveTokenSubstitute} from "../../../contracts/AaveTokenSubstitute.sol";

contract BorrowControllerV2IntegrationTest is Test, ERC1155Holder {
    using Strings for *;
    using ERC20Utils for IERC20;
    using CouponKeyLibrary for CouponKey;
    using EpochLibrary for Epoch;
    using PermitSignLibrary for Vm;
    using BookIdLibrary for IBookManager.BookKey;

    address public constant MARKET_MAKER = address(999123);

    IAssetPool public assetPool;
    BorrowControllerV2 public borrowController;
    ILoanPositionManager public loanPositionManager;
    IWrapped1155Factory public wrapped1155Factory;
    ICouponManager public couponManager;
    ICouponOracle public oracle;
    IController public cloberController;
    IBookManager public bookManager;
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
        ForkUtils.fork(vm, 192621731);
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
        wausdc = Constants.COUPON_USDC_SUBSTITUTE;
        waweth = Constants.COUPON_WETH_SUBSTITUTE;
        oracle = ICouponOracle(Constants.COUPON_COUPON_MANAGER);
        assetPool = IAssetPool(Constants.COUPON_ASSET_POOL);
        couponManager = ICouponManager(Constants.COUPON_COUPON_MANAGER);
        loanPositionManager = ILoanPositionManager(Constants.COUPON_LOAN_POSITION_MANAGER);
        bookManager = IBookManager(Constants.CLOBER_BOOK_MANAGER);
        cloberController = IController(Constants.CLOBER_CONTROLLER);

        borrowController = new BorrowControllerV2(
            Constants.WRAPPED1155_FACTORY,
            address(cloberController),
            address(bookManager),
            address(couponManager),
            Constants.WETH,
            address(loanPositionManager),
            Constants.ODOS_V2_SWAP_ROUTER
        );

        usdc.approve(wausdc, usdc.amount(3_000));
        IAaveTokenSubstitute(wausdc).mint(usdc.amount(3_000), address(this));
        IERC20(Constants.WETH).approve(waweth, 3_000 ether);
        IAaveTokenSubstitute(waweth).mint(3_000 ether, address(this));

        // create wrapped1155
        couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current()}));
        couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current()}));
        couponKeys.push(CouponKey({asset: wausdc, epoch: EpochLibrary.current().add(1)}));
        couponKeys.push(CouponKey({asset: waweth, epoch: EpochLibrary.current().add(1)}));

        IController.MakeOrderParams[] memory makeOrderParamsList = new IController.MakeOrderParams[](8);
        address[] memory tokensToSettle = new address[](6);
        for (uint256 i = 0; i < 4; i++) {
            CouponKey memory key = couponKeys[i];
            IController.OpenBookParams[] memory openBookParamsList = new IController.OpenBookParams[](2);
            address wrappedToken = wrapped1155Factory.requireWrapped1155(
                address(couponManager), key.toId(), Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );
            wrappedCoupons.push(wrappedToken);
            IHooks hooks;
            IBookManager.BookKey memory sellBookKey = IBookManager.BookKey({
                base: Currency.wrap(wrappedToken),
                unit: i % 2 == 0 ? 1 : 10 ** 6,
                quote: Currency.wrap(i % 2 == 0 ? wausdc : waweth),
                makerPolicy: FeePolicyLibrary.encode(true, 100),
                hooks: hooks,
                takerPolicy: FeePolicyLibrary.encode(true, 100)
            });
            IBookManager.BookKey memory buyBookKey = IBookManager.BookKey({
                base: Currency.wrap(i % 2 == 0 ? wausdc : waweth),
                unit: i % 2 == 0 ? 1 : 10 ** 6,
                quote: Currency.wrap(wrappedCoupons[i]),
                makerPolicy: FeePolicyLibrary.encode(true, 100),
                hooks: hooks,
                takerPolicy: FeePolicyLibrary.encode(true, 100)
            });

            openBookParamsList[0] = IController.OpenBookParams({key: sellBookKey, hookData: ""});
            openBookParamsList[1] = IController.OpenBookParams({key: buyBookKey, hookData: ""});
            cloberController.open(openBookParamsList, uint64(block.timestamp));
            borrowController.setCouponBookKey(key, sellBookKey, buyBookKey);

            uint256 amount = IERC20(wrappedToken).amount(1600);
            Coupon[] memory coupons = Utils.toArr(Coupon(key, amount));
            vm.prank(Constants.COUPON_LOAN_POSITION_MANAGER);
            couponManager.mintBatch(address(this), coupons, "");
            couponManager.safeBatchTransferFrom(
                address(this),
                address(wrapped1155Factory),
                coupons,
                Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKeys[i])
            );

            makeOrderParamsList[i * 2] = IController.MakeOrderParams({
                id: sellBookKey.toId(),
                tick: Tick.wrap(-39122),
                quoteAmount: i % 2 == 0 ? IERC20(wausdc).amount(1200) : IERC20(waweth).amount(1200),
                hookData: ""
            });
            makeOrderParamsList[i * 2 + 1] = IController.MakeOrderParams({
                id: buyBookKey.toId(),
                tick: Tick.wrap(39122),
                quoteAmount: IERC20(wrappedToken).amount(1200),
                hookData: ""
            });
            tokensToSettle[i] = wrappedToken;
            IERC20(wrappedToken).approve(address(cloberController), type(uint256).max);
        }

        IERC20(wausdc).approve(address(cloberController), type(uint256).max);
        IERC20(waweth).approve(address(cloberController), type(uint256).max);
        tokensToSettle[4] = address(wausdc);
        tokensToSettle[5] = address(waweth);
        IController.ERC20PermitParams[] memory permitParamsList;
        cloberController.make(makeOrderParamsList, tokensToSettle, permitParamsList, uint64(block.timestamp));

        vm.prank(Constants.USDC_WHALE);
        usdc.transfer(user, usdc.amount(10_000));
        vm.deal(address(user), 100 ether);
    }

    function _initialBorrow(
        address borrower,
        address collateralToken,
        address borrowToken,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint16 loanEpochs
    ) internal returns (uint256 positionId) {
        positionId = loanPositionManager.nextId();
        ERC20PermitParams memory permitParams = vm.signPermit(
            1,
            IERC20Permit(IAaveTokenSubstitute(collateralToken).underlyingToken()),
            address(borrowController),
            collateralAmount
        );
        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(borrower);
        borrowController.borrow(
            collateralToken,
            borrowToken,
            collateralAmount,
            debtAmount,
            type(int256).max,
            EpochLibrary.current().add(loanEpochs - 1),
            swapParams,
            permitParams
        );
    }

    function testBorrow() public {
        uint256 collateralAmount = usdc.amount(10000);
        uint256 debtAmount = 1 ether;

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        uint256 positionId = _initialBorrow(user, wausdc, waweth, collateralAmount, debtAmount, 1);
        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.0201 ether;

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertEq(usdc.balanceOf(user), beforeUSDCBalance - collateralAmount, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance + debtAmount - couponAmount, "NATIVE_BALANCE_GE");
        assertLe(user.balance, beforeETHBalance + debtAmount - couponAmount + 0.001 ether, "NATIVE_BALANCE_LE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current(), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, wausdc, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, waweth, "POSITION_DEBT_TOKEN");
    }

    function testBorrowMore() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 1);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount + 0.5 ether,
            type(int256).max,
            beforeLoanPosition.expiredWith,
            swapParams,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        uint256 borrowMoreAmount = 0.5 ether;
        uint256 couponAmount = 0.0101 ether;

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
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 1);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        ERC20PermitParams memory permit20Params = vm.signPermit(
            1, IERC20Permit(IAaveTokenSubstitute(wausdc).underlyingToken()), address(borrowController), collateralAmount
        );
        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount + collateralAmount,
            beforeLoanPosition.debtAmount,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
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
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 1);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(123);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            beforeLoanPosition.debtAmount,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
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
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 1);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeWETHBalance = weth.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint16 epochs = 1;
        uint256 maxPayInterest = 0.0201 ether * uint256(epochs);
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.startPrank(user);
        weth.approve(address(borrowController), maxPayInterest);
        borrowController.adjust{value: maxPayInterest}(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount,
            int256(maxPayInterest),
            beforeLoanPosition.expiredWith.add(epochs),
            swapParams,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );
        vm.stopPrank();
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(
            user.balance + weth.balanceOf(user) - beforeWETHBalance,
            beforeETHBalance - maxPayInterest,
            "NATIVE_BALANCE_GE"
        );
        assertLe(
            user.balance + weth.balanceOf(user) - beforeWETHBalance,
            beforeETHBalance - maxPayInterest + 0.0001 ether,
            "NATIVE_BALANCE_LE"
        );
        assertEq(beforeLoanPosition.expiredWith.add(epochs), afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testShortenLoanDuration() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint16 epochs = 1;
        uint256 minEarnInterest = 0.0199 ether * epochs;
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount,
            0,
            beforeLoanPosition.expiredWith.sub(epochs),
            swapParams,
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
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 1);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 repayAmount = 0.3 ether;
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);
        ERC20PermitParams memory permit20Params = vm.signPermit(
            1, IERC20Permit(IAaveTokenSubstitute(waweth).underlyingToken()), address(borrowController), repayAmount
        );

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        borrowController.adjust{value: repayAmount}(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount - repayAmount,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
            permit721Params,
            emptyERC20PermitParams,
            permit20Params
        );
        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        uint256 couponAmount = 0.006 ether;

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertLe(user.balance, beforeETHBalance - repayAmount + couponAmount, "NATIVE_BALANCE_GE");
        assertGe(user.balance, beforeETHBalance - repayAmount + couponAmount - 0.0001 ether, "NATIVE_BALANCE_LE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(beforeLoanPosition.collateralAmount, afterLoanPosition.collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(beforeLoanPosition.debtAmount, afterLoanPosition.debtAmount + repayAmount, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testLeverage() public {
        uint256 collateralAmount = 0.4 ether;
        uint256 debtAmount = usdc.amount(550);

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

        IBorrowControllerV2.SwapParams memory swapParams;
        swapParams.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000801f447c4595e16b000068d00019b57DcA972Db5D8866c630554AcdbDfE58b2659c00000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010803020801b9269d0f2801010102011dc097350301010103010019011fe3097c0b010104010001240149360b0101050100012fba5f510b0101060100000b0101070100ff0000000000000000000000000000000000000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab1db86e7fe4074e3c29d2fd0ed1d104c00e11a196b4ef385d20247f5d0f9cd2e3f716b9a55e71df9347fcdc35463e3770c2fb992716cd070b63540b947f6416e1ed89a3abca179f971b30555eb2234f30c6c9ab1c1dc392b53f9fb2ea6d9dace5f99efdc480000000000000000000000000000000000000000"
            )
        );
        swapParams.amount = usdc.amount(500);
        swapParams.inSubstitute = address(wausdc);

        vm.prank(user);
        borrowController.borrow{value: 0.26 ether}(
            waweth,
            wausdc,
            collateralAmount,
            debtAmount,
            type(int256).max,
            EpochLibrary.current(),
            swapParams,
            permitParams
        );

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user) - beforeUSDCBalance, 0, "USDC_BALANCE");
        assertLt(beforeETHBalance - user.balance, 0.26 ether, "NATIVE_BALANCE");
        assertEq(beforeWETHBalance, weth.balanceOf(user), "WETH_BALANCE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current(), "POSITION_EXPIRE_EPOCH");
        assertEq(loanPosition.collateralAmount, collateralAmount, "POSITION_COLLATERAL_AMOUNT");
        assertEq(loanPosition.debtAmount, debtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, waweth, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, wausdc, "POSITION_DEBT_TOKEN");
    }

    function testLeverageMore() public {
        uint256 positionId = _initialBorrow(user, waweth, wausdc, 1 ether, usdc.amount(500), 1);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeWETHBalance = weth.balanceOf(user);
        uint256 beforeETHBalance = user.balance;

        LoanPosition memory loanPosition = loanPositionManager.getPosition(positionId);

        uint256 beforePositionCollateralAmount = loanPosition.collateralAmount;
        uint256 beforePositionDebtAmount = loanPosition.debtAmount;

        uint256 collateralAmount = 0.4 ether;
        uint256 debtAmount = usdc.amount(550);

        ERC20PermitParams memory permitParams = vm.signPermit(
            1,
            IERC20Permit(AaveTokenSubstitute(payable(wausdc)).underlyingToken()),
            address(borrowController),
            collateralAmount
        );

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowControllerV2.SwapParams memory swapParams;
        swapParams.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000801f447c4595e16b000068d00019b57DcA972Db5D8866c630554AcdbDfE58b2659c00000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010803020801b9269d0f2801010102011dc097350301010103010019011fe3097c0b010104010001240149360b0101050100012fba5f510b0101060100000b0101070100ff0000000000000000000000000000000000000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab1db86e7fe4074e3c29d2fd0ed1d104c00e11a196b4ef385d20247f5d0f9cd2e3f716b9a55e71df9347fcdc35463e3770c2fb992716cd070b63540b947f6416e1ed89a3abca179f971b30555eb2234f30c6c9ab1c1dc392b53f9fb2ea6d9dace5f99efdc480000000000000000000000000000000000000000"
            )
        );
        swapParams.amount = usdc.amount(500);
        swapParams.inSubstitute = address(wausdc);

        vm.prank(user);
        borrowController.adjust{value: 0.26 ether}(
            positionId,
            loanPosition.collateralAmount + collateralAmount,
            loanPosition.debtAmount + debtAmount,
            type(int256).max,
            loanPosition.expiredWith,
            swapParams,
            permit721Params,
            permitParams,
            emptyERC20PermitParams
        );

        loanPosition = loanPositionManager.getPosition(positionId);

        assertEq(loanPositionManager.ownerOf(positionId), user, "POSITION_OWNER");
        assertGt(usdc.balanceOf(user) - beforeUSDCBalance, 0, "USDC_BALANCE");
        assertLt(beforeETHBalance - user.balance, 0.26 ether, "NATIVE_BALANCE");
        assertEq(beforeWETHBalance, weth.balanceOf(user), "WETH_BALANCE");
        assertEq(loanPosition.expiredWith, EpochLibrary.current(), "POSITION_EXPIRE_EPOCH");
        assertEq(
            loanPosition.collateralAmount,
            collateralAmount + beforePositionCollateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(loanPosition.debtAmount, debtAmount + beforePositionDebtAmount, "POSITION_DEBT_AMOUNT");
        assertEq(loanPosition.collateralToken, waweth, "POSITION_COLLATERAL_TOKEN");
        assertEq(loanPosition.debtToken, wausdc, "POSITION_DEBT_TOKEN");
    }

    function testRepayWithCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(500);
        uint256 debtAmount = 0.86 ether;

        IBorrowControllerV2.SwapParams memory swapParams;
        swapParams.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000801f447c4595e16b000068d00019b57DcA972Db5D8866c630554AcdbDfE58b2659c00000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010803020801b9269d0f2801010102011dc097350301010103010019011fe3097c0b010104010001240149360b0101050100012fba5f510b0101060100000b0101070100ff0000000000000000000000000000000000000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab1db86e7fe4074e3c29d2fd0ed1d104c00e11a196b4ef385d20247f5d0f9cd2e3f716b9a55e71df9347fcdc35463e3770c2fb992716cd070b63540b947f6416e1ed89a3abca179f971b30555eb2234f30c6c9ab1c1dc392b53f9fb2ea6d9dace5f99efdc480000000000000000000000000000000000000000"
            )
        );
        swapParams.amount = usdc.amount(500);
        swapParams.inSubstitute = address(wausdc);

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            debtAmount,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertLe(afterLoanPosition.debtAmount, debtAmount, "POSITION_DEBT_AMOUNT");
        assertGe(afterLoanPosition.debtAmount, 0.7 ether, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepayAllWithCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 0.14 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(500);

        IBorrowControllerV2.SwapParams memory swapParams;
        swapParams.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000801f447c4595e16b000068d00019b57DcA972Db5D8866c630554AcdbDfE58b2659c00000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010803020801b9269d0f2801010102011dc097350301010103010019011fe3097c0b010104010001240149360b0101050100012fba5f510b0101060100000b0101070100ff0000000000000000000000000000000000000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab1db86e7fe4074e3c29d2fd0ed1d104c00e11a196b4ef385d20247f5d0f9cd2e3f716b9a55e71df9347fcdc35463e3770c2fb992716cd070b63540b947f6416e1ed89a3abca179f971b30555eb2234f30c6c9ab1c1dc392b53f9fb2ea6d9dace5f99efdc480000000000000000000000000000000000000000"
            )
        );
        swapParams.amount = usdc.amount(500);
        swapParams.inSubstitute = address(wausdc);

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            0,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(Epoch.wrap(649), afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - usdc.amount(500),
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertEq(afterLoanPosition.debtAmount, 0, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testRepayWithLeftCollateral() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);

        uint256 beforeUSDCBalance = usdc.balanceOf(user);
        uint256 beforeETHBalance = user.balance;
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        uint256 collateralAmount = usdc.amount(5000);
        uint256 maxDebtAmount = 0.86 ether;

        IBorrowControllerV2.SwapParams memory swapParams;
        swapParams.data = fromHex(
            string.concat(
                "83bd37f9000a000b041dcd65000801f447c4595e16b000068d00019b57DcA972Db5D8866c630554AcdbDfE58b2659c00000001",
                this.remove0x(Strings.toHexString(address(borrowController))),
                "000000010803020801b9269d0f2801010102011dc097350301010103010019011fe3097c0b010104010001240149360b0101050100012fba5f510b0101060100000b0101070100ff0000000000000000000000000000000000000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583182af49447d8a07e3bd95bd0d56f35241523fbab1db86e7fe4074e3c29d2fd0ed1d104c00e11a196b4ef385d20247f5d0f9cd2e3f716b9a55e71df9347fcdc35463e3770c2fb992716cd070b63540b947f6416e1ed89a3abca179f971b30555eb2234f30c6c9ab1c1dc392b53f9fb2ea6d9dace5f99efdc480000000000000000000000000000000000000000"
            )
        );
        swapParams.amount = usdc.amount(500);
        swapParams.inSubstitute = address(wausdc);

        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        vm.prank(user);
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            maxDebtAmount,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
            permit721Params,
            emptyERC20PermitParams,
            emptyERC20PermitParams
        );

        LoanPosition memory afterLoanPosition = loanPositionManager.getPosition(positionId);

        assertEq(usdc.balanceOf(user), beforeUSDCBalance + collateralAmount - swapParams.amount, "USDC_BALANCE");
        assertGe(user.balance, beforeETHBalance, "NATIVE_BALANCE");
        assertEq(beforeLoanPosition.expiredWith, afterLoanPosition.expiredWith, "POSITION_EXPIRE_EPOCH");
        assertEq(
            beforeLoanPosition.collateralAmount - collateralAmount,
            afterLoanPosition.collateralAmount,
            "POSITION_COLLATERAL_AMOUNT"
        );
        assertLe(afterLoanPosition.debtAmount, maxDebtAmount, "POSITION_DEBT_AMOUNT");
        assertGe(afterLoanPosition.debtAmount, 0.7 ether, "POSITION_DEBT_AMOUNT");
        assertEq(beforeLoanPosition.collateralToken, afterLoanPosition.collateralToken, "POSITION_COLLATERAL_TOKEN");
        assertEq(beforeLoanPosition.debtToken, afterLoanPosition.debtToken, "POSITION_DEBT_TOKEN");
    }

    function testExpiredBorrowMore() public {
        uint256 positionId = _initialBorrow(user, wausdc, waweth, usdc.amount(10000), 1 ether, 2);
        LoanPosition memory beforeLoanPosition = loanPositionManager.getPosition(positionId);
        // loan duration is 2 epochs
        vm.warp(EpochLibrary.current().add(2).startTime());
        PermitSignature memory permit721Params =
            vm.signPermit(1, loanPositionManager, address(borrowController), positionId);

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILoanPositionManagerTypes.FullRepaymentRequired.selector));
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount,
            beforeLoanPosition.debtAmount + 0.5 ether,
            type(int256).max,
            beforeLoanPosition.expiredWith,
            swapParams,
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

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ILoanPositionManagerTypes.FullRepaymentRequired.selector));
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            beforeLoanPosition.debtAmount,
            0,
            beforeLoanPosition.expiredWith,
            swapParams,
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

        IBorrowControllerV2.SwapParams memory swapParams;
        vm.expectRevert(abi.encodeWithSelector(IControllerV2.InvalidAccess.selector));
        borrowController.adjust(
            positionId,
            beforeLoanPosition.collateralAmount - collateralAmount,
            beforeLoanPosition.debtAmount,
            type(int256).max,
            beforeLoanPosition.expiredWith,
            swapParams,
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
