// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "lib/openzeppelin-contracts/contracts/utils/Create2.sol";

import "./SimpleAccount.sol";

/**
 * A sample factory contract for SimpleAccount
 * A UserOperations "initCode" holds the address of the factory, and a method call (to createAccount, in this sample factory).
 * The factory's createAccount returns the target account address even if it is already installed.
 * This way, the entryPoint.getSenderAddress() can be called either before or after the account is created.
 */
contract AccountFactory {
    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after account creation
     */
    function createAccount(IEntryPoint _entryPoint, address _owner, bytes32 _salt) public returns (SimpleAccount ret) {
        address addr = getAddress(_salt, address(_entryPoint), _owner);
        uint codeSize = addr.code.length;
        if (codeSize > 0) {
            return SimpleAccount(payable(addr));
        }
        ret = new SimpleAccount{salt: _salt}(_entryPoint, _owner);
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    function getAddress(bytes32 _salt, address _entryPoint, address _owner) public view returns (address) {
        return Create2.computeAddress(
            _salt, 
            keccak256(abi.encodePacked(type(SimpleAccount).creationCode, abi.encode(_entryPoint, _owner))));
    }
}
