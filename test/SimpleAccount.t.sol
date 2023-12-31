// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AccountFactory.sol"; 
import "../src/SimpleAccount.sol"; 
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";

contract SimpleAccountTest is Test {

    AccountFactory public factory;
    IEntryPoint public entryPoint;

    address public owner;
    address public simpleWallet;
    address payable beneficiary;
    
    uint256 private ownerKey;

    bytes32 private salt = "0x12xxx345";

    function setUp() public {

        // beneficiary is an address that receives the fees from the bundler
        beneficiary = payable(address(makeAddr("beneficiary")));
        entryPoint = IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        factory = new AccountFactory();
        (owner, ownerKey) = makeAddrAndKey("owner");

        // Precompute the wallet address
        simpleWallet = factory.getAddress(salt, address(entryPoint), owner);

        // Prefund ETH into entryPoint to pay for UserOps
        deal(owner, 10 ether);
        vm.prank(owner);
            entryPoint.depositTo{value: 5 ether}(simpleWallet);
    }

    function test_InitCodeAndTransfer() public {

        // Create a user op with initCode.
        UserOperation memory op = _fillUserOp(
            simpleWallet,
            abi.encodePacked(
            abi.encodePacked(address(factory)),
            abi.encodeWithSelector(factory.createAccount.selector, address(entryPoint), owner, salt)
            ),
            ""
        );

        op.signature = abi.encodePacked(_signUserOpHash(vm, ownerKey, op));

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        // Check that there's no code at the simpleWallet address
        uint256 codeSize = simpleWallet.code.length;
        assertEq(codeSize, 0);

        uint256 nonce = entryPoint.getNonce(simpleWallet, 0);
        assertEq(nonce, 0);

        console.logUint(entryPoint.balanceOf(simpleWallet));

        /// Deploy wallet through the entryPoint
        vm.prank(owner);
            entryPoint.handleOps(ops, beneficiary);

        // Assert that the nonce has increased
        nonce = entryPoint.getNonce(simpleWallet, 0);
        assertEq(nonce, 1);

        // Assert that there is now code at the simpleWallet address
        codeSize = simpleWallet.code.length;
        assertGt(codeSize, 0);

        // Cast wallet to SimpleAccount for interaction
        SimpleAccount wallet = SimpleAccount(payable(simpleWallet));

        address walletOwner = wallet.owner();
        address entryPointAddress = address(wallet.entryPoint());
        assertEq(walletOwner, owner);
        assertEq(entryPointAddress, address(entryPoint));

        // Check wallet deposit in entryPoint
        console.logUint(wallet.getDeposit());

        assertEq(simpleWallet.balance, 0 ether);
        // Give wallet 2 ether
        deal(simpleWallet, 2 ether);
        assertEq(simpleWallet.balance, 2 ether);

        // Ctreate UserOp to transfer 1 ETH from wallet to owner
        UserOperation memory op2 = _fillUserOp(
            simpleWallet,
            "",
            abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                owner,
                1 ether,
                hex""
            )
        );

        // Sign UserOp
        op2.signature = abi.encodePacked(_signUserOpHash(vm, ownerKey, op2));
        UserOperation[] memory ops2 = new UserOperation[](1);
        ops2[0] = op2;

        assertEq(simpleWallet.balance, 2 ether);
        assertEq(owner.balance, 5 ether);

        // CAll from entryPoint
        entryPoint.handleOps(ops2, beneficiary);

        assertEq(simpleWallet.balance, 1 ether);
        assertEq(owner.balance, 6 ether);

        // EntryPoint pays for gas
        console.logUint(wallet.getDeposit());
    }

    function _signUserOpHash(
        Vm _vm,
        uint256 _key,
        UserOperation memory _op
    ) internal view returns (bytes memory signature) {
        bytes32 hash = entryPoint.getUserOpHash(_op);
        (uint8 v, bytes32 r, bytes32 s) = _vm.sign(_key, ECDSA.toEthSignedMessageHash(hash));
        signature = abi.encodePacked(r, s, v);
    }

    function _fillUserOp(
        address _sender,
        bytes memory _initData,
        bytes memory _callData
    ) internal view returns (UserOperation memory op) {
        op.sender = _sender;
        op.nonce = entryPoint.getNonce(_sender, 0);
        op.initCode = _initData;
        op.callData = _callData;
        op.callGasLimit = 10000000;
        op.verificationGasLimit = 10000000;
        op.preVerificationGas = 50000;
        op.maxFeePerGas = 50000;
        op.maxPriorityFeePerGas = 1;
    }
}
