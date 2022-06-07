pragma solidity ^0.4.0;

contract MultiSigWallet {

    // ##############################################################################################################################
    // Değişken tanımlamaları

    address private owner;                      // Kontratı başlatan adres
    uint constant MIN_SIGNATURES = 2;           // İşlemlerin onayı için gereken minimum onay sayısı
    uint private transactionIdx;                // İşlem numarası
    uint private activeMembers;                 // Kontrattakı aktif üye sayısı

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

    mapping(address => Member) private members;                             // Üyeler
    mapping (uint => Transaction) private transactions;                     // Aktif transferler
    mapping (address => bool) private divorceSigned;                        // Aktif transferler

    uint[] private pendingTransactions;                                     // Beklemedeki transferlerin numarasi tutuluyor
    address[] private activeMemberAddresses;
    uint8 divorceSignatureCount;

    // ##############################################################################################################################
    // EVENTS (LOGGING)
    // :    "event" tanımlamaları gerçekleşen olayları kayıt defterine kaydediyor.
    // :    Kayıtlar WEB3 javascript ile görüntelenebilir

    event DepositFunds(address from, uint amount);
    event TransactionCreated(address from, address to, uint amount, uint transactionId);
    event TransactionCompleted(address from, address to, uint amount, uint transactionId);
    event TransactionSigned(address by, uint transactionId);
    event childAdded(address owner, address child);

    // ##############################################################################################################################
    // Kontrat Kontrol yapılari

    // Constructor
    constructor() public {
        owner = msg.sender;
        addMember(msg.sender,1,true,true);
        activeMembers += 1;
    }

    // -- MODIFIER:
    // Çağıran adresin yetkisini kontrol ediyor
    // Erişebilirlik: kontrat sahibi ve yetkili üyeler
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

    // TO DO: 
    // Create a function to remove Member addresses from activeMembers
    // 
    // function removeMember
    //
    //
    //

    // Yeni yetkili Üye ekle
    function addOwner(address _new_owner) isOwner public {
        addMember(_new_owner,0,true,true);
        activeMembers += 1;
    }

    // Yetkili üye kaldır
    function removeOwner(address _owner) isOwner public {
        members[_owner].isActive = false;
        activeMembers -= 1;
        // removeMember()
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
        // removeMember()
    }

    // ##############################################################################################################################
    // İşlemler

    // Kontrata varlık ekle
    function () public payable {
        emit DepositFunds(msg.sender, msg.value);                                   // Depozito işlemini kayıt defterine ekle
    }

    // Kontrattan varlık çek
    function withdraw(uint _amount) public {
        transferTo(msg.sender, _amount);
    }

    // -- MODIFIER:
    // Çağıran adresin aktif bir üye olduğunu kontrol et
    // Erişebilirlik: aktif üyeler
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
    function signTransaction(uint _transactionId) isOwner public {

      Transaction storage transaction = transactions[_transactionId];

      require(0x0 != transaction.from);                                     // Böyle bir işlem var mı kontrol et
      require(msg.sender != transaction.from);                              // İşlemi oluşturan onay veremez
      require(transaction.signatures[msg.sender] != 1);                     // Aynı kişinin imzalamasını engelle

      transaction.signatures[msg.sender] = 1;
      transaction.signatureCount++;

      emit TransactionSigned(msg.sender, _transactionId);                    

      if (transaction.signatureCount >= MIN_SIGNATURES) {
        require(address(this).balance >= transaction.amount);
        transaction.to.transfer(transaction.amount);
        emit TransactionCompleted(transaction.from, transaction.to, transaction.amount, _transactionId); 
        deleteTransaction(_transactionId);
      }
    }

    function deleteTransaction(uint _transactionId) validUser public {
    
        uint8 replace = 0;

        // We cannot simply delete an index in dynamic array in solidity :(
        // We need to loop the array, delete the index and reorder the remaining elements
        for(uint i = 0; i < pendingTransactions.length; i++) {
            if (1 == replace) {
            pendingTransactions[i-1] = pendingTransactions[i];
            } else if (_transactionId == pendingTransactions[i]) {
            replace = 1;
            }
        }

        assert(replace == 1);                                                   // Protection when replace = 0
        delete pendingTransactions[pendingTransactions.length - 1];             // Son elementi sil
        pendingTransactions.length--;                                           // Güncelle
        delete transactions[_transactionId];                                    // Deleting from a mapping
    }

    // TO DO: Find a way to delete an activeMember address
    function divorce() isOwner public{
        require(divorceSignatureCount >= MIN_SIGNATURES);

        uint share = address(this).balance / activeMembers;

        for (uint i = 0; i < activeMemberAddresses.length; i++){
            activeMemberAddresses[i].transfer(share);
        }
    }

    // Boşanma için imza at
    function signDivorce() isOwner public {
        require(divorceSigned[msg.sender] == false);
        divorceSigned[msg.sender] = true;
        divorceSignatureCount++;
    }

    // Boşanma imzasını geri al
    function unsignDivorce() isOwner public {
        require(divorceSigned[msg.sender] == true);
        divorceSigned[msg.sender] = false;
        divorceSignatureCount--;
    }

    // ##############################################################################################################################
    // Görüntüleyici Fonksiyonlar

    // Retrieve the balance of the contract
    function walletBalance()  public view returns (uint) {
        return address(this).balance;
    }

    // Bekleyen transferleri görüntüle
    function getPendingTransactions()  public view returns (uint[]) {
        return pendingTransactions;
    }

    // Aktif üye sayısını görüntüle
    function getActiveMemberCount() public view returns (uint) {
        return activeMembers;
    }

    // Aktif üye adreslerine görüntüle
    function getActiveMembers() public view returns (address[]) {
        return activeMemberAddresses;
    }

    // Boşanma imza sayısını görüntüle
    function divorceSignCount() public view returns (uint8) {
        return divorceSignatureCount;
    }
}