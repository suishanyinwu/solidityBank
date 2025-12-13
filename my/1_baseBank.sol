// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract EtherBank{
    address owner;
    mapping (address => uint) userBalance;
    address[] userAddress;
    address[3] userBalance_Top3;

    event depositEvent(address indexed from,uint value);
    event newUserAddressEvent(address newAddress);
    event updateRankingEvent(address[3] balance_Top3);
    event withdrawEvent(address to,uint value);

    error DepositNotZero();
    error NotOwner();
    error ETHNotEnough();
    error WithdrawNotZero();

    constructor(){
        owner=msg.sender;
    }

    //管理者权限检查
    modifier onlyOwner{
        if(msg.sender != owner){
            revert NotOwner();
        }
        _;
    }

    receive() external payable {
        deposit(msg.sender);
    }

    //提款
    function ownerWithdraw(uint _value) external onlyOwner {
        if(_value>getAllBalance()){
            revert ETHNotEnough();
        }else if(_value==0){
            revert WithdrawNotZero();
        }

        payable(msg.sender).transfer(_value);
        
        emit withdrawEvent(msg.sender, _value);
    }

    //存款
    function deposit(address _to) public payable {
        if(msg.value == 0){
            revert DepositNotZero();
        }

        if(userBalance[_to] == 0){
            bool existence=false;
            for(uint j=0;j<userAddress.length;j++){
                if(_to == userAddress[j]){
                    existence=true;
                }
            }
            if(!existence){
                userAddress.push(_to);
                emit newUserAddressEvent(_to);
            } 
        }

        userBalance[_to]+=msg.value;

        emit depositEvent(_to, msg.value);

        updateBalanceRanking(_to);
    }

    //更新余额排行榜
    function updateBalanceRanking(address _address) internal {
        uint i=1;
        //判断是否为空，是否为一致，插入新的address
        for(;i<=3;i++){
            if(address(0) == userBalance_Top3[i-1] || _address == userBalance_Top3[i-1]) break;
        }
        if(i!=4) userBalance_Top3[i-1]=_address;

        //数组排序
        for(;i>=1;i--){
            if(userBalance[_address]>userBalance[userBalance_Top3[i-1]]){
                if(i==4){
                    userBalance_Top3[i-1]=_address;
                } else{
                    userBalance_Top3[i]=userBalance_Top3[i-1];
                    userBalance_Top3[i-1]=_address;
                }
            }
        }

        emit updateRankingEvent(userBalance_Top3);
    
    }

    //查询余额排行榜用户地址
    function getBalanceRanking() public view returns(address[3] memory){
        return userBalance_Top3;
    }

    //查询用户余额
    function getUserBalance(address _user) public view returns(uint){
        return userBalance[_user];
    }

    //查询合约总余额
    function getAllBalance() public view returns (uint total){
        return address(this).balance;
    }



} 