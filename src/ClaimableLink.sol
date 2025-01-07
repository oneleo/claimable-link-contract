// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@oz/utils/cryptography/ECDSA.sol";
import {Ownable2Step, Ownable} from "@oz/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@oz/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@oz/utils/structs/EnumerableSet.sol";
import {MessageHashUtils} from "@oz/utils/cryptography/MessageHashUtils.sol";
import {EIP712} from "@oz/utils/cryptography/EIP712.sol";

import {IClaimableLink} from "src/interfaces/IClaimableLink.sol";

contract ClaimableLink is
    IClaimableLink,
    Ownable2Step,
    ReentrancyGuard,
    EIP712
{
    using EnumerableSet for EnumerableSet.AddressSet;

    string private constant SIGNING_DOMAIN = "ClaimableLink";
    string private constant SIGNATURE_VERSION = "1";
    address private constant NATIVE_TOKEN_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // -----------------------
    // -- Private Variables --
    // -----------------------

    // Mapping to track activated signers
    mapping(address signer => bool isActivated) private _isActivatedSigner;

    // Mapping of deposits by giver, token, and transferID
    mapping(address giver => mapping(address token => mapping(address transferID => Deposit deposit)))
        private _deposits;

    // List of activated signers
    EnumerableSet.AddressSet private _signerSet;

    // -----------------
    // -- Constructor --
    // -----------------

    // Initializes the contract with admin and signers
    constructor(
        address _admin,
        address[] memory _signers
    ) Ownable(_admin) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        bool[] memory isActivatedList = new bool[](_signers.length);
        for (uint256 i = 0; i < _signers.length; i++) {
            isActivatedList[i] = true;
        }
        _updateSigners(_signers, isActivatedList);
    }

    // -------------------
    // -- Get Functions --
    // -------------------

    // Checks if a signer is activated
    function isSignerActivated(
        address _signer
    ) external view override returns (bool isActivated) {
        return _isActivatedSigner[_signer];
    }

    // Retrieves deposit details for a given giver, token, and transfer ID
    function getDeposit(
        address _giver,
        address _token,
        address _transferID
    ) external view override returns (Deposit memory) {
        return _deposits[_giver][_token][_transferID];
    }

    // Verifies if a deposit is claimable based on status and expiration
    function isClaimable(
        address _giver,
        address _token,
        address _transferID
    ) public view override returns (bool) {
        Deposit memory depositNote = _deposits[_giver][_token][_transferID];
        return
            depositNote.depositStatus == DepositStatus.Deposited &&
            depositNote.expiration >= uint64(block.timestamp);
    }

    // Retrieves the list of all signers
    function getSigners() external view returns (address[] memory) {
        return _signerSet.values();
    }

    // Generates claim hash based on input parameters
    function getClaimHash(
        address _giver,
        address _token,
        address _transferID,
        address _recipient
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_giver, _token, _transferID, _recipient));
    }

    // Retrieves the domain separator for EIP-712 hashing
    function getDomainSeparator() public view returns (bytes32) {
        return _domainSeparatorV4();
    }

    // EIP-712: Creates deposit hash for signing
    function getEIP712DepositHash(
        DepositSig memory _sig
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "DepositSig(address token,uint256 transferID,uint256 amount,uint64 expiration)"
                    ),
                    _sig.token,
                    _sig.transferID,
                    _sig.amount,
                    _sig.expiration
                )
            );
    }

    // EIP-712: Creates claim hash for signing
    function getEIP712ClaimHash(
        ClaimSig memory _sig
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "ClaimSig(address token,uint256 transferID,address recipient)"
                    ),
                    _sig.token,
                    _sig.transferID,
                    _sig.recipient
                )
            );
    }

    // -------------------
    // -- Set Functions --
    // -------------------

    // Updates the list of signers and their activation status
    function updateSigners(
        address[] calldata _signerList,
        bool[] calldata _isActivatedList
    ) external override onlyOwner {
        return _updateSigners(_signerList, _isActivatedList);
    }

    // Handles deposit of funds from the giver
    function deposit(
        address _token,
        address _transferID,
        uint256 _amount,
        uint64 _expiration
    ) external payable override nonReentrant {
        return
            _deposit(_msgSender(), _token, _transferID, _amount, _expiration);
    }

    // Handles claim of deposited funds
    function claim(
        address _giver,
        address _token,
        address _transferID,
        address payable _recipient,
        bytes memory _signerSignature
    ) external override nonReentrant {
        _claim(_giver, _token, _transferID, _recipient, _signerSignature);
    }

    // Handles claim with deposit signature
    function claimWithDepositSig(
        address _giver,
        address _token, // Does not support ETH transfer
        address _transferID,
        address payable _recipient,
        uint256 _amount,
        uint64 _expiration,
        bytes calldata _giverDepositSignature,
        bytes calldata _signerSignature
    ) external override nonReentrant {
        require(
            _token != NATIVE_TOKEN_ADDRESS,
            DepositSupportsERC20Only(_giver, _token, _transferID)
        );

        bytes32 eip712SignedDepositHash = _hashTypedDataV4(
            getEIP712DepositHash(
                DepositSig({
                    token: _token,
                    transferID: _transferID,
                    amount: _amount,
                    expiration: _expiration
                })
            )
        );
        require(
            _giver ==
                ECDSA.recover(eip712SignedDepositHash, _giverDepositSignature),
            InvalidGiverSignature(_giver)
        );

        _deposit(_giver, _token, _transferID, _amount, _expiration);

        return
            _claim(_giver, _token, _transferID, _recipient, _signerSignature);
    }

    // Handles claim with direct authorization
    function claimWithDirectAuth(
        address _giver,
        address _token,
        address _transferID,
        address payable _recipient,
        bytes calldata _giverSignature
    ) external override nonReentrant {
        require(
            isClaimable(_giver, _token, _transferID),
            DepositNotClaimable(_giver, _token, _transferID)
        );

        Deposit storage depositNote = _deposits[_giver][_token][_transferID];

        bytes32 eip712SignedClaimHash = _hashTypedDataV4(
            getEIP712ClaimHash(
                ClaimSig({
                    token: _token,
                    transferID: _transferID,
                    recipient: _recipient
                })
            )
        );
        require(
            _giver == ECDSA.recover(eip712SignedClaimHash, _giverSignature),
            InvalidGiverSignature(_giver)
        );

        depositNote.depositStatus = DepositStatus.Claimed;
        _claimToken(_token, _recipient, depositNote.amount);
        emit Claimed(
            _giver,
            _token,
            _transferID,
            depositNote.amount,
            _recipient,
            _giver
        );
    }

    // Cancels a deposit and returns the funds
    function cancel(
        address _token,
        address _transferID
    ) external override nonReentrant {
        Deposit storage depositNote = _deposits[_msgSender()][_token][
            _transferID
        ];

        if (depositNote.depositStatus == DepositStatus.NotDepositedYet) {
            depositNote.token = _token;
            depositNote.expiration = uint64(0);
            depositNote.amount = uint256(0);
            depositNote.depositStatus = DepositStatus.Cancelled;
        }

        if (depositNote.depositStatus == DepositStatus.Deposited) {
            depositNote.depositStatus = DepositStatus.Cancelled;
            _claimToken(_token, payable(_msgSender()), depositNote.amount);
        }

        emit Cancelled(_msgSender(), _token, _transferID);
    }

    // Refunds expired deposits to the giver
    function refund(
        address payable _giver,
        address _token,
        address _transferID
    ) external override nonReentrant {
        Deposit storage depositNote = _deposits[_giver][_token][_transferID];
        require(
            depositNote.depositStatus == DepositStatus.Deposited &&
                depositNote.expiration < uint64(block.timestamp),
            DepositNotExpired(_giver, _token, _transferID)
        );

        depositNote.depositStatus = DepositStatus.Expired;
        _claimToken(_token, _giver, depositNote.amount);

        emit Refunded(_giver, _token, _transferID);
    }

    // -----------------------
    // -- Private Functions --
    // -----------------------

    // Updates signers list
    function _updateSigners(
        address[] memory _signerList,
        bool[] memory _isActivatedList
    ) private {
        require(
            _signerList.length == _isActivatedList.length,
            MismatchInInputLengths()
        );

        for (uint256 i = 0; i < _signerList.length; i++) {
            address signer = _signerList[i];

            require(signer != address(0), InvalidSignerSignature(signer));

            bool isActivatedSigner = _isActivatedList[i];

            if (isActivatedSigner == _isActivatedSigner[signer]) {
                if (isActivatedSigner) {
                    revert SignerAlreadyActive(signer);
                } else {
                    revert SignerAlreadyDeactivated(signer);
                }
            }

            if (isActivatedSigner) {
                _signerSet.add(signer);
            } else {
                _signerSet.remove(signer);
            }

            _isActivatedSigner[signer] = isActivatedSigner;

            emit SignerUpdated(signer, isActivatedSigner);
        }
    }

    // Handles deposits: ETH or ERC20 tokens
    function _deposit(
        address _giver,
        address _token,
        address _transferID,
        uint256 _amount,
        uint64 _expiration
    ) private {
        Deposit storage depositNote = _deposits[_giver][_token][_transferID];

        require(
            depositNote.depositStatus == DepositStatus.NotDepositedYet,
            DepositAlreadyMade(_giver, _token, _transferID)
        );

        if (_token == NATIVE_TOKEN_ADDRESS) {
            // Deposit ETH
            require(msg.value == _amount, ETHAmountMismatch());
        }

        if (_token != NATIVE_TOKEN_ADDRESS) {
            // Deposit ERC20 token
            require(
                msg.value == 0,
                DepositTokenMismatch(_giver, _token, _transferID)
            );

            SafeERC20.safeTransferFrom(
                IERC20(_token),
                _giver,
                address(this),
                _amount
            );
        }

        depositNote.token = _token;
        depositNote.expiration = _expiration;
        depositNote.amount = _amount;
        depositNote.depositStatus = DepositStatus.Deposited;

        emit Deposited(_giver, _token, _transferID, _amount, _expiration);
    }

    // Handles claims
    function _claim(
        address _giver,
        address _token,
        address _transferID,
        address payable _recipient,
        bytes memory _signerSignature
    ) private {
        require(
            isClaimable(_giver, _token, _transferID),
            DepositNotClaimable(_giver, _token, _transferID)
        );

        Deposit storage depositNote = _deposits[_giver][_token][_transferID];

        bytes32 claimHash = getClaimHash(
            _giver,
            _token,
            _transferID,
            _recipient
        );
        bytes32 ethSignedClaimHash = MessageHashUtils.toEthSignedMessageHash(
            claimHash
        );
        address signer = ECDSA.recover(ethSignedClaimHash, _signerSignature);
        require(_isActivatedSigner[signer], InvalidSignerSignature(signer));

        depositNote.depositStatus = DepositStatus.Claimed;

        _claimToken(_token, _recipient, depositNote.amount);

        emit Claimed(
            _giver,
            _token,
            _transferID,
            depositNote.amount,
            _recipient,
            signer
        );
    }

    // Claims the token
    function _claimToken(
        address _token,
        address payable _recipient,
        uint256 _amount
    ) private {
        if (_token == NATIVE_TOKEN_ADDRESS) {
            // Send ETH
            return _transferETH(_amount, _recipient);
        }

        if (_token != NATIVE_TOKEN_ADDRESS) {
            // Send ERC20 token
            return SafeERC20.safeTransfer(IERC20(_token), _recipient, _amount);
        }
    }

    // Transfers ETH
    function _transferETH(uint256 _amount, address payable _recipient) private {
        (bool success, ) = _recipient.call{value: _amount}("");
        require(success, ETHSendFailure(_amount, _recipient));
    }
}
