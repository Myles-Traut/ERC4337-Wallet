// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

import "../src/AccountFactory.sol"; 
import "../src/SimpleAccount.sol"; 
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation} from "lib/account-abstraction/contracts/interfaces/UserOperation.sol";



contract SimpleAccountTest is Test {

    AccountFactory public factory;
    IEntryPoint entryPoint;

    address owner;
    address sender;
    address payable beneficiary;
    
    uint256 ownerKey;

    bytes32 salt = "0x12xxx345";

    function setUp() public {
        beneficiary = payable(address(makeAddr("beneficiary")));
        entryPoint = IEntryPoint(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789);
        factory = new AccountFactory();
        (owner, ownerKey) = makeAddrAndKey("owner");

        // Precompute the wallet address
        sender = factory.getAddress(salt, address(entryPoint), owner);

        // Depotit ETH into entryPoint to pay for UserOp
        deal(owner, 10 ether);
        vm.prank(owner);
            entryPoint.depositTo{value: 5 ether}(sender);
    }

    function test_InitCode() public {

        UserOperation memory op = _fillUserOp(
            sender,
            abi.encodePacked(
            abi.encodePacked(address(factory)),
            abi.encodeWithSelector(factory.createAccount.selector, address(entryPoint), owner, salt)
            )
        );

        op.signature = abi.encodePacked(_signUserOpHash(vm, ownerKey, op));

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = op;

        // Check that there's no code at the sender address
        uint256 codeSize = sender.code.length;
        assertEq(codeSize, 0);

        uint256 nonce = entryPoint.getNonce(sender, 0);
        assertEq(nonce, 0);

        /// Deploy wallet through the entryPoint
        vm.prank(owner);
            entryPoint.handleOps(ops, beneficiary);

        // Assert that the nonce has increased
        nonce = entryPoint.getNonce(sender, 0);
        assertEq(nonce, 1);

        // Assert that there is now code at the sender address
        codeSize = sender.code.length;
        assertGt(codeSize, 0);

        SimpleAccount wallet = SimpleAccount(payable(sender));

        address walletOwner = wallet.owner();
        address entryPointAddress = address(wallet.entryPoint());
        assertEq(walletOwner, owner);
        assertEq(entryPointAddress, address(entryPoint));
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
        bytes memory _data
    ) internal view returns (UserOperation memory op) {
        op.sender = _sender;
        op.nonce = entryPoint.getNonce(_sender, 0);
        op.initCode = _data;
        op.callGasLimit = 10000000;
        op.verificationGasLimit = 10000000;
        op.preVerificationGas = 50000;
        op.maxFeePerGas = 50000;
        op.maxPriorityFeePerGas = 1;
    }
}
