Inspired by https://twitter.com/dhof/status/1566823568616333316

Code provided as-is, not audited, not even fully functional. Still work-in-progress. Use at your own risk.

CC0 - do whatever you want with the source code.

[Install Foundry](https://book.getfoundry.sh/getting-started/installation) to run the tests.

Started by [@w1nt3r_eth](https://twitter.com/w1nt3r_eth)
Finished(?) by [@pmespresso](https://github.com/pmespresso)

## Specs

#### Participating

- [x] 1 NFT = 1 Player just verify you own a valid NFT to play. This is not part of your spoils
- [ ] Only certain preapproved NFTs can join (make it elitist to piss ppl off enough to fork it and make their own lol)
- [x] Pay entry free to create player. Entry fee goes to the player's "spoils," and ETH Balance attached to your player. Game takes nothing.
- [x] If you defeat a player, you win all their accumulated spoils. If you are defeated, you lose all your spoils.
- [x] Spoils cannot be withdrawn till end of game
- [ ] Either the max player limit is reached and `start()` is called automatically, or the `startCountdown` reaches 0 and `start()` is called by the Chainlink Keeper.

#### Turns

- [ ] Turn based, 1 turn every 36 hours
  - [ ] (**editor's commment**: 36 hours eh? seems not very engaging...also a game gonna take fucking forever...also will need notifications so 90% of players don't just disappear after a couple moves)
  - [ ] Submit stage (18 hours): Make your move and submit a hash of it to initiall hide from other players
  - [ ] Reveal stage (18 hours); Submit plaintext version of your move and its password to reveal it
    - [ ] If you don't rewveal your move you are penalized heavily (TBD what is the penalty, needs to outweigh not revealing move)
  - [ ] Resolution (instant-ish): All moves are process, and next submit stage begins (Chainlink Keeper calls `rollDice()` then `resolve()` every 18 hours)

#### Moving

- [x] Players are initially spawned on 2D grid map in random starting spots. All starting spots are equidistant from one another.
- [x] You can [MOVE] to one adjacent grid spot per turn. You can also [REST] in the grid spot you currently occupy.
- [ ] Grid spots can reveal two things the firs time they are encountered:
  - **Resources** which are picked up immediately and can be used to level up and train the character
  - **Effects** which are either continuous (Passive AOE), or triggered (provies additional [ABILITY] that can be used during a turn).
  - **Enemies** some other player who is already occupying the square (in which case you gotta battle it out)
- [ ] Once a grid spot is revealed it is revealed to all players

#### Battles

- [x] When 2 players occupy the same grid slot, a battle occurs. Battles are resolved by a series of calculations (simple comparison of stats like att/def/HP/etc. with rock-paper-sissors specialization) along with a dice roll.
- [x] If allies, don't fight
<!-- - Losing player is removed from map, permanently loses spoils to the winner -->
- [x] Losing player is moved to a "jail" cell, which is hidden from the players (only contract can view)
- [ ] If someone accidentally lands on the jail cell, they can roll dice to jailbreak (e.g. if their alliance members are in there).
- [ ] If more than 2 on same grid slot, random 2 are chosen for battle.
- [ ] (**editor's comment**: possibly multiples of 2 can be chosen and the lucky(?) odd one sits out)

#### Alliances

- [x] Players can choose to form alliances or apply to alliances.
- [x] The player who forms the alliances is the **leader** and has sole rights over accepting or ignoring applications. (**editor's comment**: might be an interesting place to attach a mini-dao like structure to vote in / kick members)
- [x] Players in an alliance will not attack each other then occupying the same slot.
- [ ] If an alliance wins, all of the spoils between the players in the alliance are split proportionately to what they put up at stake.
- [ ] (**editors'comment**: are battles fought with a representative of the alliance or the cumulative stats of the alliance?)
- [x] Players can only be in 1 alliance
- [x] Alliances have a max membership count (TBD, based on intended total number of players)
- [x] N.B. Pseudo "superalliances" can still be formed outside of the game through social contracts or smart contracts. But cannot guarantee there won't be betrayals. (**editor's comment** Strategic/Tactical betrayal is a fun component of any good strategy game :D)

#### Win Condition

- [x] Last player
- [x] Last alliance standing
- [x] At this point the winers may withdraw their spoils
- [ ] (**editor's comment**: In order to add more chaos and tact in choosing your allies, if an alliance is the last standing, they could anonymously vote to continue as FFA, or be satisfied with splitting the spoils.)

#### Miscellaneous

- [x] Every 5 turns (a little over a week), the play field is reduced in size (Battle Royale/Fortnite,Warzone, etc.) to force more battles over time and push towards a win.
- [x] Every time a player submits a bad move, they are penalized byy 0.05 ether until they cannot pay anymore at which point they are sent to jail.
- [ ]
- [ ] Items places randomly along the grid could power up attributes like hp or attack and even allow teleport
