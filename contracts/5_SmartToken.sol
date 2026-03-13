// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./6_ITokenRecipient.sol";

error TransferFailed();
error AmountZero();
error AddressInvalid();
error CallbackFailed();

contract smartToken is ERC20{
    constructor(string memory name_,string memory symbol_) ERC20(name_,symbol_){
         _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function transferAndCall(address _bankAddress,uint256 _amount) external  {
        if(_amount == 0) revert AmountZero();
        if(_bankAddress == address(0) || _bankAddress.code.length <= 0) revert AddressInvalid();

        transfer(_bankAddress, _amount);

        //触发TokenBank的回调函数
        ITokenRecipient(_bankAddress).onTransferReceived(msg.sender,_amount);

        // 校验转账是否成功
        bool success = transfer(_bankAddress, _amount);
        if (!success) revert TransferFailed();

        // 触发回调并捕获异常
        try ITokenRecipient(_bankAddress).onTransferReceived(msg.sender, _amount) {
            // 回调成功，无需处理
        } catch {
            revert CallbackFailed();
        }

    }

}