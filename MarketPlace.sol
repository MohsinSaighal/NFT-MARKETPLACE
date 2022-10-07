// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./ERC4907.sol";
import "./IERC4907.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

error PriceNotMet(address nftAddress, uint256 tokenId, uint256 price);
error ItemNotForSale(address nftAddress, uint256 tokenId);
error NotListed(address nftAddress, uint256 tokenId);
error AlreadyListed(address nftAddress, uint256 tokenId);
error NoProceeds();
error NotOwner();


// Error thrown for isNotOwner modifier
// error IsNotOwner()

contract NftMarketplace is  ERC4907, ReentrancyGuard {

    ERC20 public tokenAddress;
     constructor(string memory _name, string memory _symbol,address _tokenAddress) ERC4907(_name, _symbol) {
        tokenAddress = ERC20(_tokenAddress);
    }
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;


    struct RentListing {
        address owner;
        address user;
        address nftContract;
        uint256 tokenId;
        uint256 pricePerDay;
        uint256 startDateUNIX; // when the nft can start being rented
        uint256 endDateUNIX; // when the nft can no longer be rented
        uint256 expires; // when the user can no longer rent it
    }

    struct Listing {
        uint256 price;
        address seller;
        uint nftPrice;
        bool active;
    }
    

    event ItemListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price,
        uint256 nftPrice
    );

    event ItemCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ItemBought(
        address indexed buyer,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 nftTokenPrice,
        uint256 price
    );

    event NFTListed(
        address owner,
        address user,
        address nftContract,
        uint256 tokenId,
        uint256 pricePerDay,
        uint256 startDateUNIX,
        uint256 endDateUNIX,
        uint256 expires
    );

     event NFTUnlisted(
        address unlistSender,
        address nftContract,
        uint256 tokenId,
        uint256 refund
    );

    event NFTRented(
        address owner,
        address user,
        address nftContract,
        uint256 tokenId,
        uint256 startDateUNIX,
        uint256 endDateUNIX,
        uint64 expires,
        uint256 rentalFee
    );

    mapping(address => mapping(uint256 => Listing)) private s_listings;
    mapping(address => uint256) private s_proceeds;
    mapping(address => mapping(uint256 => RentListing)) private _listingMap;
    mapping(address => EnumerableSet.UintSet) private _nftContractTokensMap;
    
    EnumerableSet.AddressSet private _nftContracts;


    modifier notListed(
        address nftAddress,
        uint256 tokenId,
        address owner
    ) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price > 0) {
            revert AlreadyListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isListed(address nftAddress, uint256 tokenId) {
        Listing memory listing = s_listings[nftAddress][tokenId];
        if (listing.price <= 0) {
            revert NotListed(nftAddress, tokenId);
        }
        _;
    }

    modifier isOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender != owner) {
            revert NotOwner();
        }
        _;
    }

     // IsNotOwner Modifier - Nft Owner can't buy his/her NFT
    // Modifies buyItem function
    // Owner should only list, cancel listing or update listing
     modifier isNotOwner(
        address nftAddress,
        uint256 tokenId,
        address spender
    ) {
        IERC721 nft = IERC721(nftAddress);
        address owner = nft.ownerOf(tokenId);
        if (spender == owner) {
            revert NotOwner();
        }
        _;
    } 

    /////////////////////
    // Main Functions //
    /////////////////////
    /*
     * @notice Method for listing NFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param price sale price for each item
     */
    function listItem(
        address nftAddress,
        uint256 tokenId,
        uint256 nft_token_Price,
        uint256 price
    )
        external

        notListed(nftAddress, tokenId, msg.sender)
        //isOwner(nftAddress, tokenId, msg.sender)
    {
        require(price > 0,"Price Must Be Above Zero");
       //IERC721 nft = IERC721(nftAddress);       
        //require(nft.getApproved(tokenId)!= address(this),"Not Approved For Market Place");
        IERC721(nftAddress).transferFrom(msg.sender, address(this), tokenId);
        s_listings[nftAddress][tokenId] = Listing(price, msg.sender,nft_token_Price,true);
        emit ItemListed(msg.sender, nftAddress, tokenId, price,nft_token_Price);
    }
    
    /*
     * @notice Method for listing Rentable NFT
     * @param nftContract Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param pricePerDay PerDay Rent for each nft
     * @param startDateUNIX Start Date for each nft
     * @param endDateUNIX   End Date for each nft
     */

    function listRentableNFT(
        address nftContract,
        uint256 tokenId,
        uint256 pricePerDay,
        uint256 startDateUNIX,
        uint256 endDateUNIX
    ) public  nonReentrant {
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner of nft");
        require(pricePerDay > 0, "Rental price should be greater than 0");
        require(startDateUNIX >= block.timestamp, "Start date cannot be in the past");
        require(endDateUNIX >= startDateUNIX, "End date cannot be before the start date");
        require(_listingMap[nftContract][tokenId].nftContract == address(0), "This NFT has already been listed");

        _listingMap[nftContract][tokenId] = RentListing(
            msg.sender,
            address(0),
            nftContract,
            tokenId,
            pricePerDay,
            startDateUNIX,
            endDateUNIX,
            0
        );
        EnumerableSet.add(_nftContractTokensMap[nftContract], tokenId);
        EnumerableSet.add(_nftContracts, nftContract);
        
        emit NFTListed(
            IERC721(nftContract).ownerOf(tokenId),
            address(0),
            nftContract,
            tokenId,
            pricePerDay,
            startDateUNIX,
            endDateUNIX,
            0
        );
    }
    
    /*
     * @notice Method to  Rent NFT
     * @param nftContract Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param expires Expiry for NFT
     */

    function rentNFT(
        address nftContract,
        uint256 tokenId,
        uint64 expires
    ) public payable nonReentrant {
        RentListing storage listing = _listingMap[nftContract][tokenId];
        require(listing.user == address(0) || block.timestamp > listing.expires, "NFT already rented");
        require(expires <= listing.endDateUNIX, "Rental period exceeds max date rentable");
        // Transfer rental fee
        uint256 numDays = (expires - block.timestamp)/60/60/24 + 1;
        uint256 rentalFee = listing.pricePerDay * numDays;
        require(msg.value >= rentalFee, "Not enough ether to cover rental period");
        payable(listing.owner).transfer(rentalFee);
        // Update listing
        //IERC4907(nftContract).setUser(tokenId, msg.sender, expires);
        listing.user = msg.sender;
        listing.expires = expires;

        emit NFTRented(
            IERC721(nftContract).ownerOf(tokenId),
            msg.sender,
            nftContract,
            tokenId,
            listing.startDateUNIX,
            listing.endDateUNIX,
            expires,
            rentalFee
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //require (rentables[tokenId].rentable==false,"Nft Cannot be Sell When its on Rent");
        require(_users[tokenId].expires <= block.timestamp,"You cant Sell Rented Nft");
        super.safeTransferFrom(from, to, tokenId);
    }

    /*
     * @notice Method for cancelling listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function cancelListing(address nftAddress, uint256 tokenId)
        external
        isOwner(nftAddress, tokenId, msg.sender)
        isListed(nftAddress, tokenId)
    {   
        s_listings[nftAddress][tokenId].active = false;
        IERC721(nftAddress).transferFrom(address(this), msg.sender, tokenId);
        emit ItemCanceled(msg.sender, nftAddress, tokenId);
    }
      /*
     * @notice Method for unlistingNFT
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */

    function unlistNFT(address nftContract, uint256 tokenId) public payable nonReentrant {
        RentListing storage listing = _listingMap[nftContract][tokenId];
        require(listing.owner != address(0), "This NFT is not listed");
        require(listing.owner == msg.sender, "Not approved to unlist NFT");
        // fee to be returned to user if unlisted before rental period is up
        // nothing to refund if no renter
        uint256 refund = 0;
        if (listing.user != address(0)) {
            refund = ((listing.expires - block.timestamp) / 60 / 60 / 24 + 1) * listing.pricePerDay;
            require(msg.value >= refund, "Not enough ether to cover refund");
            payable(listing.user).transfer(refund);
        }
        // clean up data
        IERC4907(nftContract).setUser(tokenId, address(0), 0);
        EnumerableSet.remove(_nftContractTokensMap[nftContract], tokenId);
        delete _listingMap[nftContract][tokenId];
        if (EnumerableSet.length(_nftContractTokensMap[nftContract]) == 0) {
            EnumerableSet.remove(_nftContracts, nftContract);
        }

        emit NFTUnlisted(
            msg.sender,
            nftContract,
            tokenId,
            refund
        );
    }

    /*
     * @notice Method for buying listing
     * @notice The owner of an NFT could unapprove the marketplace,
     * which would cause this function to fail
     * Ideally you'd also have a `createOffer` functionality.
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     */
    function buyItem(address nftAddress, uint256 tokenId)
        external
        payable
        isListed(nftAddress, tokenId)
        // isNotOwner(nftAddress, tokenId, msg.sender)
        nonReentrant
    {
        Listing memory listedItem = s_listings[nftAddress][tokenId];
        require(s_listings[nftAddress][tokenId].active = true,"No Such Nft is Listed");
        require (msg.value == listedItem.price,"Price Not Met");
        require(msg.value == listedItem.nftPrice,"Token Price Not Met");

        if(address(tokenAddress) != address(0)){    
           tokenAddress.transferFrom(msg.sender, listedItem.seller, listedItem.nftPrice);
           IERC721(nftAddress).safeTransferFrom(address(this), msg.sender, tokenId);


        }else{
            payable(listedItem.seller).transfer(listedItem.price);
            IERC721(nftAddress).safeTransferFrom(listedItem.seller, msg.sender, tokenId);
            

        }   

        s_proceeds[listedItem.seller] += msg.value;
        s_listings[nftAddress][tokenId].active = false;

             
        emit ItemBought(msg.sender, nftAddress, tokenId, listedItem.price,listedItem.nftPrice);
    }
    

    

    /*
     * @notice Method for updating listing
     * @param nftAddress Address of NFT contract
     * @param tokenId Token ID of NFT
     * @param newPrice Price in Wei of the item
     */
    function updateListing(
        address nftAddress,
        uint256 tokenId,
        uint256 newPrice,
        uint256 nft_token_Price
    )
        external
        isListed(nftAddress, tokenId)
        nonReentrant
        isOwner(nftAddress, tokenId, msg.sender)
    {
        //We should check the value of `newPrice` and revert if it's below zero (like we also check in `listItem()`)
        require(newPrice & nft_token_Price> 0,"Price Must Be Above Zero");
        s_listings[nftAddress][tokenId].price = newPrice;
        s_listings[nftAddress][tokenId].nftPrice = nft_token_Price;
        emit ItemListed(msg.sender, nftAddress, tokenId, newPrice,nft_token_Price);
    }

    /*
     * @notice Method for withdrawing proceeds from sales
     */
    function withdrawProceeds() external {
        uint256 proceeds = s_proceeds[msg.sender];
        if (proceeds <= 0) {
            revert NoProceeds();
        }
        s_proceeds[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: proceeds}("");
        require(success, "Transfer failed");
    }

    /////////////////////
    // Getter Functions //
    /////////////////////

    function getListing(address nftAddress, uint256 tokenId)
        external
        view
        returns (Listing memory)
    {
        return s_listings[nftAddress][tokenId];
    }

    function getProceeds(address seller) external view returns (uint256) {
        return s_proceeds[seller];
    }
}

