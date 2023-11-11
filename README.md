# Dutch Auction Demo


## Features

+ **Basic Features:**  
    + Start auction
    + Bid
    + Clear auction
        + Distribute the tokens to successful bidders.
        + Burn the remaining tokens if auction is not sold out.
    + block.timestamp to ensures time sensitive functionalities.


+ **Reusable** [✅]: A single `DutchAuction` contract can initiate multiple auction from `IAuctionableToken` compliant tokens. Dutch auction contract can conduct multiple auctions on the same or different types of token, given total auction supply and pricing curve.

+ **Composable** [✅]: Auction token and Auction contract are separated, each can be extended with arbitrary logic.

+ **Resilience** [✅]: Contract is robust against re-entrancy attack. Manipulating states before external payable calls. Utilizing Reentrancy Guard, with consideration of Transient storage [EIP-1153] to improve efficiency. NOT PUBLICLY AUDITED YET, USE AT YOUR OWN RISK!

+ **Gas Efficient** [✅]: Try running gas profile to see result (**@see** `Local Instruction / Run tasks / Test`)

    + `bid()` consumes about _**100k gas**_.

    + `startAuction()` consumes about _**300k gas**_.

    + `clearAuction()` consumes about _**23k gas / participant**_.

+ **Test-Driven Development** [✅]: Each functionality of the contract has been tested exhaustively.

+ **Additional features:**
    + Auction operator can set a commitment amount limit per bidder, preventing a single actor from harvesting all the auctioned token.
    + If the auction has not been cleared 10 minutes after it expired, successful bidders are allowed to withdraw their committed ethers.



## Repo structure

+  'src/': Contains the source code of the repository

+  'test/': Contains the test scripts to test the functionalities of Contracts

+  'script/': Contains the scripts to deploy Tokens and Dutch Auction Contracts, and to run startAuction, clearAuction and withdraw

+  'lib/': Contains the necessary imports

## Local Instruction

### 1. Install foundry tool chains.

Follow instructions at (https://book.getfoundry.sh/getting-started/installation)[https://book.getfoundry.sh/getting-started/installation]

### 2. Run tasks

#### Compile 

```
forge compile
```

=> Check `./out` folder.

#### Test

```
forge test
```

With gas report 

```
forge test --gas-report
```

For specific contract

```
forge test --mc <CONTRACT_TO_MATCH>
```

#### Run scripts

...

#### Cases

Token parameters:
+ maxSupply: 10000


Case 1: Auction is not sold out
+ token = IAuctionableToken
+ duration = 20 minutes
+ totalSupply = 100
+ startPrice = 2 * 10 ** 16 (0.002 ETH) [2ETH to sold out immediately]
+ reservePrice 1 * 10 ** 16 (0.001 ETH)
+ 10% -> maxWei = 0.01  ETH.


Bidder 1: Bid 0.002 ETH at start of auction
Bidder 2: Bid 0.002 ETH at 5 minutes
Bidder 2: Bid 0.05 ETH at 7 minutes
Show initial balance
Show refund happens (aka, only 0.008 ETH deducted instead of 0.05 ETH), check balance in wallet

After 20 minutes, clearAuciton
Show tokens are distributed to the bidders
Bidder 1: 2 tokens
Bidder 2: 10 tokens

Case 2: Auction is sold out
+ token = IAuctionableToken
+ duration = 20 minutes
+ totalSupply = 100
+ startPrice = 2 * 10 ** 16 (0.002 ETH) [2ETH to sold out immediately]
+ reservePrice 1 * 10 ** 16 (0.001 ETH)
+ 10000% -> maxWei =  0.1 ETH.

Bidder 1: Bid 0.002 ETH at start of auction
Bidder 2: Bid 0.3 ETH at 2 minutes
Wait 10 minutes, Bidder 1 withdraw -> Gets back his 0.002 ETH
Clear Auction
Bidder 2: get all 100 tokens and get some ETH back

## Flowchart
![Dutch Auction Flowchart](./Dutch_Auction_Flowchart.png)