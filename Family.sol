pragma solidity ^0.4.0;

contract MultiSigWallet {

    // ##############################################################################################################################
    // DEFINITIONS

    address private owner;                      // Kontratı başlatan adres
    uint constant MIN_SIGNATURES = 2;           // İşlemlerin onayı için gereken minimum onay sayısı
    uint private transactionIdx;                // İşlem numarası
    uint private activeMembers;

    // Ödeme bilgilerini tutan veri yapısı
    struct Transaction {
      address from;                                 // Gönderen adres
      address to;                                   // Alıcı adres
      uint amount;                                  // Miktar
      uint8 signatureCount;                         // İmza sayısı
      mapping (address => uint8) signatures;        // (1 veya 0) işlem onaylandı mı
    }

    // Aile bireylerini tutan veri yapısı
    struct Member {
        uint share;             // Cüzdandaki % payı
        bool isSpouse;          // Yetkili mi
        bool isActive;          // Aktif bir kullanıcı mı
    }

    mapping(address => Member) private members;                        // Üyeler
    mapping (uint => Transaction) private transactions;                // Aktif transferler
    uint[] private pendingTransactions;                                // Beklemedeki transferlerin numarasi tutuluyor
    address[] private activeMemberAddresses;

    // ##############################################################################################################################
    // EVENTS (LOGGING)
    // :    "event" saves events in a log.
    // :    Useful to check what happened before
    // :    Logs can be accessed in WEB3 javascript implementation

    event DepositFunds(address from, uint amount);
    event TransactionCreated(address from, address to, uint amount, uint transactionId);
    event TransactionCompleted(address from, address to, uint amount, uint transactionId);
    event TransactionSigned(address by, uint transactionId);
    event childAdded(address owner, address child);


    // ##############################################################################################################################
    // CONTRACT CONTROL

    // Constructor
    constructor() public {
        owner = msg.sender;
        addMember(msg.sender,1,true,true);
        activeMembers += 1;
    }

    // -- MODIFIER:
    // Check the address if it is one of owners/parents
    // Accessibility: only Owners/Parents 
    modifier isOwner() {                                                                         
        require(members[msg.sender].isSpouse == true);    
        _;
    }

    // Yeni bir üye ekle
    function addMember(address _new_member, uint _share, bool _isSpouse, bool _isActive) private {
        Member memory new_member;
        new_member.share = _share;
        new_member.isSpouse = _isSpouse;
        new_member.isActive = _isActive;
        members[_new_member] = new_member;

        if (_isActive){
            activeMemberAddresses.push(_new_member);
        }
    }

    // Yeni yetkili Üye ekle
    function addOwner(address _new_owner) isOwner public {
        addMember(_new_owner,0,true,true);
        activeMembers += 1;
    }

    // Yetkili üye kaldır
    function removeOwner(address _owner) isOwner public {
        members[owner].isActive = false;
        activeMembers -= 1;
    }

    // Yeni çocuk üye ekle
    function addChild(address _child) isOwner public {
        addMember(_child,0,false,true);
        emit childAdded(msg.sender,_child);             // Yeni bir çocuk eklendi mesajı
        activeMembers += 1;
    }

    // Çocuk üyeyi kaldır
    function removeChild (address _child) isOwner public {
        members[_child].isActive = false;
        activeMembers -= 1;
    }

    // ##############################################################################################################################
    // İşlemler

    // Kontrata varlık ekle
    function () public payable {
        emit DepositFunds(msg.sender, msg.value);                                   // Log that a deposit was made
    }

    // Kontrattan varlık çek
    function withdraw(uint _amount) public {
        transferTo(msg.sender, _amount);
    }

    // -- MODIFIER:
    // Check the address if it is one of owners or children
    // Accessibility: Owners/Parents and Children
    modifier validUser() {                                                                         
        require( members[msg.sender].isActive == true);    
        _;
    }

    // Kontrat varlıklarını belirtilen hesaba aktar
    function transferTo(address _to, uint _amount) validUser public {

        require(address(this).balance >= _amount);
        uint transactionId = transactionIdx++;          // İşlem numarasını güncelle

        // yeni bir işlem oluştur
        Transaction memory transaction;
        transaction.from = msg.sender;
        transaction.to = _to;
        transaction.amount = _amount;

        // İşlemi +1 onay ver (yetkili kişi ise)
        if (members[msg.sender].isSpouse){
            transaction.signatureCount = 1;
        } else {    // Çocuklar kendi başlarına onay veremezler
            transaction.signatureCount = 0;
        }

        transactions[transactionId] = transaction;
        pendingTransactions.push(transactionId);

        emit TransactionCreated(msg.sender, _to, _amount, transactionId);             
    }


    // Transfer işlemini onayla
    function signTransaction(uint transactionId) isOwner public {

      Transaction storage transaction = transactions[transactionId];

      require(0x0 != transaction.from);                                     // İşlem var mı kontrol et
      require(msg.sender != transaction.from);                              // İşlemi oluşturan onay veremez
      require(transaction.signatures[msg.sender] != 1);                     // Aynı kişinin imzalamasını engelle

      transaction.signatures[msg.sender] = 1;
      transaction.signatureCount++;

      emit TransactionSigned(msg.sender, transactionId);                    

      if (transaction.signatureCount >= MIN_SIGNATURES) {
        require(address(this).balance >= transaction.amount);
        transaction.to.transfer(transaction.amount);
        emit TransactionCompleted(transaction.from, transaction.to, transaction.amount, transactionId); 
        deleteTransaction(transactionId);
      }
    }

    function deleteTransaction(uint transactionId) validUser public {
    
        uint8 replace = 0;

        // We cannot simply delete an index in dynamic array in solidity :(
        // We need to loop the array, delete the index and reorder the remaining elements
        for(uint i = 0; i < pendingTransactions.length; i++) {
            if (1 == replace) {
            pendingTransactions[i-1] = pendingTransactions[i];
            } else if (transactionId == pendingTransactions[i]) {
            replace = 1;
            }
        }

        assert(replace == 1);                                                   // Protection when replace = 0
        delete pendingTransactions[pendingTransactions.length - 1];             // Delete the last elements
        pendingTransactions.length--;                                           // Update
        delete transactions[transactionId];                                     // Deleting from a mapping
    }

    // TO DO: Divorce needs to be approved by spouses or lawyers
    // TO DO: Find a way to delete an activeMember address
    function divorce() isOwner public{
        uint share = address(this).balance / activeMembers;

        for (uint i = 0; i < activeMemberAddresses.length; i++){
            activeMemberAddresses[i].transfer(share);
        }
    }

    // ##############################################################################################################################
    // VIEW FUNCTIONS

    // Retrieve the balance of the contract
    function walletBalance()  public view returns (uint) {
        return address(this).balance;
    }

    // View pending transactions
    function getPendingTransactions()  public view returns (uint[]) {
        return pendingTransactions;
    }

    function getActiveMemberCount() public view returns (uint) {
        return activeMembers;
    }

    function getActiveMembers() public view returns (address[]) {
        return activeMemberAddresses;
    }
}