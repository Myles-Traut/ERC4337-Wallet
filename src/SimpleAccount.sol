// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "account-abstraction/core/BaseAccount.sol";

contract SimpleAccount is BaseAccount {
    using ECDSA for bytes32;

    IEntryPoint private immutable _entryPoint;

    address public owner;

    /// @notice Validate that only the entryPoint is able to call a method
    modifier onlyEntryPoint() {
        require(msg.sender == address(_entryPoint), "SmartWallet: Only entryPoint can call this method");
        _;
    }

    /// @notice Able to receive ETH
    receive() external payable {}

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event PayPrefund(address indexed _payee, uint256 _amount);

    constructor(IEntryPoint anEntryPoint , address _owner) {
        _entryPoint = anEntryPoint;
        owner = _owner;
    }

    /**
     * deposit more funds for this account in the entryPoint
     */
    function addDeposit() public payable {
        entryPoint().depositTo{value : msg.value}(address(this));
    }

    /**
     * withdraw value from the account's deposit
     * @param withdrawAddress target to send to
     * @param amount to withdraw
     */
    function withdrawDepositTo(address payable withdrawAddress, uint256 amount) public {
        entryPoint().withdrawTo(withdrawAddress, amount);
    }

    /**
     * execute a transaction (called directly from owner, or by entryPoint)
     */
    function execute(address dest, uint256 value, bytes calldata func) external {
        _requireFromEntryPointOrOwner();
        _call(dest, value, func);
    }

    /**
     * execute a sequence of transactions
     */
    function executeBatch(address[] calldata dest, bytes[] calldata func) external {
        _requireFromEntryPointOrOwner();
        require(dest.length == func.length, "wrong array lengths");
        for (uint256 i = 0; i < dest.length; i++) {
            _call(dest[i], 0, func[i]);
        }
    }

    /*--------------------------*/
    /*------VIEW FUNCTIONS------*/
    /*--------------------------*/

    /// @inheritdoc BaseAccount
    function entryPoint() public view virtual override returns (IEntryPoint) {
        return _entryPoint;
    }

    /**
     * check current account deposit in the entryPoint
     */
    function getDeposit() public view returns (uint256) {
        return entryPoint().balanceOf(address(this));
    }
    function validateSig(UserOperation calldata userOp, bytes32 userOpHash) public returns (uint256 validationData){
        validationData = _validateSignature(userOp, userOpHash);
    }

    /*--------------------------------*/
    /*------ INTERNAL FUNCTIONS ------*/
    /*--------------------------------*/

    // Require the function call went through EntryPoint or owner
    function _requireFromEntryPointOrOwner() internal view {
        require(msg.sender == address(entryPoint()) || msg.sender == owner, "account: not Owner or EntryPoint");
    }

    // implement template method of BaseAccount
    function _validateSignature(UserOperation calldata userOp, bytes32 userOpHash)
    internal override virtual returns (uint256 validationData) {
        bytes32 hash = userOpHash.toEthSignedMessageHash();
        if (owner != hash.recover(userOp.signature))
            return SIG_VALIDATION_FAILED;
        return 0;
    }

    function _validateNonce(uint256 nonce) internal override virtual view {
        require(nonce < type(uint64).max);
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value : value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function _onlyOwner() internal view {
        //directly from EOA owner, or through the account itself (which gets redirected through execute())
        require(msg.sender == owner || msg.sender == address(this), "only owner");
    }
}
