// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

error UserNotAssociatedWithTrade();
error AssetNotTransferredBySeller();
error TradeCompleted();
error TradeNotActive();
error MinimumVotesNotReached();
error EqualVotesWaitForMoreVotes();

contract Marketplace {
    enum TradeStatus {
        DEFAULT,
        STARTED,
        TRANSFERRED,
        COMPLETED
    }

    struct Trade {
        bytes productId;
        address buyer;
        address seller;
        TradeStatus tradeStatus;
        bool isDisputed;
        bool isDisputeOngoing;
        address disputeWinner;
    }
    struct Dispute {
        address buyer;
        uint256 votesForBuyer;
        address seller;
        uint256 votesForSeller;
        uint256 totalVotes;
        uint256 minimumVotesRequired;
    }
    struct Product {
        string name;
        uint256 price;
        uint256 quantity;
    }
    struct Reputation {
        uint256 completedTrades;
        uint256 pendingTrades;
        uint256 pendingDisputes;
        uint256 wonDisputes;
        uint256 lostDisputes;
        uint256 clearedDisputes;
    }
    mapping(bytes => Product) public productDetails;
    mapping(address => bytes[]) public ownedProducts;
    mapping(bytes => address) public productOwner;
    bytes[] public listOfProducts;

    mapping(bytes => Trade) public trades;
    mapping(bytes => Dispute) public tradeDisputes;
    mapping(address => mapping(bytes => bool)) public votesForDispute;
    mapping(bytes => bytes) public productToTrade;

    mapping(address => Reputation) public userReputation;

    event ProductListed(address owner, bytes productId);
    event TradeStarted(
        address buyer,
        address seller,
        bytes productId,
        bytes tradeId
    );

    constructor() {}

    function listProduct(Product memory _product)
        public
        returns (bytes memory)
    {
        bytes memory productId = abi.encode(_product);
        productDetails[productId] = _product;
        productOwner[productId] = msg.sender;
        bytes[] memory arr = new bytes[](ownedProducts[msg.sender].length + 1);

        for (uint256 i = 0; i < ownedProducts[msg.sender].length; i++) {
            arr[i] = ownedProducts[msg.sender][i];
        }
        arr[ownedProducts[msg.sender].length] = productId;

        ownedProducts[msg.sender] = arr;
        listOfProducts.push(productId);
        emit ProductListed(msg.sender, productId);

        return productId;
    }

    // 0x00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000005537572616a000000000000000000000000000000000000000000000000000000
    // called by buyer
    function buyProduct(bytes memory productId) public payable {
        require(
            productToTrade[productId].length == 0,
            "The product is already in trade."
        );
        require(
            productDetails[productId].quantity != 0,
            "Product doesn't exist"
        );
        require(
            productOwner[productId] != msg.sender,
            "Cannot buy your own product."
        );
        require(productOwner[productId] != address(0x0), "Product not owned.");
        require(
            msg.value >= productDetails[productId].price,
            "Insufficient amount transferred"
        );
        Trade memory trade = Trade(
            productId,
            msg.sender,
            productOwner[productId],
            TradeStatus.STARTED,
            false,
            false,
            address(0x0)
        );
        bytes memory tradeId = abi.encode(trade);

        trades[tradeId] = trade;
        productToTrade[productId] = tradeId;

        userReputation[msg.sender].pendingTrades += 1;
        userReputation[productOwner[productId]].pendingTrades += 1;
        emit TradeStarted(
            msg.sender,
            productOwner[productId],
            productId,
            tradeId
        );
    }

    // called by seller to complete the buy request
    function completeBuyProcess(bytes memory tradeId) public {
        bytes memory productId = trades[tradeId].productId;
        require(productId.length != 0, "Invalid TradeId");
        require(
            trades[tradeId].tradeStatus == TradeStatus.STARTED,
            "No trade started."
        );
        require(
            keccak256(productToTrade[productId]) == keccak256(tradeId),
            "Product not on trade"
        );
        require(
            productDetails[productId].quantity != 0,
            "Product doesn't exist"
        );
        require(
            productOwner[productId] == msg.sender,
            "You are not the product owner."
        );
        require(
            productOwner[productId] != address(0x0),
            "Product not available."
        );

        address oldOwner = productOwner[productId];

        // new owner
        bytes[] memory arr = new bytes[](ownedProducts[msg.sender].length + 1);
        for (uint256 i = 0; i < ownedProducts[msg.sender].length; i++) {
            arr[i] = ownedProducts[msg.sender][i];
        }
        arr[ownedProducts[msg.sender].length] = productId;
        ownedProducts[msg.sender] = arr;

        // old owner
        bytes[] memory arr2 = new bytes[](ownedProducts[oldOwner].length - 1);
        bool productFound = false;
        for (uint256 i = 0; i < arr2.length; i++) {
            if (keccak256(ownedProducts[oldOwner][i]) == keccak256(productId)) {
                productFound = true;
            } else {
                if (productFound == true) {
                    arr2[i] = ownedProducts[oldOwner][i + 1];
                } else {
                    arr2[i] = ownedProducts[oldOwner][i];
                }
            }
        }
        ownedProducts[oldOwner] = arr2;
        trades[tradeId].tradeStatus = TradeStatus.TRANSFERRED;
        // payable(msg.sender).transfer(productDetails[productId].price);
    }

    // called by buyer to confirm the trade and release funds to transfer to seller
    function confirmTrade(bytes memory tradeId) public {
        bytes memory productId = trades[tradeId].productId;
        require(
            trades[tradeId].tradeStatus == TradeStatus.TRANSFERRED,
            "Asset not transferred yet."
        );
        require(productId.length != 0, "Invalid TradeId");
        require(
            keccak256(productToTrade[productId]) == keccak256(tradeId),
            "Product not on trade"
        );
        require(
            productDetails[productId].quantity != 0,
            "Product doesn't exist"
        );
        require(
            productOwner[productId] != msg.sender,
            "You are not the product owner."
        );
        require(
            productOwner[productId] != address(0x0),
            "Product not available."
        );

        address oldOwner = productOwner[productId];

        productOwner[productId] = msg.sender;

        // new owner
        trades[tradeId].tradeStatus = TradeStatus.COMPLETED;
        userReputation[msg.sender].pendingTrades -= 1;
        userReputation[msg.sender].completedTrades += 1;
        userReputation[oldOwner].pendingTrades -= 1;
        userReputation[oldOwner].completedTrades += 1;

        if (
            trades[tradeId].isDisputed == true &&
            trades[tradeId].isDisputeOngoing == true
        ) {
            trades[tradeId].isDisputed = false;
            trades[tradeId].isDisputeOngoing = false;

            userReputation[msg.sender].pendingDisputes -= 1;
            userReputation[msg.sender].clearedDisputes += 1;
            userReputation[oldOwner].pendingDisputes -= 1;
            userReputation[oldOwner].clearedDisputes += 1;
        }

        payable(oldOwner).transfer(productDetails[productId].price);
        delete productToTrade[productId];
    }

    // GETTERS
    function getListOfProducts() public view returns (bytes[] memory) {
        return listOfProducts;
    }

    function getUserDetails(address _user)
        public
        view
        returns (Reputation memory)
    {
        return userReputation[_user];
    }

    // Dispute
    function raiseDispute(bytes memory tradeId) public {
        Trade memory tradeDetails = trades[tradeId];
        if (tradeDetails.tradeStatus == TradeStatus.DEFAULT) {
            revert TradeNotActive();
        } else if (tradeDetails.tradeStatus == TradeStatus.COMPLETED) {
            revert TradeCompleted();
        } else if (tradeDetails.tradeStatus == TradeStatus.STARTED) {
            revert AssetNotTransferredBySeller();
        } else if (tradeDetails.tradeStatus == TradeStatus.TRANSFERRED) {
            trades[tradeId].isDisputed = true;
            trades[tradeId].isDisputeOngoing = true;

            userReputation[tradeDetails.buyer].pendingDisputes += 1;
            userReputation[tradeDetails.seller].pendingDisputes += 1;

            tradeDisputes[tradeId] = Dispute(
                tradeDetails.buyer,
                0,
                tradeDetails.seller,
                0,
                0,
                1
            );
        } else {
            revert UserNotAssociatedWithTrade();
        }
    }

    function voteForDispute(bytes memory tradeId, address user) public {
        Trade memory tradeDetails = trades[tradeId];
        require(
            tradeDetails.isDisputeOngoing == true,
            "No ongoing dispute to vote"
        );
        require(
            msg.sender != tradeDetails.buyer &&
                msg.sender != tradeDetails.seller,
            "Cannot vote for your own dispute"
        );
        require(votesForDispute[msg.sender][tradeId] == false, "Already voted");
        require(
            user == tradeDetails.buyer || user == tradeDetails.seller,
            "Provided address is neither buyer or seller."
        );

        if (user == tradeDetails.buyer) {
            tradeDisputes[tradeId].votesForBuyer += 1;
        } else {
            tradeDisputes[tradeId].votesForSeller += 1;
        }
        tradeDisputes[tradeId].totalVotes += 1;
        votesForDispute[msg.sender][tradeId] == true;
    }

    function finishDispute(bytes memory tradeId) public {
        Trade memory tradeDetails = trades[tradeId];
        Dispute memory disputeDetails = tradeDisputes[tradeId];
        require(
            tradeDetails.isDisputeOngoing == true,
            "No ongoing dispute to vote"
        );
        require(
            msg.sender != tradeDetails.buyer &&
                msg.sender != tradeDetails.seller,
            "Cannot finish your own dispute"
        );

        if (disputeDetails.totalVotes < disputeDetails.minimumVotesRequired) {
            revert MinimumVotesNotReached();
        } else {
            if (disputeDetails.votesForBuyer == disputeDetails.votesForSeller) {
                revert EqualVotesWaitForMoreVotes();
            } else {
                trades[tradeId].tradeStatus = TradeStatus.COMPLETED;
                userReputation[tradeDetails.buyer].pendingTrades -= 1;
                userReputation[tradeDetails.buyer].completedTrades += 1;
                userReputation[tradeDetails.seller].pendingTrades -= 1;
                userReputation[tradeDetails.seller].completedTrades += 1;

                trades[tradeId].isDisputeOngoing = false;
                userReputation[tradeDetails.buyer].pendingDisputes -= 1;
                userReputation[tradeDetails.seller].pendingDisputes -= 1;

                if (
                    disputeDetails.votesForBuyer > disputeDetails.votesForSeller
                ) {
                    productOwner[tradeDetails.productId] = tradeDetails.buyer;

                    // new owner
                    bytes[] memory arr = new bytes[](
                        ownedProducts[tradeDetails.seller].length + 1
                    );
                    for (
                        uint256 i = 0;
                        i < ownedProducts[tradeDetails.seller].length;
                        i++
                    ) {
                        arr[i] = ownedProducts[tradeDetails.seller][i];
                    }
                    arr[
                        ownedProducts[tradeDetails.seller].length
                    ] = tradeDetails.productId;
                    ownedProducts[tradeDetails.seller] = arr;

                    // old owner
                    bytes[] memory arr2 = new bytes[](
                        ownedProducts[tradeDetails.buyer].length - 1
                    );
                    bool productFound = false;
                    for (uint256 i = 0; i < arr2.length; i++) {
                        if (
                            keccak256(ownedProducts[tradeDetails.buyer][i]) ==
                            keccak256(tradeDetails.productId)
                        ) {
                            productFound = true;
                        } else {
                            if (productFound == true) {
                                arr2[i] = ownedProducts[tradeDetails.buyer][
                                    i + 1
                                ];
                            } else {
                                arr2[i] = ownedProducts[tradeDetails.buyer][i];
                            }
                        }
                    }
                    ownedProducts[tradeDetails.buyer] = arr2;

                    payable(tradeDetails.buyer).transfer(
                        productDetails[tradeDetails.productId].price
                    );

                    trades[tradeId].disputeWinner = tradeDetails.buyer;

                    userReputation[tradeDetails.buyer].wonDisputes += 1;
                    userReputation[tradeDetails.seller].lostDisputes += 1;
                } else {
                    productOwner[tradeDetails.productId] = tradeDetails.buyer;
                    payable(tradeDetails.seller).transfer(
                        productDetails[tradeDetails.productId].price
                    );

                    trades[tradeId].disputeWinner = tradeDetails.seller;
                    userReputation[tradeDetails.buyer].lostDisputes += 1;
                    userReputation[tradeDetails.seller].wonDisputes += 1;
                }
            }
        }
    }
}
