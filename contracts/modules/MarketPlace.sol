// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
/**
 * @file MarketPlace.sol
 * @dev This file contains the implementation of the MarketPlace contract.
 *
 * Imports:
 * - ModularInternal: Provides internal modular functionality.
 * - Strings: Utility library for string operations.
 * - AssetToken: Token contract for asset tokens.
 * - IAssetToken: Interface for the AssetToken contract.
 * - IMarketPlace: Interface for the MarketPlace contract.
 * - console: Hardhat console for debugging.
 */

import "../core/abstracts/ModularInternal.sol";
import "../utils/Strings.sol";
import "../interfaces/IPriceFetcher.sol";
import {AssetToken} from "../token/AssetToken.sol";
import {IAssetToken} from "../interfaces/IAssetToken.sol";
import {IMarketPlace} from "../interfaces/IMarketPlace.sol";
import {SafeERC20} from "../token/ERC20/utils/SafeERC20.sol";

/**
 * @title MarketPlace
 * @dev This contract is a module that extends the ModularInternal contract.
 * It is part of the RWATokenization project and is located at /c:/Users/duran/RWATokenization/contracts/modules/MarketPlace.sol.
 */
contract MarketPlace is ModularInternal {
    using AppStorage for AppStorage.Layout;

    // Mapping to store assets by ID
    mapping(uint256 => Asset) public assets;

    event TransferExecuted(
        uint256 orderId,
        address seller,
        address buyer,
        uint256 assetId,
        uint256 tokenAmount,
        uint256 amount,
        address salecurrency
    );

    address immutable _this;
    address public immutable usdtToken;

    /**
     * @dev Constructor for the MarketPlace contract.
     * Grants the ADMIN_ROLE to the deployer of the contract and the specified appAddress.
     *
     * @param appAddress The address to be granted the ADMIN_ROLE.
     */
    constructor(address appAddress, address _usdtToken) {
        _this = address(this);
        usdtToken = _usdtToken;
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, appAddress);
    }

    /**
     * @dev Returns an array of ⁠ FacetCut ⁠ structs, which define the functions (selectors)
     *      provided by this module. This is used to register the module's functions
     *      with the modular system.
     * @return FacetCut[] Array of ⁠ FacetCut ⁠ structs representing function selectors.
     */
    function moduleFacets() external view returns (FacetCut[] memory) {
        uint256 selectorIndex = 0;
        bytes4[] memory selectors = new bytes4[](2);

        // Add function selectors to the array
        selectors[selectorIndex++] = this.transferAsset.selector;
        selectors[selectorIndex++] = this.calculateGasFee.selector;

        // Create a FacetCut array with a single element
        FacetCut[] memory facetCuts = new FacetCut[](1);

        // Set the facetCut target, action, and selectors
        facetCuts[0] = FacetCut({
            target: _this,
            action: FacetCutAction.ADD,
            selectors: selectors
        });
        return facetCuts;
    }

    /**
     * @notice Transfers an asset from the seller to the buyer.
     * @dev This function can only be called by an account with the ADMIN_ROLE.
     * It ensures that the seller and buyer addresses are valid, and that the token amount and price are greater than zero.
     * It checks the FEXSE token allowance and balance of the buyer, and the asset token approval and balance of the seller.
     * It then transfers the FEXSE tokens from the buyer to the seller, and the asset tokens from the seller to the buyer.
     * Finally, it updates the asset's user token information and emits a TransferExecuted event.
     * @param seller The address of the asset seller.
     * @param buyer The address of the asset buyer.
     * @param assetId The ID of the asset being transferred.
     * @param tokenAmount The amount of asset tokens being transferred.
     * @param tokenPrice The price of each asset token in FEXSE tokens.
     */
    function transferAsset(
        uint256 orderId,
        address seller,
        address buyer,
        uint256 assetId,
        uint256 tokenAmount,
        uint256 tokenPrice,
        address saleCurrency
    ) external nonReentrant onlyRole(ADMIN_ROLE) {
        uint256 gasBefore = gasleft();

        _validateTransferParameters(
            seller,
            buyer,
            assetId,
            tokenAmount,
            tokenPrice,
            saleCurrency
        );

        AppStorage.Layout storage data = AppStorage.layout();
        Asset storage asset = data.assets[assetId];

        uint256 amount = tokenPrice * tokenAmount;
        uint256 servideFeeAmount = (amount * 5) / 1000;

        require(
            IERC20(saleCurrency).allowance(buyer, address(this)) >=
                (amount + servideFeeAmount),
            "FEXSE allowance too low"
        );

        require(
            IAssetToken(asset.tokenContract).isApprovedForAll(
                seller,
                address(this)
            ) == true,
            "asset is not approved"
        );

        require(
            IERC20(saleCurrency).balanceOf(buyer) >= (amount + servideFeeAmount)
        );

        require(
            IAssetToken(asset.tokenContract).balanceOf(seller, assetId) >=
                tokenAmount,
            "sender does not have enough asset "
        );

        SafeERC20.safeTransferFrom(
            IERC20(saleCurrency),
            buyer,
            seller,
            (amount - servideFeeAmount)
        );

        IAssetToken(asset.tokenContract).safeTransferFrom(
            seller,
            buyer,
            assetId,
            tokenAmount,
            ""
        );

        emit TransferExecuted(
            orderId,
            seller,
            buyer,
            assetId,
            tokenAmount,
            amount,
            saleCurrency
        );

        uint256 gasUsed = gasBefore - gasleft(); 
        uint256 gasFee = calculateGasFee(saleCurrency, gasUsed);// approximate value of gas used in FEXSE tokens

        if (gasFee >= ((servideFeeAmount * 30) / 100)) {
            SafeERC20.safeTransferFrom(
                IERC20(saleCurrency),
                buyer,
                address(this),
                (servideFeeAmount * 2) + gasFee
            );
        } else {
            SafeERC20.safeTransferFrom(
                IERC20(saleCurrency),
                buyer,
                address(this),
                servideFeeAmount * 2
            );
        }
    }

    /**
     * @dev Calculates the gas fee in FEXSE tokens based on the gas used.
     * @param gasUsed The amount of gas used for the transaction.
     * @return The calculated gas fee in FEXSE tokens.
     */
    function calculateGasFee(
        address saleCurrency,
        uint256 gasUsed
    ) public view returns (uint256) {
        if (gasUsed == 0) return 0;
        
        uint256 gasPriceinUSDT = IPriceFetcher(address(this)).getGasPriceInUSDT(
            gasUsed
        );

        if (saleCurrency == usdtToken) {
            return gasPriceinUSDT;
        } else {
            uint256 gasFee = ((gasPriceinUSDT * 10 ** 18) / (45 * 10 ** 3));
            return gasFee;
        }
    }

   
    /**
     * @dev Validates the parameters for a token transfer.
     * @param seller The address of the seller.
     * @param buyer The address of the buyer.
     * @param assetId The ID of the asset being transferred.
     * @param tokenAmount The amount of tokens being transferred.
     * @param tokenPrice The price of the tokens being transferred.
     * @param saleCurrency The currency used for the sale.
     * @notice This function checks that the seller and buyer addresses are valid and not the same,
     *         the token amount and price are greater than zero, the token price is within the allowed range,
     *         the sale currency is valid, and neither the seller nor the buyer are blacklisted.
     * @dev The seller address must not be the zero address.
     * @dev The buyer address must not be the zero address.
     * @dev The seller and buyer must not be the same address.
     * @dev The token amount must be greater than zero.
     * @dev The token price must be greater than zero.
     * @dev The token price must be within 80% to 120% of the asset's current price.
     * @dev The sale currency must be either USDT or the platform's token.
     * @dev The seller must not be blacklisted.
     * @dev The buyer must not be blacklisted.
     */
    function _validateTransferParameters(
        address seller,
        address buyer,
        uint256 assetId,
        uint256 tokenAmount,
        uint256 tokenPrice,
        address saleCurrency
    ) private view {
        require(seller != address(0), "Invalid seller address");
        require(buyer != address(0), "Invalid buyer address");
        require(seller != buyer, "Seller and buyer cannot be the same");
        require(tokenAmount > 0, "Token amount must be greater than zero");
        require(tokenPrice > 0, "Token price must be greater than zero");

        AppStorage.Layout storage data = AppStorage.layout();
        Asset storage asset = data.assets[assetId];

        // Fiyat aralığı kontrolü
        uint256 minPrice = (asset.tokenPrice * 80) / 100;
        uint256 maxPrice = (asset.tokenPrice * 120) / 100;
        require(
            tokenPrice >= minPrice && tokenPrice <= maxPrice,
            "Token price out of allowed range"
        );

        // Geçerli para birimi kontrolü
        require(
            saleCurrency == usdtToken ||
                saleCurrency == address(data.fexseToken),
            "Invalid sale currency"
        );

        // Kara liste kontrolü
        require(!data.isBlacklisted[seller], "Seller is blacklisted");
        require(!data.isBlacklisted[buyer], "Buyer is blacklisted");
    }
}
