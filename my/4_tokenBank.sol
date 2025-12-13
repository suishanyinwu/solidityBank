// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract tokenBank{
    mapping(address =>mapping(address => uint)) userTokenBalance;

    event depositEvent(address user,address token,uint256 amount);
    event withdrawEvent(address to,address token,uint value);

    error WithdrawNotZero();
    error DepositNotZero();
    error TokenBalanceNotEnough();
    error CallFailure(string);

    //存款
    function deposit(address _token,uint256 _amount) public payable {
        if(_amount==0) revert DepositNotZero();

        //查询用户在token的余额
        (bool success1,bytes memory data1)=_token.call( abi.encodeWithSignature("balanceOf(address)", msg.sender) );
        if(!success1) revert CallFailure("balaceOf");
        if( _amount > abi.decode(data1, (uint256) ) ) revert TokenBalanceNotEnough();

        //授权
        (bool success2,bytes memory data2)=_token.delegatecall( abi.encodeWithSignature("approve(address,uint256)", address(this),_amount));
        if(!success2 || !abi.decode(data2, (bool))) revert CallFailure("approve");

        //转账
        (bool success3,bytes memory data3)=_token.call( abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender,address(this),_amount) );
        if(!success3 || !abi.decode(data3, (bool))) revert CallFailure("transferFrom");

        //信息存储到本地合约
        userTokenBalance[msg.sender][_token]+=_amount;
        emit depositEvent(msg.sender, _token, _amount);

    }

    //提款
    function withdraw(address _token,uint256 _amount) public payable {
        if(_amount==0) revert WithdrawNotZero();

        //查询用户授权给本合约的余额
        if( _amount > userTokenBalance[msg.sender][_token] ) revert TokenBalanceNotEnough();

        //更新本地余额
        userTokenBalance[msg.sender][_token]-=_amount;
        emit withdrawEvent(msg.sender,_token,_amount);

        //转账给用户
        (bool success,bytes memory data)=_token.call(abi.encodeWithSignature( "transfer(address, uint256)", msg.sender,_amount) );
        if(!success || !abi.decode(data, (bool))) revert CallFailure("transfer");
    }
}