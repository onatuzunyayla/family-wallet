
pragma solidity ^0.4.0;

contract MultiSigWallet {

    // ##############################################################################################################################
    // DEFINITIONS

    address private _owner;                     // Kontartı başlatan adres
    uint constant MIN_SIGNATURES = 2;           // İşlemlerin onayı için gereken minimum onay sayısı
    uint private _transactionIdx;               // İşlem numarası

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

    mapping(address => Member) private _members;
    mapping (uint => Transaction) private _transactions;                // Active transactions
    uint[] private _pendingTransactions;                                // Holds the index of pending transaction(s)

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
        _owner = msg.sender;
        addMember(msg.sender,1,true,true);
    }

    // -- MODIFIER:
    // Check the address if it is one of owners/parents
    // Accessibility: only Owners/Parents 
    modifier isOwner() {                                                                         
        require(_members[msg.sender].isSpouse == true);    
        _;
    }


    // Yeni bir üye ekle
    function addMember(address caller, uint _share, bool _isSpouse, bool _isActive) private {
        Member memory new_member;
        new_member.share = _share;
        new_member.isSpouse = _isSpouse;
        new_member.isActive = _isActive;
        _members[caller] = new_member;
    }

    // Yeni yetkili Üye ekle
    function addOwner(address owner) isOwner public {
        addMember(owner,0,true,true);
    }

    // Yetkili üye kaldır
    function removeOwner(address owner) isOwner public {
        _members[owner].isActive = false;
    }

    // Yeni çocuk üye ekle
    function addChild(address child) isOwner public {
        addMember(child,0,false,true);
        emit childAdded(msg.sender,child);           // Yeni bir çocuk eklendi mesajı
    }

    // Çocuk üyeyi kaldır
    function removeChild (address child) isOwner public {
        _members[child].isActive = false;
    }


    // ##############################################################################################################################
    // İşlemler

    // Kontrata varlık ekle
    function () public payable {
        emit DepositFunds(msg.sender, msg.value);                                   // Log that a deposit was made
    }

    // Kontrattan varlık çek
    function withdraw(uint amount) public {
        transferTo(msg.sender, amount);
    }

    // -- MODIFIER:
    // Check the address if it is one of owners or children
    // Accessibility: Owners/Parents and Children
    modifier validUser() {                                                                         
        require( _members[msg.sender].isActive == true);    
        _;
    }

    // Kontrat varlıklarını belirtilen hesaba aktar
    function transferTo(address to, uint amount) validUser public {

        require(address(this).balance >= amount);
        uint transactionId = _transactionIdx++;          // İşlem numarasını güncelle

        // yeni bir işlem oluştur
        Transaction memory transaction;
        transaction.from = msg.sender;
        transaction.to = to;
        transaction.amount = amount;

        // İşlemi +1 onay ver (yetkili kişi ise)
        if (_members[msg.sender].isSpouse){
            transaction.signatureCount = 1;
        } else {    // Çocuklar kendi başlarına onay veremezler
            transaction.signatureCount = 0;
        }

        _transactions[transactionId] = transaction;
        _pendingTransactions.push(transactionId);

        emit TransactionCreated(msg.sender, to, amount, transactionId);             
    }


    // Transfer işlemini onayla
    function signTransaction(uint transactionId) isOwner public {

      Transaction storage transaction = _transactions[transactionId];

      require(0x0 != transaction.from);                                     // Tİşlem var mı kontrol et
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
        for(uint i = 0; i < _pendingTransactions.length; i++) {
            if (1 == replace) {
            _pendingTransactions[i-1] = _pendingTransactions[i];
            } else if (transactionId == _pendingTransactions[i]) {
            replace = 1;
            }
        }

        assert(replace == 1);                                                   // Protection when replace = 0
        delete _pendingTransactions[_pendingTransactions.length - 1];           // Delete the last elements
        _pendingTransactions.length--;                                          // Update
        delete _transactions[transactionId];                                    // Deleting from a mapping
    }

    // ##############################################################################################################################
    // VIEW FUNCTIONS

    // Retrieve the balance of the contract
    function walletBalance()  public view returns (uint) {
      return address(this).balance;
    }

    // View pending transactions
    function getPendingTransactions()  public view returns (uint[]) {
      return _pendingTransactions;
    }
}