// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {ECDSA} from "@oz/utils/cryptography/ECDSA.sol";
import {Ownable2Step, Ownable} from "@oz/access/Ownable2Step.sol";
import {ERC20} from "@oz/token/ERC20/ERC20.sol";
import {IERC20} from "@oz/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@oz/interfaces/draft-IERC6093.sol";
import {MessageHashUtils} from "@oz/utils/cryptography/MessageHashUtils.sol";

import {ClaimableLink} from "src/ClaimableLink.sol";
import {IClaimableLink} from "src/interfaces/IClaimableLink.sol";

contract MockMintableToken is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ClaimableLinkTest is Test {
    address private constant NATIVE_TOKEN_ADDRESS =
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    ClaimableLink private claimableLink;
    MockMintableToken private mintableToken;

    address contractAddress;
    address tokenAddress;

    address admin;
    uint256 adminKey;
    address signer;
    uint256 signerKey;
    address other;
    uint256 otherKey;
    address giver;
    uint256 giverKey;

    address recipient;
    address transferID;

    function setUp() public {
        (admin, adminKey) = makeAddrAndKey("admin");
        (signer, signerKey) = makeAddrAndKey("signer");
        (other, otherKey) = makeAddrAndKey("other");
        (giver, giverKey) = makeAddrAndKey("giver");

        recipient = makeAddr("recipient");
        transferID = makeAddr("transferID");

        address[] memory signers = new address[](1);
        signers[0] = signer;

        claimableLink = new ClaimableLink(admin, signers);
        mintableToken = new MockMintableToken("MockMintableToken", "MMT");

        contractAddress = address(claimableLink);
        tokenAddress = address(mintableToken);

        vm.deal(address(this), 1000 ether);
        vm.deal(address(giver), 1000 ether);
        mintableToken.mint(address(giver), 1000e18);
    }

    // ---------------------------
    // -- Test: updateSigners() --
    // ---------------------------

    function testUpdateSignerByAdmin() public {
        // Set up signers and activation statuses
        address[] memory signers = new address[](2);
        signers[0] = makeAddr("signers[0]");
        signers[1] = makeAddr("signers[1]");

        bool[] memory isActivated = new bool[](2);
        isActivated[0] = true;
        isActivated[1] = true;

        // Expect SignerUpdated() event emission
        vm.expectEmit(true, true, false, false, contractAddress);
        emit IClaimableLink.SignerUpdated(signers[0], true);

        // Expect SignerUpdated() event emission
        vm.expectEmit(true, true, false, false, contractAddress);
        emit IClaimableLink.SignerUpdated(signers[1], true);

        // Execute updateSigners() via admin account
        vm.startPrank(admin);
        claimableLink.updateSigners(signers, isActivated);
        vm.stopPrank();

        // Check if the signers are activated
        assertEq(claimableLink.isSignerActivated(signers[0]), true);
        assertEq(claimableLink.isSignerActivated(signers[1]), true);

        // Check the signers in storage
        assertEq(claimableLink.getSigners().length, 3);
        assertEq(claimableLink.getSigners()[0], signer);
        assertEq(claimableLink.getSigners()[1], signers[0]);
        assertEq(claimableLink.getSigners()[2], signers[1]);
    }

    // ---------------------
    // -- Test: deposit() --
    // ---------------------

    function testDepositInETH() public {
        // Set reused variables
        uint256 ethAmount = 1 ether;
        uint64 depositExpiration = uint64(block.timestamp + 1 days);

        // Get giver and claimableLink contract ETH balances before deposit()
        uint256 giverETHBalanceBefore = giver.balance;
        uint256 contractETHBalanceBefore = contractAddress.balance;

        // Check the deposit note status before deposit()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore ==
                IClaimableLink.DepositStatus.NotDepositedYet,
            true
        );

        // Expect Deposited() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Deposited(
            giver,
            NATIVE_TOKEN_ADDRESS,
            transferID,
            ethAmount,
            depositExpiration
        );

        // Execute deposit() via giver account
        vm.startPrank(giver);
        claimableLink.deposit{value: ethAmount}(
            NATIVE_TOKEN_ADDRESS,
            transferID,
            ethAmount,
            depositExpiration
        );
        vm.stopPrank();

        // Check giver and contract ETH balances after deposit()
        uint256 giverETHBalanceAfter = giver.balance;
        uint256 contractETHBalanceAfter = contractAddress.balance;
        assertEq(
            int256(giverETHBalanceAfter) - int256(giverETHBalanceBefore),
            -int256(ethAmount)
        );
        assertEq(contractETHBalanceAfter - contractETHBalanceBefore, ethAmount);

        // Check the deposit note status after deposit()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Deposited,
            true
        );
    }

    function testDepositInToken() public {
        // Set reused variables
        uint256 tokenAmount = 1e18;
        uint64 depositExpiration = uint64(block.timestamp + 1 days);

        // Get giver and claimableLink contract token balances before deposit()
        uint256 giverTokenBalanceBefore = mintableToken.balanceOf(giver);
        uint256 contractTokenBalanceBefore = mintableToken.balanceOf(
            contractAddress
        );

        // Check the deposit note status before deposit()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore ==
                IClaimableLink.DepositStatus.NotDepositedYet,
            true
        );

        // Execute approve() via giver account
        vm.startPrank(giver);
        mintableToken.approve(contractAddress, type(uint256).max);
        vm.stopPrank();

        // Expect Deposited() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Deposited(
            giver,
            tokenAddress,
            transferID,
            tokenAmount,
            depositExpiration
        );

        // Execute deposit() via giver account
        vm.startPrank(giver);
        claimableLink.deposit(
            tokenAddress,
            transferID,
            tokenAmount,
            depositExpiration
        );
        vm.stopPrank();

        // Check giver and contract token balances after deposit()
        uint256 giverTokenBalanceAfter = mintableToken.balanceOf(giver);
        uint256 contractTokenBalanceAfter = mintableToken.balanceOf(
            contractAddress
        );
        assertEq(
            int256(giverTokenBalanceAfter) - int256(giverTokenBalanceBefore),
            -int256(tokenAmount)
        );
        assertEq(
            contractTokenBalanceAfter - contractTokenBalanceBefore,
            tokenAmount
        );

        // Check the deposit note status after deposit()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Deposited,
            true
        );
    }

    // ---------------------------------
    // -- Test: claimWithDepositSig() --
    // ---------------------------------

    function testClaimWithDepositSigInToken() public {
        // Set reused variables
        uint256 tokenAmount = 1e18;
        uint64 depositExpiration = uint64(block.timestamp + 1 days);

        // Get giver and recipient token balances before claimWithDepositSig()
        uint256 giverTokenBalanceBefore = mintableToken.balanceOf(giver);
        uint256 recipientTokenBalanceBefore = mintableToken.balanceOf(
            contractAddress
        );

        // Check the deposit note status before claimWithDepositSig()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore ==
                IClaimableLink.DepositStatus.NotDepositedYet,
            true
        );

        // Execute approve() via giver account
        vm.startPrank(giver);
        mintableToken.approve(contractAddress, type(uint256).max);
        vm.stopPrank();

        // Sign the claim hash with signer account
        bytes memory signerSignature = _signClaimHash(
            signerKey,
            claimableLink,
            giver,
            tokenAddress,
            transferID,
            recipient
        );

        // Sign the EIP-712 deposit hash with giver account
        bytes memory giverSignature = _signEIP712DepositHash(
            giverKey,
            claimableLink,
            tokenAddress,
            transferID,
            tokenAmount,
            depositExpiration
        );

        // Expect Deposited() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Deposited(
            giver,
            tokenAddress,
            transferID,
            tokenAmount,
            depositExpiration
        );

        // Expect Claimed() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Claimed(
            giver,
            tokenAddress,
            transferID,
            tokenAmount,
            recipient,
            signer
        );

        // Execute claimWithDepositSig() via signer account
        vm.startPrank(signer);
        claimableLink.claimWithDepositSig(
            giver,
            tokenAddress,
            transferID,
            payable(recipient),
            tokenAmount,
            depositExpiration,
            giverSignature,
            signerSignature
        );
        vm.stopPrank();

        // Check giver and recipient token balances after claimWithDepositSig()
        uint256 giverTokenBalanceAfter = mintableToken.balanceOf(giver);
        uint256 recipientTokenBalanceAfter = mintableToken.balanceOf(recipient);
        assertEq(
            int256(giverTokenBalanceAfter) - int256(giverTokenBalanceBefore),
            -int256(tokenAmount)
        );
        assertEq(
            recipientTokenBalanceAfter - recipientTokenBalanceBefore,
            tokenAmount
        );

        // Check the deposit note status after claimWithDepositSig()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Claimed,
            true
        );
    }

    // ---------------------------------
    // -- Test: claimWithDirectAuth() --
    // ---------------------------------

    function testClaimWithDirectAuthInETH() public {
        // Set reused variables
        uint256 ethAmount = 1 ether;

        // Execute deposit() via giver account
        vm.startPrank(giver);
        claimableLink.deposit{value: ethAmount}(
            NATIVE_TOKEN_ADDRESS,
            transferID,
            ethAmount,
            uint64(block.timestamp + 1 days)
        );
        vm.stopPrank();

        // Get claimableLink contract and recipient ETH balances before claimWithDirectAuth()
        uint256 contractETHBalanceBefore = contractAddress.balance;
        uint256 recipientETHBalanceBefore = recipient.balance;

        // Check the deposit note status before claimWithDirectAuth()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore == IClaimableLink.DepositStatus.Deposited,
            true
        );

        // Sign the EIP-712 claim hash with giver account
        bytes memory giverSignature = _signEIP712ClaimHash(
            giverKey,
            claimableLink,
            NATIVE_TOKEN_ADDRESS,
            transferID,
            recipient
        );

        // Expect Claimed() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Claimed(
            giver,
            NATIVE_TOKEN_ADDRESS,
            transferID,
            ethAmount,
            recipient,
            giver
        );

        // Execute claimWithDirectAuth() via signer account
        vm.startPrank(signer);
        claimableLink.claimWithDirectAuth(
            giver,
            NATIVE_TOKEN_ADDRESS,
            transferID,
            payable(recipient),
            giverSignature
        );
        vm.stopPrank();

        // Check contract and recipient ETH balances after claimWithDirectAuth()
        uint256 contractETHBalanceAfter = contractAddress.balance;
        uint256 recipientETHBalanceAfter = recipient.balance;
        assertEq(
            int256(contractETHBalanceAfter) - int256(contractETHBalanceBefore),
            -int256(ethAmount)
        );
        assertEq(
            recipientETHBalanceAfter - recipientETHBalanceBefore,
            ethAmount
        );

        // Check the deposit note status after claimWithDirectAuth()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Claimed,
            true
        );
    }

    function testClaimWithDirectAuthInToken() public {
        // Set reused variables
        uint256 tokenAmount = 1e18;

        // Execute approve() adn deposit() via giver account
        vm.startPrank(giver);
        mintableToken.approve(contractAddress, type(uint256).max);
        claimableLink.deposit(
            tokenAddress,
            transferID,
            tokenAmount,
            uint64(block.timestamp + 1 days)
        );
        vm.stopPrank();

        // Get claimableLink contract and recipient token balances before claimWithDirectAuth()
        uint256 contractTokenBalanceBefore = mintableToken.balanceOf(
            contractAddress
        );
        uint256 recipientTokenBalanceBefore = mintableToken.balanceOf(
            recipient
        );

        // Check the deposit note status before claimWithDirectAuth()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore == IClaimableLink.DepositStatus.Deposited,
            true
        );

        // Sign the EIP-712 claim hash with giver account
        bytes memory giverSignature = _signEIP712ClaimHash(
            giverKey,
            claimableLink,
            tokenAddress,
            transferID,
            recipient
        );

        // Expect Claimed() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Claimed(
            giver,
            tokenAddress,
            transferID,
            tokenAmount,
            recipient,
            giver
        );

        // Execute claimWithDirectAuth() via signer account
        vm.startPrank(signer);
        claimableLink.claimWithDirectAuth(
            giver,
            tokenAddress,
            transferID,
            payable(recipient),
            giverSignature
        );
        vm.stopPrank();

        // Check contract and recipient token balances after claimWithDirectAuth()
        uint256 contractTokenBalanceAfter = mintableToken.balanceOf(
            contractAddress
        );
        uint256 recipientTokenBalanceAfter = mintableToken.balanceOf(recipient);
        assertEq(
            int256(contractTokenBalanceAfter) -
                int256(contractTokenBalanceBefore),
            -int256(tokenAmount)
        );
        assertEq(
            recipientTokenBalanceAfter - recipientTokenBalanceBefore,
            tokenAmount
        );

        // Check the deposit note status after claimWithDirectAuth()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Claimed,
            true
        );
    }

    // --------------------
    // -- Test: cancel() --
    // --------------------

    function testCancelInETH() public {
        // Set reused variables
        uint256 ethAmount = 1e18;

        // Execute approve() adn deposit() via giver account
        vm.startPrank(giver);
        claimableLink.deposit{value: ethAmount}(
            NATIVE_TOKEN_ADDRESS,
            transferID,
            ethAmount,
            uint64(block.timestamp + 1 days)
        );
        vm.stopPrank();

        // Get giver and claimableLink contract ETH balances before cancel()
        uint256 giverETHBalanceBefore = giver.balance;
        uint256 contractETHBalanceBefore = contractAddress.balance;

        // Check the deposit note status before cancel()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore == IClaimableLink.DepositStatus.Deposited,
            true
        );

        // Expect Cancelled() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Cancelled(giver, NATIVE_TOKEN_ADDRESS, transferID);

        // Execute cancel() via giver account
        vm.startPrank(giver);
        claimableLink.cancel(NATIVE_TOKEN_ADDRESS, transferID);
        vm.stopPrank();

        // Get giver and claimableLink contract ETH balances after cancel()
        uint256 giverETHBalanceAfter = giver.balance;
        uint256 contractETHBalanceAfter = contractAddress.balance;
        assertEq(giverETHBalanceAfter - giverETHBalanceBefore, ethAmount);
        assertEq(
            int256(contractETHBalanceAfter) - int256(contractETHBalanceBefore),
            -int256(ethAmount)
        );

        // Check the deposit note status after cancel()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Cancelled,
            true
        );
    }

    function testCancelInToken() public {
        // Set reused variables
        uint256 tokenAmount = 1e18;

        // Execute approve() adn deposit() via giver account
        vm.startPrank(giver);
        mintableToken.approve(contractAddress, type(uint256).max);
        claimableLink.deposit(
            tokenAddress,
            transferID,
            tokenAmount,
            uint64(block.timestamp + 1 days)
        );
        vm.stopPrank();

        // Get giver and claimableLink contract token balances before cancel()
        uint256 giverTokenBalanceBefore = mintableToken.balanceOf(giver);
        uint256 contractTokenBalanceBefore = mintableToken.balanceOf(
            contractAddress
        );

        // Check the deposit note status before cancel()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore == IClaimableLink.DepositStatus.Deposited,
            true
        );

        // Expect Cancelled() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Cancelled(giver, tokenAddress, transferID);

        // Execute cancel() via giver account
        vm.startPrank(giver);
        claimableLink.cancel(tokenAddress, transferID);
        vm.stopPrank();

        // Get giver and claimableLink contract token balances after cancel()
        uint256 giverTokenBalanceAfter = mintableToken.balanceOf(giver);
        uint256 contractTokenBalanceAfter = mintableToken.balanceOf(
            contractAddress
        );
        assertEq(giverTokenBalanceAfter - giverTokenBalanceBefore, tokenAmount);
        assertEq(
            int256(contractTokenBalanceAfter) -
                int256(contractTokenBalanceBefore),
            -int256(tokenAmount)
        );

        // Check the deposit note status after cancel()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Cancelled,
            true
        );
    }

    // --------------------
    // -- Test: refund() --
    // --------------------

    function testRefundInETH() public {
        // Set reused variables
        uint256 ethAmount = 1 ether;
        uint64 depositExpiration = uint64(block.timestamp + 1 days);

        // Execute deposit() via giver account
        vm.startPrank(giver);
        claimableLink.deposit{value: ethAmount}(
            NATIVE_TOKEN_ADDRESS,
            transferID,
            ethAmount,
            depositExpiration
        );
        vm.stopPrank();

        // Get giver and claimableLink contract ETH balances before claimWithDirectAuth()
        uint256 giverETHBalanceBefore = giver.balance;
        uint256 contractETHBalanceBefore = contractAddress.balance;

        // Check the deposit note status before claimWithDirectAuth()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore == IClaimableLink.DepositStatus.Deposited,
            true
        );

        // Simulate deposit expiration
        vm.warp(depositExpiration + 1);

        // Expect Refunded() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Refunded(giver, NATIVE_TOKEN_ADDRESS, transferID);

        // Execute refund() via signer account
        vm.startPrank(signer);
        claimableLink.refund(payable(giver), NATIVE_TOKEN_ADDRESS, transferID);
        vm.stopPrank();

        // Get giver and claimableLink contract ETH balances after cancel()
        uint256 giverETHBalanceAfter = giver.balance;
        uint256 contractETHBalanceAfter = contractAddress.balance;
        assertEq(giverETHBalanceAfter - giverETHBalanceBefore, ethAmount);
        assertEq(
            int256(contractETHBalanceAfter) - int256(contractETHBalanceBefore),
            -int256(ethAmount)
        );

        // Check the deposit note status after cancel()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, NATIVE_TOKEN_ADDRESS, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Expired,
            true
        );
    }

    function testRefundInToken() public {
        // Set reused variables
        uint256 tokenAmount = 1e18;
        uint64 depositExpiration = uint64(block.timestamp + 1 days);

        // Execute approve() adn deposit() via giver account
        vm.startPrank(giver);
        mintableToken.approve(contractAddress, type(uint256).max);
        claimableLink.deposit(
            tokenAddress,
            transferID,
            tokenAmount,
            depositExpiration
        );
        vm.stopPrank();

        // Get giver and claimableLink contract token balances before refund()
        uint256 giverTokenBalanceBefore = mintableToken.balanceOf(giver);
        uint256 contractTokenBalanceBefore = mintableToken.balanceOf(
            contractAddress
        );

        // Check the deposit note status before refund()
        IClaimableLink.Deposit memory depositNoteBefore = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusBefore = depositNoteBefore
            .depositStatus;
        assertEq(
            depositNoteStatusBefore == IClaimableLink.DepositStatus.Deposited,
            true
        );

        // Simulate deposit expiration
        vm.warp(depositExpiration + 1);

        // Expect Refunded() event emission
        vm.expectEmit(true, true, true, true, contractAddress);
        emit IClaimableLink.Refunded(giver, tokenAddress, transferID);

        // Execute refund() via signer account
        vm.startPrank(signer);
        claimableLink.refund(payable(giver), tokenAddress, transferID);
        vm.stopPrank();

        // Get giver and claimableLink contract ETH balances after cancel()
        uint256 giverTokenBalanceAfter = mintableToken.balanceOf(giver);
        uint256 contractTokenBalanceAfter = mintableToken.balanceOf(
            contractAddress
        );
        assertEq(giverTokenBalanceAfter - giverTokenBalanceBefore, tokenAmount);
        assertEq(
            int256(contractTokenBalanceAfter) -
                int256(contractTokenBalanceBefore),
            -int256(tokenAmount)
        );

        // Check the deposit note status after cancel()
        IClaimableLink.Deposit memory depositNoteAfter = claimableLink
            .getDeposit(giver, tokenAddress, transferID);
        IClaimableLink.DepositStatus depositNoteStatusAfter = depositNoteAfter
            .depositStatus;
        assertEq(
            depositNoteStatusAfter == IClaimableLink.DepositStatus.Expired,
            true
        );
    }

    // --------------------
    // -- Util Functions --
    // --------------------

    function _signClaimHash(
        uint256 _privateKey,
        ClaimableLink _claimableLink,
        address _giver,
        address _token,
        address _transferID,
        address _recipient
    ) private pure returns (bytes memory) {
        bytes32 claimHash = _claimableLink.getClaimHash(
            _giver,
            _token,
            _transferID,
            _recipient
        );

        bytes32 ethSignedClaimHash = MessageHashUtils.toEthSignedMessageHash(
            claimHash
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            ethSignedClaimHash
        );
        return abi.encodePacked(r, s, v);
    }

    function _signEIP712DepositHash(
        uint256 _privateKey,
        ClaimableLink _claimableLink,
        address _token,
        address _transferID,
        uint256 _amount,
        uint64 _expiration
    ) private view returns (bytes memory) {
        bytes32 eip712DepositHash = _claimableLink.getEIP712DepositHash(
            IClaimableLink.DepositSig({
                token: _token,
                transferID: _transferID,
                amount: _amount,
                expiration: _expiration
            })
        );

        bytes32 typeDataDepositHash = MessageHashUtils.toTypedDataHash(
            _claimableLink.getDomainSeparator(),
            eip712DepositHash
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            typeDataDepositHash
        );
        return abi.encodePacked(r, s, v);
    }

    function _signEIP712ClaimHash(
        uint256 _privateKey,
        ClaimableLink _claimableLink,
        address _token,
        address _transferID,
        address _recipient
    ) private view returns (bytes memory) {
        bytes32 eip712ClaimHash = _claimableLink.getEIP712ClaimHash(
            IClaimableLink.ClaimSig({
                token: _token,
                transferID: _transferID,
                recipient: _recipient
            })
        );

        bytes32 typeDataClaimHash = MessageHashUtils.toTypedDataHash(
            _claimableLink.getDomainSeparator(),
            eip712ClaimHash
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _privateKey,
            typeDataClaimHash
        );
        return abi.encodePacked(r, s, v);
    }
}
