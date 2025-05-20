// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../ERC20/ERC20.sol";
import "../ERC20/utils/SafeERC20.sol";
import "../../utils/AccessControl.sol";
import "../../utils/ReentrancyGuard.sol";
import "../../utils/Ownable.sol";

/**
 * @title FexseTokenVesting
 * @dev A contract that manages vesting schedules for FEXSE tokens with
 * different categories having unique cliff and vesting parameters
 */
contract FexseTokenVesting is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // FEXSE token contract
    IERC20 public fexseToken;

    // Vesting category IDs
    enum VestingCategory {
        DEVELOPMENT_RND,
        OPERATIONS_MARKETING,
        PRIVATE_PUBLIC_SALES,
        TREASURE,
        COMMUNITY,
        TEAM_FOUNDERS,
        FEX_FOUNDATION,
        CONSULTANTS_STRATEGIC,
        LIQUIDITY_POOLS,
        PRE_SALE,
        AIRDROP
    }

    // Structure to store vesting schedule information
    struct VestingSchedule {
        uint256 totalAmount;      // Total tokens allocated
        uint256 cliffMonths;      // Cliff duration in months
        uint256 vestingMonths;    // Vesting duration in months
        uint256 startTime;        // Timestamp when vesting starts
        uint256 releasedAmount;   // Amount already released
        bool initialized;         // Whether this schedule is initialized
    }

    // Map category to vesting schedule
    mapping(VestingCategory => VestingSchedule) public vestingSchedules;
    
    // Map category to beneficiaries
    mapping(VestingCategory => address[]) public categoryBeneficiaries;
    
    // Map category and beneficiary to allocation
    mapping(VestingCategory => mapping(address => uint256)) public beneficiaryAllocations;
    
    // Map beneficiary to released tokens per category
    mapping(VestingCategory => mapping(address => uint256)) public beneficiaryReleased;

    // Events
    event VestingScheduleCreated(VestingCategory indexed category, uint256 totalAmount, uint256 cliffMonths, uint256 vestingMonths, uint256 startTime);
    event BeneficiaryAdded(VestingCategory indexed category, address indexed beneficiary, uint256 allocation);
    event TokensReleased(VestingCategory indexed category, address indexed beneficiary, uint256 amount);
    event EmergencyWithdraw(address indexed owner, uint256 amount);

    /**
     * @dev Constructor
     * @param _fexseToken Address of the FEXSE token contract
     */
    constructor(address _fexseToken) {
        require(_fexseToken != address(0), "FexseTokenVesting: token is zero address");
        fexseToken = IERC20(_fexseToken);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    /**
     * @dev Initialize all vesting schedules based on the whitepaper distribution
     * @param _startTime Timestamp when vesting starts
     */
    function initializeVestingSchedules(uint256 _startTime) external onlyRole(OWNER_ROLE) {
        require(_startTime >= block.timestamp, "FexseTokenVesting: start time is before current time");
        
        // Development and R&D: 10%, 270,000,000 tokens, no cliff, 60 months vesting
        _createVestingSchedule(
            VestingCategory.DEVELOPMENT_RND,
            270_000_000 * 10**18,  
            0,                     
            60,                    
            _startTime
        );

        // Operations & Marketing: 10%, 270,000,000 tokens, no cliff, 60 months vesting
        _createVestingSchedule(
            VestingCategory.OPERATIONS_MARKETING,
            270_000_000 * 10**18,
            0,
            60,
            _startTime
        );
        
        // Private & Public Sales: 20%, 540,000,000 tokens, 2 months cliff, 12 months vesting
        _createVestingSchedule(
            VestingCategory.PRIVATE_PUBLIC_SALES,
            540_000_000 * 10**18,
            2,
            12,
            _startTime
        );
        
        // Treasure: 25%, 675,000,000 tokens, 2 months cliff, 18 months vesting
        _createVestingSchedule(
            VestingCategory.TREASURE,
            675_000_000 * 10**18,
            2,
            18,
            _startTime
        );
        
        // Community: 5%, 135,000,000 tokens, 2 months cliff, 24 months vesting
        _createVestingSchedule(
            VestingCategory.COMMUNITY,
            135_000_000 * 10**18,
            2,
            24,
            _startTime
        );
        
        // Team & Founders: 10%, 270,000,000 tokens, 12 months cliff, 24 months vesting
        _createVestingSchedule(
            VestingCategory.TEAM_FOUNDERS,
            270_000_000 * 10**18,
            12,
            24,
            _startTime
        );
        
        // Fex Foundation: 5%, 135,000,000 tokens, 3 months cliff, 12 months vesting
        _createVestingSchedule(
            VestingCategory.FEX_FOUNDATION,
            135_000_000 * 10**18,
            3,
            12,
            _startTime
        );
        
        // Consultants & Strategic Partnerships: 5%, 135,000,000 tokens, 3 months cliff, 12 months vesting
        _createVestingSchedule(
            VestingCategory.CONSULTANTS_STRATEGIC,
            135_000_000 * 10**18,
            3,
            12,
            _startTime
        );
        
        // Liquidity Pools: 5%, 135,000,000 tokens, no cliff, 2 months vesting
        _createVestingSchedule(
            VestingCategory.LIQUIDITY_POOLS,
            135_000_000 * 10**18,
            0,
            2,
            _startTime
        );
        
        // Pre-Sale: 3%, 81,000,000 tokens, 6 months cliff, 6 months vesting
        _createVestingSchedule(
            VestingCategory.PRE_SALE,
            81_000_000 * 10**18,
            6,
            6,
            _startTime
        );
        
        // Airdrop: 2%, 54,000,000 tokens, 2 months cliff, 3 months vesting
        _createVestingSchedule(
            VestingCategory.AIRDROP,
            54_000_000 * 10**18,
            2,
            3,
            _startTime
        );
    }

    /**
     * @dev Internal function to create a vesting schedule
     */
    function _createVestingSchedule(
        VestingCategory _category,
        uint256 _totalAmount,
        uint256 _cliffMonths,
        uint256 _vestingMonths,
        uint256 _startTime
    ) internal {
        require(!vestingSchedules[_category].initialized, "FexseTokenVesting: schedule already initialized");
        require(_vestingMonths > 0, "FexseTokenVesting: vesting duration must be > 0");
        
        vestingSchedules[_category] = VestingSchedule({
            totalAmount: _totalAmount,
            cliffMonths: _cliffMonths,
            vestingMonths: _vestingMonths,
            startTime: _startTime,
            releasedAmount: 0,
            initialized: true
        });
        
        emit VestingScheduleCreated(_category, _totalAmount, _cliffMonths, _vestingMonths, _startTime);
    }
    
    /**
     * @dev Add a beneficiary to a vesting category with a specific allocation
     * @param _category Vesting category
     * @param _beneficiary Address of the beneficiary
     * @param _allocation Token amount allocated to the beneficiary
     */
    function addBeneficiary(
        VestingCategory _category, 
        address _beneficiary, 
        uint256 _allocation
    ) public onlyRole(OPERATOR_ROLE) {
        require(vestingSchedules[_category].initialized, "FexseTokenVesting: schedule not initialized");
        require(_beneficiary != address(0), "FexseTokenVesting: beneficiary is zero address");
        require(_allocation > 0, "FexseTokenVesting: allocation must be > 0");
        require(beneficiaryAllocations[_category][_beneficiary] == 0, "FexseTokenVesting: beneficiary already exists");
        
        // Check that total allocations do not exceed the total amount for the category
        uint256 totalAllocated = getTotalAllocatedForCategory(_category);
        require(totalAllocated + _allocation <= vestingSchedules[_category].totalAmount, 
                "FexseTokenVesting: allocation exceeds available amount");
        
        beneficiaryAllocations[_category][_beneficiary] = _allocation;
        categoryBeneficiaries[_category].push(_beneficiary);
        
        emit BeneficiaryAdded(_category, _beneficiary, _allocation);
    }
    
    /**
     * @dev Add multiple beneficiaries to a vesting category with specific allocations
     */
    function addMultipleBeneficiaries(
        VestingCategory _category, 
        address[] calldata _beneficiaries, 
        uint256[] calldata _allocations
    ) external onlyRole(OPERATOR_ROLE) {
        require(_beneficiaries.length == _allocations.length, "FexseTokenVesting: arrays length mismatch");
        
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            addBeneficiary(_category, _beneficiaries[i], _allocations[i]);
        }
    }
    
    /**
     * @dev Get the total amount allocated for a specific category
     */
    function getTotalAllocatedForCategory(VestingCategory _category) public view returns (uint256) {
        address[] memory beneficiaries = categoryBeneficiaries[_category];
        uint256 total = 0;
        
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            total = total + beneficiaryAllocations[_category][beneficiaries[i]];
        }
        
        return total;
    }
    
    /**
     * @dev Calculate vested tokens for a specific beneficiary in a category
     * @param _category The vesting category
     * @param _beneficiary The beneficiary address
     * @return The amount of tokens vested
     */
    function calculateVestedAmount(
        VestingCategory _category, 
        address _beneficiary
    ) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[_category];
        require(schedule.initialized, "FexseTokenVesting: schedule not initialized");
        
        uint256 allocation = beneficiaryAllocations[_category][_beneficiary];
        if (allocation == 0) {
            return 0;
        }
        
        if (block.timestamp < schedule.startTime + schedule.cliffMonths * 30 days) {
            return 0;
        }
        
        if (block.timestamp >= schedule.startTime + (schedule.cliffMonths + schedule.vestingMonths) * 30 days) {
            return allocation;
        }
        
        uint256 timeFromCliff = block.timestamp - (schedule.startTime + schedule.cliffMonths * 30 days);
        uint256 vestingDuration = schedule.vestingMonths * 30 days;
        
        return (allocation * timeFromCliff) / vestingDuration;
    }
    
    /**
     * @dev Release vested tokens for a beneficiary
     * @param _category The vesting category
     */
    function release(VestingCategory _category) external nonReentrant {
        address beneficiary = msg.sender;
        uint256 allocation = beneficiaryAllocations[_category][beneficiary];
        require(allocation > 0, "FexseTokenVesting: no allocation for beneficiary");
        
        uint256 vestedAmount = calculateVestedAmount(_category, beneficiary);
        uint256 releasedAmount = beneficiaryReleased[_category][beneficiary];
        
        uint256 releasable = vestedAmount - releasedAmount;
        require(releasable > 0, "FexseTokenVesting: no tokens are due");
        
        beneficiaryReleased[_category][beneficiary] = beneficiaryReleased[_category][beneficiary] + releasable;
        vestingSchedules[_category].releasedAmount = vestingSchedules[_category].releasedAmount + releasable;
        
        fexseToken.safeTransfer(beneficiary, releasable);
        
        emit TokensReleased(_category, beneficiary, releasable);
    }
    
    /**
     * @dev Release vested tokens for a beneficiary by the contract owner
     * @param _category The vesting category
     * @param _beneficiary The beneficiary address
     */
    function releaseByOwner(
        VestingCategory _category, 
        address _beneficiary
    ) external onlyRole(OPERATOR_ROLE) nonReentrant {
        uint256 allocation = beneficiaryAllocations[_category][_beneficiary];
        require(allocation > 0, "FexseTokenVesting: no allocation for beneficiary");
        
        uint256 vestedAmount = calculateVestedAmount(_category, _beneficiary);
        uint256 releasedAmount = beneficiaryReleased[_category][_beneficiary];
        
        uint256 releasable = vestedAmount - releasedAmount;
        require(releasable > 0, "FexseTokenVesting: no tokens are due");
        
        beneficiaryReleased[_category][_beneficiary] = beneficiaryReleased[_category][_beneficiary] + releasable;
        vestingSchedules[_category].releasedAmount = vestingSchedules[_category].releasedAmount + releasable;
        
        fexseToken.safeTransfer(_beneficiary, releasable);
        
        emit TokensReleased(_category, _beneficiary, releasable);
    }
    
    /**
     * @dev Get information about a beneficiary's vesting status
     */
    function getBeneficiaryInfo(
        VestingCategory _category, 
        address _beneficiary
    ) external view returns (
        uint256 totalAllocation,
        uint256 vestedAmount,
        uint256 releasedAmount,
        uint256 releasableAmount
    ) {
        totalAllocation = beneficiaryAllocations[_category][_beneficiary];
        vestedAmount = calculateVestedAmount(_category, _beneficiary);
        releasedAmount = beneficiaryReleased[_category][_beneficiary];
        releasableAmount = vestedAmount > releasedAmount ? vestedAmount - releasedAmount : 0;
    }
    
    /**
     * @dev Get the list of all beneficiaries for a category
     */
    function getCategoryBeneficiaries(VestingCategory _category) external view returns (address[] memory) {
        return categoryBeneficiaries[_category];
    }
    
    /**
     * @dev Get summary information for a vesting category
     */
    function getCategorySummary(VestingCategory _category) external view returns (
        uint256 totalAmount,
        uint256 totalAllocated,
        uint256 totalReleased,
        uint256 cliffMonths,
        uint256 vestingMonths,
        uint256 startTime,
        bool initialized
    ) {
        VestingSchedule memory schedule = vestingSchedules[_category];
        totalAmount = schedule.totalAmount;
        totalAllocated = getTotalAllocatedForCategory(_category);
        totalReleased = schedule.releasedAmount;
        cliffMonths = schedule.cliffMonths;
        vestingMonths = schedule.vestingMonths;
        startTime = schedule.startTime;
        initialized = schedule.initialized;
    }
    
    /**
     * @dev Emergency withdraw function - can only withdraw tokens not allocated to beneficiaries
     * @param _amount The amount to withdraw
     */
    function emergencyWithdraw(uint256 _amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 totalAllocated = 0;
        
       for (uint256 i = 0; i <= uint256(type(VestingCategory).max); i++) { 
            VestingCategory category = VestingCategory(i);
            if (vestingSchedules[category].initialized) {
                totalAllocated = totalAllocated + (vestingSchedules[category].totalAmount);
            }
        }
        
        uint256 contractBalance = fexseToken.balanceOf(address(this));
        uint256 withdrawable = contractBalance > totalAllocated ? contractBalance - totalAllocated : 0;
        
        require(_amount <= withdrawable, "FexseTokenVesting: cannot withdraw allocated tokens");
        require(_amount > 0, "FexseTokenVesting: amount must be > 0");
        
        fexseToken.safeTransfer(msg.sender, _amount);
        
        emit EmergencyWithdraw(msg.sender, _amount);
    }

    function grantOperatorRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _grantRole(OPERATOR_ROLE, account);
    }

    function grantOwnerRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(OWNER_ROLE, account);
    }
}