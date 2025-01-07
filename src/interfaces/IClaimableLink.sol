// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";

interface IClaimableLink {
    // --------------------
    // --- Enumerations ---
    // --------------------

    enum DepositStatus {
        NotDepositedYet, // 0: No deposit made (default value)
        Deposited, // 1: Deposit completed
        Claimed, // 2: Deposit claimed
        Cancelled, // 3: Deposit cancelled
        Expired // 4: Deposit expired

    }

    // ------------------
    // --- Structures ---
    // ------------------

    struct Deposit {
        address token; // Token address
        uint64 expiration; // Expiration timestamp (seconds)
        uint256 amount; // Deposit amount
        DepositStatus depositStatus; // Current deposit status
    }

    // EIP-712
    struct DepositSig {
        address token;
        address transferID;
        uint256 amount;
        uint64 expiration;
    }

    struct ClaimSig {
        address token;
        address transferID;
        address recipient;
    }

    // ------------
    // -- Events --
    // ------------

    // Signer status update
    event SignerUpdated(address indexed signer, bool indexed isActivated);

    // Token deposited
    event Deposited(
        address indexed giver, address indexed token, address indexed transferID, uint256 amount, uint64 expiration
    );

    // Token claimed
    event Claimed(
        address indexed giver,
        address indexed token,
        address indexed transferID,
        uint256 amount,
        address recipient,
        address signer
    );

    // Deposit cancelled
    event Cancelled(address indexed giver, address indexed token, address indexed transferID);

    // Deposit refunded
    event Refunded(address indexed giver, address indexed token, address indexed transferID);

    // ------------
    // -- Errors --
    // ------------

    // Signer-related errors
    error InvalidSignerSignature(address signer);
    error SignerAlreadyActive(address signer);
    error SignerAlreadyDeactivated(address signer);
    error UnauthorizedSigner(address signer);
    error MismatchInInputLengths();

    // Deposit-related errors
    error DepositAlreadyMade(address giver, address token, address transferID);
    error DepositNotMade(address giver, address token, address transferID);
    error DepositTokenMismatch(address giver, address token, address transferID);
    error DepositSupportsERC20Only(address giver, address token, address transferID);
    // error InsufficientETH();
    error ETHAmountMismatch();

    // Claim-related errors
    error DepositNotClaimable(address giver, address token, address transferID);
    error DepositExpired(address giver, address token, address transferID);
    error InvalidGiverSignature(address giver);

    // Refund-related errors
    error DepositNotExpired(address giver, address token, address transferID);

    // General errors
    error ETHSendFailure(uint256 amount, address to);

    // -------------------
    // -- Get Functions --
    // -------------------

    // Check if signer is activated
    function isSignerActivated(address _signer) external view returns (bool _isActivated);

    // Retrieve deposit details
    function getDeposit(address _giver, address _token, address _transferID)
        external
        view
        returns (Deposit calldata _deposit);

    // Check if user can claim token
    function isClaimable(address _giver, address _token, address _transferID)
        external
        view
        returns (bool _isClaimable);

    // -------------------
    // -- Set Functions --
    // -------------------

    // Update signer list
    function updateSigners(address[] calldata _signerList, bool[] calldata _isActivatedList) external;

    // Deposit token
    function deposit(address _token, address _transferID, uint256 _amount, uint64 _expiration) external payable;

    // Claim token
    function claim(
        address _giver,
        address _token,
        address _transferID,
        address payable _recipient,
        bytes memory _signerSignature
    ) external;

    // Claim token with deposit signature
    function claimWithDepositSig(
        address _giver,
        address _token,
        address _transferID,
        address payable _recipient,
        uint256 _amount,
        uint64 _expiration,
        bytes calldata _giverDepositSignature,
        bytes calldata _signerSignature
    ) external;

    // Claim token with direct authorization signature
    function claimWithDirectAuth(
        address _giver,
        address _token,
        address _transferID,
        address payable _recipient,
        bytes calldata _giverSignature
    ) external;

    // Cancel deposit
    function cancel(address _token, address _transferID) external;

    // Refund deposit
    function refund(address payable _giver, address _token, address _transferID) external;
}
