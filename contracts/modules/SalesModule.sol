// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @file SalesModule.sol
 * @dev This file is part of the RWATokenization project and contains the SalesModule contract.
 *
 * Imports:
 * - ModularInternal: Abstract contract providing internal modular functionality.
 * - IERC20: Interface for the ERC20 standard as defined in the EIP.
 * - Strings: Utility library for string operations.
 * - IPriceFetcher: Interface for fetching price data.
 * - AssetToken: Contract representing an asset-backed token.
 * - IRWATokenization: Interface for the RWATokenization project.
 * - SafeERC20: Library for safe operations with ERC20 tokens.
 */
import "../core/abstracts/ModularInternal.sol";
import "../token/ERC20/IERC20.sol";
import "../utils/Strings.sol";
import "../interfaces/IPriceFetcher.sol";
import {AssetToken} from "../token/AssetToken.sol";
import {IRWATokenization} from "../interfaces/IRWATokenization.sol";
import {SafeERC20} from "../token/ERC20/utils/SafeERC20.sol";

/**
 * @title SalesModule
 * @dev This contract is a module for handling sales within the RWATokenization system.
 * It extends the ModularInternal contract to leverage modular functionalities.
 */
contract SalesModule is ModularInternal {
    using AppStorage for AppStorage.Layout;

    address public immutable usdtToken;

    // Event to log profit distribution
    event TokensSold(
        uint256 assetId,
        address buyer,
        uint256 totalTokens,
        uint256 tokenPrice
    );
    address immutable _this;

    /**
     * @dev Constructor function that initializes the contract.
     * Sets the contract's address to `_this` and grants the `ADMIN_ROLE` to the deployer of the contract.
     */
    constructor(address _usdtToken) {
        _this = address(this);
        _grantRole(ADMIN_ROLE, msg.sender);
        usdtToken = _usdtToken;
    }

    /**
     * @notice Returns an array of FacetCut structs representing the module facets.
     * @dev This function creates an array of function selectors and a FacetCut array with a single element.
     *      The FacetCut array is populated with the target, action, and selectors.
     * @return facetCuts An array of FacetCut structs.
     */
    function moduleFacets() external view returns (FacetCut[] memory) {
        uint256 selectorIndex = 0;
        bytes4[] memory selectors = new bytes4[](1);

        // Add function selectors to the array
        selectors[selectorIndex++] = this.buyFexse.selector;

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
     * @notice Allows a user to buy Fexse tokens using a specified sale currency (e.g., USDT).
     * @dev This function is non-reentrant.
     * @param tokenAmount The amount of Fexse tokens to buy.
     * @param saleCurrency The address of the ERC20 token used for the sale (e.g., USDT).
     * @dev The tokenAmount must be greater than 0.
     * @dev The buyer must have an allowance of the sale currency (USDT) that is at least equal to the required amount.
     * @dev The sender must have an allowance of Fexse tokens that is at least equal to the tokenAmount.
     * @dev The buyer must have a balance of the sale currency (USDT) that is at least equal to the required amount.
     * @dev The sender must have a balance of Fexse tokens that is at least equal to the tokenAmount.
     * @dev The transfer of the sale currency (USDT) from the buyer to the sender must succeed.
     * @dev The transfer of Fexse tokens from the sender to the buyer must succeed.
     */
    function buyFexse(
        uint256 tokenAmount,
        address saleCurrency
    ) external nonReentrant {
        AppStorage.Layout storage data = AppStorage.layout();

        // presale tokens should be usdt tokens only
        require(saleCurrency == usdtToken, "buyFexse: Invalid sale currency");
        require(tokenAmount > 10 ** 18, "You must buy at least 1 token");

        address buyer = msg.sender;

        require(!data.isBlacklisted[buyer], "Fexse buyer is in blacklist");

        address sender = data.deployer;

        //uint256 fexsePrice = IPriceFetcher(address(this)).getFexsePrice();

        uint256 usdtAmount = (tokenAmount * 45 * 10 ** 3) /
            10 ** 18; // Total USDT required

        // Check USDT and fexse allowance and balance
        require(
            IERC20(saleCurrency).allowance(buyer, address(this)) >= usdtAmount,
            "USDT allowance too low"
        );

        require(
            IERC20(data.fexseToken).allowance(sender, address(this)) >=
                tokenAmount,
            "Fexse allowance too low"
        );

        require(
            IERC20(saleCurrency).balanceOf(buyer) >= usdtAmount,
            "Insufficient USDT balance"
        );

        // Check if contract has enough tokens to sell
        require(
            IERC20(data.fexseToken).balanceOf(sender) >= tokenAmount,
            "Insufficient token balance in sender"
        );

        // Transfer USDT from buyer to contract
        SafeERC20.safeTransferFrom(
            IERC20(saleCurrency),
            buyer,
            sender,
            usdtAmount
        );

        // Transfer tokens from contract to buyer
        require(
            IERC20(data.fexseToken).transferFrom(sender, buyer, tokenAmount),
            "Token transfer failed"
        );
    }
}
