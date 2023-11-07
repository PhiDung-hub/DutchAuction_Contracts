# Dutch Auction Demo


## Features

+ **Reusable** [✅]: A single `DutchAuction` contract can initiate multiple auction from `IAuctionableToken` compliant tokens.
  
+ **Composable** [✅]: Auction token and Auction contract are separated, each can be extended with arbitrary logic.

+ **Resilience** [✅]: Contract is robust against re-entrancy attack. NOT PUBLICLY AUDITED YET, USE AT YOUR OWN RISK!

+ **Gas Efficient** [✅]: Try running gas profile to see result (**@see** `Local Instruction / Run tasks / Test`)

    + `bid()` consumes about _**100k gas**_.

    + `startAuction()` consumes about _**300k gas**_.

    + `clearAuction()` consumes about _**23k gas / participant**_.



## Repo structure

...

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
