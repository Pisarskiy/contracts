pragma solidity ^0.4.25;

import "./oraclizeAPI.sol";

library SafeMath {

  function mul(uint256 _a, uint256 _b) internal pure returns (uint256) {
   
    if (_a == 0) {
      return 0;
    }

    uint256 c = _a * _b;
    require(c / _a == _b);

    return c;
  }

  function div(uint256 _a, uint256 _b) internal pure returns (uint256) {
    require(_b > 0); // Solidity only automatically asserts when dividing by 0
    uint256 c = _a / _b;
    // assert(_a == _b * c + _a % _b); // There is no case in which this doesn't hold

    return c;
  }

  function sub(uint256 _a, uint256 _b) internal pure returns (uint256) {
    require(_b <= _a);
    uint256 c = _a - _b;

    return c;
  }

  function add(uint256 _a, uint256 _b) internal pure returns (uint256) {
    uint256 c = _a + _b;
    require(c >= _a);

    return c;
  }

  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b != 0);
    return a % b;
  }
  
}

contract Lottery is usingOraclize {
   
    using SafeMath for uint;
   
    uint constant minBet = 0.1 ether;
    uint constant fee = 100; // 100% = 10000
    uint constant roundDuration = 86400;
    
    bool isTest = false; // Для отладки в JavaScript VM
    
    enum lotteryStates {RELEASE,STARTED,STOPED}
    lotteryStates state;
    
    bytes32 public roundId;
    
    struct Ticket {
        address ticketAddress;
        uint amountInvested;
    }
    
    struct Player {
        address playerAddress;
        mapping( address => uint) amountByTicket;
        uint amountInvested;
    }
    
    struct Bet {
        address playerAddress;
        address ticketAddress;
        uint amountBet;
    }
    
    mapping (address => mapping (bytes32 => uint)) public playerIdByAddress; // and by roundId
    mapping (uint => Player) players;
    uint[] public playersIDs;
    
    uint public jackpot;
    address public owner;
    uint numPlayers;
    
    mapping (bytes32 => Bet) public bets;
    bytes32[] public betsKeys;
    
    mapping (address => Ticket) tickets;
    address[] ticketAddresses;
    
    
    event Transfer (address indexed from, address indexed to, uint256 value);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
    
    event LogNewOraclizeQuery(string description);
    event LogLottery(string description, address sender, uint amount);
    
    constructor() {
        
        state = lotteryStates.RELEASE;
        
        owner = msg.sender;
        numPlayers = 0;
        
    }
   
   
    // MODIFIERS
    
    modifier onlyOwner {
        if (msg.sender != owner) throw;
        _;
    }
    
    modifier onlyPlayer {
        if (playerIdByAddress[msg.sender][roundId] == 0) throw;
        _;
    }
    
    modifier onlyOraclize {
        if (!isTest) {
            if (msg.sender != oraclize_cbAddress()) throw;
        }
        _;
    }
    
    modifier onlyStarded {
        if (state != lotteryStates.STARTED) throw;
        _;
    }
    
    
    // MANAGE CONTRACT 
    function regTicket( address ticketAddress) onlyOwner {
        
        if (ticketAddresses.length >= 3) throw;
        if (state != lotteryStates.RELEASE) throw;
        
        if (tickets[ticketAddress].ticketAddress == address(0)) {
            
            tickets[ticketAddress] = Ticket(ticketAddress, 0);
            ticketAddresses.push(ticketAddress);
            
        }
        
    }
    
    function release() payable onlyOwner {
        
        if (state != lotteryStates.RELEASE) throw;
        if (ticketAddresses.length < 3) throw;
        
        state = lotteryStates.STARTED;
        
        startNewRound(roundDuration);
        
        LogLottery("release", msg.sender, this.balance);
        
    }
    
    
    // HELPER FUNCTIONS
    function getTicket(uint id) view returns(address, uint) {
        
        if (id < ticketAddresses.length) {
            address _address = ticketAddresses[id];
            return (tickets[_address].ticketAddress, tickets[_address].amountInvested);
        }
        
    }
    
    function getTickets(uint id) view returns(address[]) {
        return ticketAddresses;
    }

    function getBet(uint id) view returns (address, uint) {
        
        if (id < betsKeys.length) {
            bytes32 betKey = betsKeys[id];
            return(bets[betKey].playerAddress, bets[betKey].amountBet);
        }
            
    }
    
    function addPlayerAtID(address playerAddress, address ticketAddress, uint betValue)
        private {

        uint id;
        
        if (playerIdByAddress[playerAddress][roundId] == uint(0)) {
            // Регистрируем нового игрока 
            numPlayers++;
            
            id = numPlayers;
            playerIdByAddress[playerAddress][roundId] = id;
            playersIDs.push(id);
            
            players[id].playerAddress = playerAddress;
            
            LogLottery("addPlayerAtID", playerAddress, betValue);
        
        } else {
            id = playerIdByAddress[playerAddress][roundId];
            LogLottery("updPlayerAtID", playerAddress, betValue);
        } 
        
        players[id].amountByTicket[ticketAddress] += betValue;
        players[id].amountInvested += betValue;
        
        
        
    }
    
    function getMinBet() view returns(uint) {
        return minBet;
    }
    
    function getBalanceOfLottery() view returns(uint) {
        return this.balance;    
    }
    
    function getCurrentState() view returns(lotteryStates) {
        return state;
    }
    
    function getPlayersIDs() view returns(uint[]) {
        return playersIDs;
    }
    
    function getPlayerInfo( address playerAddress) view returns (uint, uint) {
        
        uint id = playerIdByAddress[playerAddress][roundId];
        
        return (id, players[id].amountInvested);
    }
    
    function percent(uint numerator, uint denominator, uint precision) internal constant returns(uint quotient) {

         // caution, check safe-to-multiply here
        uint _numerator  = numerator * 10 ** (precision+1);
        // with rounding of last digit
        uint _quotient =  ((_numerator / denominator) + 5) / 10;
        return ( _quotient);
    }
    
    
    // MAIN PART
    
    function deposit(address _playerAddress) payable 
        onlyStarded {
        
        uint betValue = msg.value;
        
        if (betValue < minBet) throw;
        
        // Адрес кошелька еще не зарегистрирован
        address _ticketAddress = msg.sender;
        if (msg.sender != tickets[_ticketAddress].ticketAddress) throw;
        
        tickets[msg.sender].amountInvested += msg.value;
        
        bytes32 newId;
        
        if (isTest) {
        
            newId = bytes32(keccak256(now));
                
        } else {
        
            if (oraclize_getPrice("URL") > this.balance) {
                LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
                throw;
            }
            
            newId = oraclize_query("URL", "json(https://api.gdax.com/products/ETH-USD/ticker).price");
            
        }
        
        bets[newId] = Bet(_playerAddress, msg.sender, betValue);
        betsKeys.push(newId);
       
        addPlayerAtID(_playerAddress, _ticketAddress, betValue);
        
        jackpot += betValue;
        
        LogLottery("deposit", _playerAddress, betValue);
       
    }
    
    function startNewRound(uint scheduleTime) private {
       
        state = lotteryStates.STARTED;
        
        if (isTest) {
            roundId = bytes32(keccak256(now));
        
        } else {
            
            if (oraclize_getPrice("URL") > this.balance) {
                
                // На счету контракта не хватает средств
                state = lotteryStates.STOPED;
                LogNewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");    
        
            } else {
                // Рандомное число от 1 до 3, 
                // которое мы получим через scheduleTime секунд в функции __callback
                roundId = oraclize_query( scheduleTime, "URL", "json(https://api.random.org/json-rpc/1/invoke).result.random.data.0", '\n{"jsonrpc":"2.0","method":"generateIntegers","params":{"apiKey":"d025913b-ae24-47e0-bc13-0116d6c231d3","n":1,"min":1,"max":3,"replacement":true,"base":10},"id":1}');
            }    
        }
        
        
    }
    
    function __callback(bytes32 myid, string result) onlyOraclize {
      
        if (myid == roundId) {
            
            // Раунд закончен, распределяем прибыль 
            uint winnerNumber = parseInt(result);
            profitDistribution(winnerNumber);     
            
        }
        
    }
    
    // Для отладки через VM
    function testCallBack() onlyOwner{
        
        uint randomInt = 1;
        profitDistribution(randomInt);
        
    }
    
    
    function profitDistribution(uint _winnerNumber) private {
        
        if ((_winnerNumber > ticketAddresses.length) || (_winnerNumber == 0)) throw;
        
        // Меняем state, чтобы в момент распределения никто не ставил ставки
        state = lotteryStates.STOPED;
        
        address winnerAddress = ticketAddresses[_winnerNumber-1];
        
        LogLottery("winnerNumber", winnerAddress, _winnerNumber);
        
        uint ticketAmount = tickets[winnerAddress].amountInvested;
        
        uint amountInvested;
        address playerAddress;
        
        uint i;
        uint playersLength = playersIDs.length;
        
        if (ticketAmount <= 0) {
            
            // Нет победителей, возвращаем деньги участникам за исключением комиссии
            for (i = 0; i < playersLength; i++) {
               
                amountInvested = players[ playersIDs[i]].amountInvested;
                
                if (amountInvested > 0) {
                
                    amountInvested = amountInvested - (amountInvested.mul(fee).div(10000));
                    
                    playerAddress = players[ playersIDs[i]].playerAddress;
                    
                    if (amountInvested > 0) {
                        playerAddress.transfer(amountInvested);
                        Transfer( this, playerAddress, amountInvested);
                    }
                
                }
                
            }
            
        } else {
            
            for (i = 0; i < playersLength; i++) {
                
                amountInvested = players[ playersIDs[i]].amountByTicket[winnerAddress];
                if (amountInvested > 0) {
                   
                    playerAddress = players[ playersIDs[i]].playerAddress;
                    
                    // Доля инвестора в выигрышный билет
                    uint playerPercentage = percent(amountInvested, ticketAmount, 4);
                    
                    // Сумма выигрыша без учета комиссии
                    uint profitAmount = jackpot.mul(playerPercentage).div(uint(10000));
                    
                    // Конечная сумма прибыли инвестора
                    profitAmount = profitAmount - (profitAmount.mul(fee).div(10000));
                    
                    if (profitAmount > 0) {
                        playerAddress.transfer(profitAmount);
                        Transfer( this, playerAddress, profitAmount);   
                    }
                
                }
            }      
            
        }
        
        // Обнуляем раунд
        jackpot = 0;
        delete playersIDs;
        delete betsKeys;
        
        for (i = 0; i < ticketAddresses.length; i++) {
            tickets[ ticketAddresses[i]].amountInvested = 0;
        }
    
        startNewRound(roundDuration);
        
    }

}

contract Ticket {
    
    Lottery public lottery;
    
    address public lotteryAddress;
    mapping (address => uint) public balanceOf;
    
    address owner;
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        if (msg.sender != owner) throw;
        _;
    }
    
    function getBalance(address _address) view returns (uint) {
        return _address.balance;
    }
    
    function setLotteryAddress(address _lotteryAddress) onlyOwner {
        
        lotteryAddress = _lotteryAddress;
    
    }
    
    function bet() payable {
        
        if (lotteryAddress == address(0)) throw;
        
        lottery = Lottery(lotteryAddress);
        uint minBet = lottery.getMinBet();
        
        if (msg.value < minBet) throw;
        
        lottery.deposit.value(msg.value)(msg.sender);
        
    }
    
}